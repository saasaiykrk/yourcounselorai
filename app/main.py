"""
HTTP API (FastAPI). The phone talks ONLY to this service; it never holds the
Anthropic key, the WHO key or the database key.

Endpoints (all JSON, all require a Supabase Auth JWT except /healthz):
  GET  /healthz   (local; Cloud Run's front end reserves paths ending in "z")
  GET  /health    (same response; use this one on *.run.app)
  GET  /v1/me                         → profile, level, verification status
  POST /v1/profile                    → role + registration number at signup (status=pending)
  PATCH /v1/profile                   → the clinician edits their details (role/registration change → re-verify)
  POST /v1/consult                    → one consult turn (inspected before return)
  POST /v1/incidents                  → "Report a problem" button on any reply
  GET  /v1/history?q=&mode=           → the clinician's own past consults (History tab)
  GET  /v1/history/{id}               → one past consult, read-only
  PATCH /v1/history/{id}              → set or clear its label (identifier-checked)
  DELETE /v1/history/{id}             → hide it from History (kept for audit until retention)
  POST /v1/consultations              → guided consultation: start with the case → first question
  GET  /v1/consultations              → unfinished guided consultations to continue
  GET  /v1/consultations/{id}         → one consultation (and its report once written)
  POST /v1/consultations/{id}/reply   → answer · don't know · skip · finish · confirm safety
  PATCH /v1/consultations/{id}/facts  → correct the collected facts (no model call)
  POST /v1/consultations/{id}/report  → write the fixed Consultation Report (Mode R; inspected)
  GET  /v1/admin/clinicians?status=   → admin: pending / verified / rejected registrations
  PATCH /v1/admin/clinicians/{id}     → admin verifies registration, sets L1/L2/L3
  GET  /v1/admin/incidents?status=    → admin: "Report a problem" items and held-back replies
  GET  /v1/admin/incidents/{id}       → admin: one incident with its de-identified turn
  GET  /v1/admin/incidents/{id}/held-back → admin web page only: the held-back replies (audited)
  PATCH /v1/admin/incidents/{id}      → admin: triage status + reviewer note
  GET  /v1/admin/clinicians/{id}/consults → admin: a clinician's consults, incl. hidden (audited)
  GET  /v1/admin/consults/{id}        → admin: one consult (audited)
  POST /v1/admin/consults/{id}/pdf    → admin: records a PDF download of one delivered reply (audited)
  GET  /v1/admin/report-notice        → admin: the safety notice printed on downloaded reports
  GET  /admin                         → web admin page (static; signs in with Supabase email code)

DEV_MODE=1 (local only): accepts a `Bearer dev-L1|dev-L2|dev-L3` token as a
verified clinician, skips the database, exposes POST /dev/clean, and — if no
ANTHROPIC_API_KEY is set — uses a fake model that returns a canned reply. This
is what harness/server.js talks to. DEV_MODE must be OFF in production.

⚠ Scaffold: the HTTP + DB layers are written to spec but not executed in the
build environment. The pure-Python core (cleaner, inspector, prompt, pipeline)
is unit-tested (tests/).
"""
from __future__ import annotations

import json
import pathlib
import re
import uuid
from datetime import date
from types import SimpleNamespace

from fastapi import Depends, FastAPI, Header, HTTPException, Query
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel, ConfigDict, Field, StringConstraints
from typing import Annotated

from . import db, deid
from .consultation import ConsultationEngine, ConsultationError, public_view
from .dev_admin import DevAdminStore, DevConsultationStore, DevHistoryStore
from .icd import ICD11Client, OfflineICD11
from .inspector import ICD_CODE_RE
from .pipeline import DeidRejected, ModelResult, Pipeline
from .prompt import load_consult_prompts, load_skill
from .report_notice import report_notice
from .secrets import load_config

CFG = load_config()
SKILL = load_skill(CFG.skill_dir)
ICD = (ICD11Client(CFG.who_icd_client_id, CFG.who_icd_client_secret, CFG.icd_release)
       if CFG.icd_enabled else OfflineICD11())


class _FakeDevModel:
    """Keyless local model: returns a canned, inspector-valid Mode A reply so the
    plumbing can be tested end to end without an Anthropic key."""
    model = "dev-fake"

    def __init__(self, skill_dir: str):
        p = pathlib.Path("fixtures/golden/mode_a_panic.md")
        self._canned = p.read_text() if p.exists() else "<!--yc mode=Q gate=none ceiling=NA level=L2-->\nDev fake model: no canned reply found."
        r = pathlib.Path("fixtures/golden/consult_report_ocd.md")
        # No WHO lookups offline: every code is marked "to confirm", as the real model must do.
        self._report = ICD_CODE_RE.sub(lambda m: m.group(0) + " (code to confirm at icd.who.int)", r.read_text()) \
            if r.exists() else self._canned

    def run(self, system, messages, tools, tool_handler) -> ModelResult:
        text = self._canned
        if isinstance(system, list):  # guided consultation report (Mode R): canned gold-standard report
            level = re.search(r"Clinician level: (L[123])", messages[-1]["content"])
            text = self._report.replace("level=L2", f"level={level.group(1) if level else 'L2'}", 1)
        return ModelResult(text=text, model=self.model, usage={"input_tokens": 0, "output_tokens": 0})

    def run_structured(self, system, user, schema):
        """Keyless intake: records the reply under the field just asked, then says "ready" — so the
        app asks the intake guide's mandatory questions one by one and then offers the report.
        A one- or two-word answer gets one clarifying question, to show that step offline."""
        asked = re.search(r"\[Question just answered\] \(([a-z_]+)\)", user)
        message = user.split("[Clinician's message]\n", 1)[-1].split("\n\n[App note]")[0].strip()[:200]
        try:
            state = json.loads(user.split("\n")[1])
        except (IndexError, ValueError):
            state = {}
        field = asked.group(1) if asked else "presenting_concern"
        facts = [{"field": field, "value": message}]
        known = set(state.get("facts", {})) | set(state.get("unknown", [])) | {field}
        needed = [f for f in ("presenting_concern", "age_gender", "risk_screening", "duration_onset") if f not in known]
        out = {"status": "ready", "case_type": "Sample case (dev mode)", "info_needed": needed, "facts_patch": facts,
               "unknown_fields": [], "case_summary": "", "question": "", "why": "", "field": "", "options": [],
               "brief_answer": ""}
        if asked and len(message.split()) <= 2 and field not in state.get("clarified", []):
            out.update(status="clarify", question=f"Could you say a little more about that ({field.replace('_', ' ')})?",
                       field=field, why="The answer was short; a little more detail makes the report specific.")
        return out, {"input_tokens": 0, "output_tokens": 0}


if CFG.dev_mode and not CFG.anthropic_api_key:
    MODEL = _FakeDevModel(CFG.skill_dir)
else:
    from .claude_client import AnthropicClient
    MODEL = AnthropicClient(CFG.anthropic_api_key, CFG.claude_model)

PIPELINE = Pipeline(SKILL, MODEL, ICD)
CONSULT = ConsultationEngine(load_consult_prompts(CFG.skill_dir), MODEL, PIPELINE)

if not CFG.dev_mode:
    import jwt  # PyJWT
    JWKS = jwt.PyJWKClient(CFG.supabase_jwks_url)

app = FastAPI(title="YourCounselor backend", version=SKILL.version)

if CFG.dev_mode:
    # Local only: lets the Flutter app run in a browser (`flutter run -d chrome`)
    # against this dev server. Phones don't need CORS; production never enables it.
    from fastapi.middleware.cors import CORSMiddleware
    app.add_middleware(
        CORSMiddleware,
        allow_origin_regex=r"^http://(localhost|127\.0\.0\.1)(:\d+)?$",
        allow_methods=["GET", "POST", "PATCH"],
        allow_headers=["Authorization", "Content-Type"],
    )

# In-memory clinician for DEV_MODE so no database is needed locally.
_DEV_CLINICIAN = {"id": "dev-clinician", "level": "L2", "verification_status": "verified",
                  "consent_version": "beta-draft-1", "is_admin": True}
_dev_admin = DevAdminStore()  # sample registrations and reports for the admin panel in DEV_MODE
_dev_history = DevHistoryStore()  # consult history in DEV_MODE (no database)
_dev_consults = DevConsultationStore()  # guided consultations in DEV_MODE (no database)


# --- auth -------------------------------------------------------------------
def current_user(authorization: str = Header(...)) -> dict:
    token = authorization.removeprefix("Bearer ").strip()
    if CFG.dev_mode and token.startswith("dev-"):
        return {"id": "dev-clinician", "dev_level": token.split("-", 1)[1] if "-" in token else "L2"}
    import jwt
    try:
        key = JWKS.get_signing_key_from_jwt(token).key
        claims = jwt.decode(token, key, algorithms=["RS256", "ES256"], audience="authenticated")
    except Exception:
        raise HTTPException(401, "invalid token")
    return {"id": claims["sub"]}


def verified_clinician(user: dict = Depends(current_user)) -> dict:
    if CFG.dev_mode and user["id"] == "dev-clinician":
        return {**_DEV_CLINICIAN, "level": user.get("dev_level", "L2") if user.get("dev_level") in ("L1", "L2", "L3") else "L2"}
    c = db.get_clinician(user["id"])
    if not c or c["verification_status"] != "verified" or c["level"] not in ("L1", "L2", "L3"):
        raise HTTPException(403, "registration not yet verified")
    if not c["consent_version"]:
        raise HTTPException(403, "consent not recorded")
    return c


def admin(user: dict = Depends(current_user)) -> dict:
    if CFG.dev_mode and user["id"] == "dev-clinician":
        return _DEV_CLINICIAN
    c = db.get_clinician(user["id"])
    if not c or not c.get("is_admin"):
        raise HTTPException(403, "admin only")
    return c


# --- schemas ----------------------------------------------------------------
class ProfileIn(BaseModel):
    # The clinician's own details (never a client's); admin-only, never sent to the AI.
    full_name: Annotated[str, StringConstraints(strip_whitespace=True, min_length=2, max_length=100)]
    gender: str = Field(pattern="^(female|male|other|prefer_not_to_say)$")
    age: int = Field(ge=18, le=100)
    role: str = Field(pattern="^(counsellor_trainee|psychologist|psychiatrist)$")
    registration_body: str = Field(pattern="^(RCI|NMC|SMC|none)$")
    registration_number: str | None = Field(default=None, max_length=40)
    consent_version: str = Field(max_length=20)


class ProfileEditIn(BaseModel):
    """The clinician edits their own details. No level or status here: those come only from an admin."""
    model_config = ConfigDict(extra="forbid")
    full_name: Annotated[str, StringConstraints(strip_whitespace=True, min_length=2, max_length=100)]
    gender: str = Field(pattern="^(female|male|other|prefer_not_to_say)$")
    age: int = Field(ge=18, le=100)
    role: str = Field(pattern="^(counsellor_trainee|psychologist|psychiatrist)$")
    registration_body: str = Field(pattern="^(RCI|NMC|SMC|none)$")
    registration_number: str | None = Field(default=None, max_length=40)


# A change to these means the registration must be checked again (and the level set again).
_PROFESSIONAL = ("role", "registration_body", "registration_number")


class ConsultIn(BaseModel):
    text: str = Field(min_length=3, max_length=12000)
    mode: str = Field(default="auto", pattern="^(auto|A|B|C|D|E|F|G)$")
    conversation_id: uuid.UUID | None = None
    deid_attested: bool
    client_redaction_counts: dict[str, int] = {}
    level: str | None = Field(default=None, pattern="^(L1|L2|L3)$")   # honoured only in DEV_MODE


class IncidentIn(BaseModel):
    turn_id: uuid.UUID
    category: str = Field(pattern="^(unsafe|wrong_clinical|missing_safety|identifier_leak|crisis_number|other)$")
    note: str = Field(default="", max_length=2000)


class VerifyIn(BaseModel):
    level: str | None = Field(default=None, pattern="^(L1|L2|L3)$")   # required when verifying
    verification_status: str = Field(pattern="^(verified|rejected)$")
    evidence_note: str = Field(min_length=3, max_length=500)          # how the register was checked


class IncidentUpdateIn(BaseModel):
    status: str = Field(pattern="^(open|triaged|fixed|wont_fix)$")
    reviewer_note: str = Field(default="", max_length=2000)


class LabelIn(BaseModel):
    title: str | None = Field(default=None, max_length=60)


class ConsultationStartIn(BaseModel):
    text: str = Field(min_length=3, max_length=12000)
    deid_attested: bool
    client_redaction_counts: dict[str, int] = {}


class ConsultationReplyIn(BaseModel):
    action: str = Field(pattern="^(answer|dont_know|skip|finish|safety_managed|safety_absent)$")
    text: str = Field(default="", max_length=4000)
    deid_attested: bool = False
    client_msg_id: str | None = Field(default=None, max_length=64)   # a repeat of the same id is not re-run


class FactsIn(BaseModel):
    facts: dict[str, str | None] = Field(max_length=30)


class ReportIn(BaseModel):
    force: bool = False            # "Generate report now" before the intake has finished


class CleanIn(BaseModel):
    text: str = Field(max_length=12000)


# --- routes -----------------------------------------------------------------
@app.get("/healthz")
@app.get("/health")
def healthz():
    return {"ok": True, "skill_version": SKILL.version, "prompt_hash": SKILL.prompt_hash,
            "model": MODEL.model, **CFG.public()}


@app.get("/v1/me")
def me(user: dict = Depends(current_user)):
    features = {"consultation": CFG.consultation_enabled}
    if CFG.dev_mode and user["id"] == "dev-clinician":
        return {**_DEV_CLINICIAN, "features": features}
    row = db.get_clinician(user["id"])
    return {**row, "features": features} if row else {"id": user["id"], "verification_status": "none"}


@app.post("/v1/profile")
def profile(body: ProfileIn, user: dict = Depends(current_user)):
    db.upsert_clinician_profile(user["id"], body.model_dump())
    return {"verification_status": "pending"}


@app.patch("/v1/profile")
def edit_profile(body: ProfileEditIn, user: dict = Depends(current_user)):
    """Name, gender and age change directly. A changed role or registration sends the account back
    to "pending" with no level until an admin checks the register again."""
    p = body.model_dump()
    p["registration_number"] = (p["registration_number"] or "").strip() or None
    if CFG.dev_mode and user["id"] == "dev-clinician":
        row = _DEV_CLINICIAN
        reverify = any((row.get(k) or None) != p[k] for k in _PROFESSIONAL)
        row.update(full_name=p["full_name"], gender=p["gender"], age_at_registration=p["age"],
                   **{k: p[k] for k in _PROFESSIONAL})
        if reverify:
            row.update(verification_status="pending", level=None)
        return {"verification_status": row["verification_status"], "reverify": reverify}
    result = db.update_clinician_profile(user["id"], p)
    if result is None:
        raise HTTPException(404, "register first")
    return result


@app.post("/v1/consult")
def consult(body: ConsultIn, c: dict = Depends(verified_clinician)):
    if not body.deid_attested:
        raise HTTPException(422, "de-identification attestation required")
    level = c["level"]
    if CFG.dev_mode and body.level:
        level = body.level

    if CFG.dev_mode:
        conv_id, history = body.conversation_id or uuid.uuid4(), []
    else:
        if db.turns_today(c["id"]) >= CFG.daily_turn_limit:
            raise HTTPException(429, "daily limit reached")
        conv_id = body.conversation_id or db.new_conversation(c["id"])
        try:
            history = db.history(conv_id, c["id"])
        except PermissionError:
            raise HTTPException(404, "conversation not found")

    try:
        r = PIPELINE.run(body.text, level=level, requested_mode=body.mode, history=history,
                         today=date.today().isoformat())
    except DeidRejected as e:
        if not CFG.dev_mode:
            db.log_deid_rejection(c["id"], e.counts)
        raise HTTPException(422, {"error": "identifiers_detected", "types": sorted(e.counts)})

    if CFG.dev_mode:
        turn_id = uuid.uuid4()
        _dev_history.record(c["id"], str(conv_id), body.mode, level, body.text, r.display_text, r.status,
                            skill_version=r.skill_version)
    else:
        turn_id = db.log_turn(conv_id, c["id"], level, body, r)
        if r.status == "blocked":
            db.auto_incident(turn_id, r.reports[-1])

    return {"turn_id": str(turn_id), "conversation_id": str(conv_id), "status": r.status,
            "text": r.display_text, "skill_version": r.skill_version, "report": r.reports[-1]}


@app.post("/v1/incidents")
def incident(body: IncidentIn, c: dict = Depends(verified_clinician)):
    if CFG.dev_mode:
        return {"ok": True, "dev": True}
    try:
        db.create_incident(body.turn_id, c["id"], body.category, body.note)
    except PermissionError:
        raise HTTPException(404, "turn not found")
    return {"ok": True}


# --- consult history (clinician's own; read-only) ---------------------------------
def _check_label(title: str | None) -> str | None:
    """Labels go through the same cleaner as case text; any identifier or possible name is refused."""
    title = (title or "").strip()
    if not title:
        return None
    r = deid.clean(title)
    if r.redactions or r.warnings:
        types = sorted(set(r.counts) | ({"POSSIBLE_NAME"} if r.warnings else set()))
        raise HTTPException(422, {"error": "identifiers_detected", "types": types})
    return title


@app.get("/v1/history")
def history_list(q: str | None = Query(None, max_length=100), mode: str | None = Query(None, pattern="^[A-GR]$"),
                 c: dict = Depends(verified_clinician)):
    q = (q or "").strip() or None
    rows = _dev_history.list(c["id"], q, mode) if CFG.dev_mode else db.list_history(c["id"], q, mode)
    return {"consults": [{k: v for k, v in r.items() if k != "hidden_at"} for r in rows]}


@app.get("/v1/history/{conv_id}")
def history_get(conv_id: uuid.UUID, c: dict = Depends(verified_clinician)):
    conv = _dev_history.get(str(conv_id), c["id"]) if CFG.dev_mode else db.get_conversation(conv_id, c["id"])
    if not conv:
        raise HTTPException(404, "consult not found")
    return {k: v for k, v in conv.items() if k not in ("clinician_id", "hidden_at")}


@app.patch("/v1/history/{conv_id}")
def history_label(conv_id: uuid.UUID, body: LabelIn, c: dict = Depends(verified_clinician)):
    title = _check_label(body.title)
    ok = (_dev_history.rename(str(conv_id), c["id"], title) if CFG.dev_mode
          else db.rename_conversation(conv_id, c["id"], title))
    if not ok:
        raise HTTPException(404, "consult not found")
    return {"ok": True, "title": title}


@app.delete("/v1/history/{conv_id}")
def history_hide(conv_id: uuid.UUID, c: dict = Depends(verified_clinician)):
    ok = _dev_history.hide(str(conv_id), c["id"]) if CFG.dev_mode else db.hide_conversation(conv_id, c["id"])
    if not ok:
        raise HTTPException(404, "consult not found")
    return {"ok": True}


# --- guided consultation ------------------------------------------------------------
# The phone sends one step at a time; the server keeps the compact state (app/consultation.py).
# Every text is re-cleaned, every intake response is inspected, and the report goes through the
# same pipeline and inspector as any consult. The level always comes from the clinicians row.
def _consultations_on() -> None:
    if not CFG.consultation_enabled:
        raise HTTPException(404, "guided consultation is not enabled")


def _identifiers(c: dict, e: DeidRejected):
    if not CFG.dev_mode:
        db.log_deid_rejection(c["id"], e.counts)
    return HTTPException(422, {"error": "identifiers_detected", "types": sorted(e.counts)})


def _claim(conv_id: str, c: dict) -> dict:
    row = _dev_consults.claim(conv_id, c["id"]) if CFG.dev_mode else db.claim_consultation(conv_id, c["id"])
    if row is None:
        raise HTTPException(404, "consultation not found")
    if row == "busy":
        raise HTTPException(409, {"error": "busy", "detail": "the previous step is still being processed"})
    return row


def _save(conv_id: str, state: dict) -> None:
    (_dev_consults.save if CFG.dev_mode else db.save_consultation)(conv_id, state["stage"], state)


def _release(conv_id: str) -> None:
    (_dev_consults.release if CFG.dev_mode else db.release_consultation)(conv_id)


def _report_reply(conv_id: str, c: dict, state: dict) -> dict | None:
    """The stored report of a finished consultation, shaped like a /v1/consult reply."""
    rep = state.get("report")
    if not rep:
        return None
    conv = _dev_history.get(conv_id, c["id"]) if CFG.dev_mode else db.get_conversation(conv_id, c["id"])
    turn = next((t for t in (conv or {}).get("turns", []) if str(t["id"]) == rep["turn_id"]), None)
    if not turn:
        return None
    return {"turn_id": rep["turn_id"], "conversation_id": conv_id, "status": turn["status"],
            "text": turn["output_shown"], "skill_version": rep.get("skill_version", SKILL.version)}


@app.post("/v1/consultations")
def consultation_start(body: ConsultationStartIn, c: dict = Depends(verified_clinician)):
    _consultations_on()
    if not body.deid_attested:
        raise HTTPException(422, "de-identification attestation required")
    if not CFG.dev_mode and db.turns_today(c["id"]) + db.consultations_today(c["id"]) >= CFG.daily_turn_limit:
        raise HTTPException(429, "daily limit reached")
    try:
        state = CONSULT.start(body.text)
    except DeidRejected as e:
        raise _identifiers(c, e)
    conv_id = str(_dev_consults.new(c["id"], state["stage"], state) if CFG.dev_mode
                  else db.new_consultation(c["id"], state["stage"], state))
    return public_view(state, conv_id)


@app.get("/v1/consultations")
def consultation_list(c: dict = Depends(verified_clinician)):
    _consultations_on()
    rows = _dev_consults.list_open(c["id"]) if CFG.dev_mode else db.list_open_consultations(c["id"])
    return {"consultations": [{**r, "id": str(r["id"])} for r in rows]}


@app.get("/v1/consultations/{conv_id}")
def consultation_get(conv_id: uuid.UUID, c: dict = Depends(verified_clinician)):
    _consultations_on()
    row = _dev_consults.get(str(conv_id), c["id"]) if CFG.dev_mode else db.get_consultation(conv_id, c["id"])
    if not row:
        raise HTTPException(404, "consultation not found")
    return {**public_view(row["state"], str(conv_id)), "reply": _report_reply(str(conv_id), c, row["state"])}


@app.post("/v1/consultations/{conv_id}/reply")
def consultation_reply(conv_id: uuid.UUID, body: ConsultationReplyIn, c: dict = Depends(verified_clinician)):
    _consultations_on()
    if body.action == "answer" and not body.deid_attested:
        raise HTTPException(422, "de-identification attestation required")
    cid = str(conv_id)
    state = _claim(cid, c)["state"]
    if body.client_msg_id and state.get("last_msg_id") == body.client_msg_id:
        _release(cid)                       # a repeated tap or retry: already done, no second model call
        return public_view(state, cid)
    try:
        CONSULT.reply(state, body.action, body.text)
    except DeidRejected as e:
        _release(cid)
        raise _identifiers(c, e)
    except ConsultationError as e:
        _release(cid)
        raise HTTPException(e.status, e.detail)
    except Exception:
        _release(cid)
        raise
    state["last_msg_id"] = body.client_msg_id
    _save(cid, state)
    return public_view(state, cid)


@app.patch("/v1/consultations/{conv_id}/facts")
def consultation_facts(conv_id: uuid.UUID, body: FactsIn, c: dict = Depends(verified_clinician)):
    _consultations_on()
    cid = str(conv_id)
    state = _claim(cid, c)["state"]
    try:
        CONSULT.edit_facts(state, body.facts)
    except DeidRejected as e:
        _release(cid)
        raise _identifiers(c, e)
    except ConsultationError as e:
        _release(cid)
        raise HTTPException(e.status, e.detail)
    _save(cid, state)
    return public_view(state, cid)


@app.post("/v1/consultations/{conv_id}/report")
def consultation_report(conv_id: uuid.UUID, body: ReportIn, c: dict = Depends(verified_clinician)):
    _consultations_on()
    cid = str(conv_id)
    state = _claim(cid, c)["state"]
    if state["stage"] == "COMPLETED":       # already written: return it, never pay for it twice
        _release(cid)
        return {"consultation": public_view(state, cid), "reply": _report_reply(cid, c, state)}
    level = c["level"]
    try:
        r = CONSULT.report(state, level, force=body.force, today=date.today().isoformat())
    except DeidRejected as e:
        _release(cid)
        raise _identifiers(c, e)
    except ConsultationError as e:
        _release(cid)
        raise HTTPException(e.status, e.detail)
    except Exception:
        _release(cid)
        raise
    case = SimpleNamespace(mode="R", text=CONSULT.case_text(state), client_redaction_counts={})
    if CFG.dev_mode:
        turn_id = str(uuid.uuid4())
        _dev_history.record(c["id"], cid, "R", level, case.text, r.display_text, r.status, turn_id=turn_id,
                            skill_version=r.skill_version)
    else:
        turn_id = str(db.log_turn(cid, c["id"], level, case, r))
        if r.status == "blocked":
            db.auto_incident(turn_id, r.reports[-1])
    state["report"] = {"turn_id": turn_id, "status": r.status, "skill_version": r.skill_version}
    _save(cid, state)
    reply = {"turn_id": turn_id, "conversation_id": cid, "status": r.status, "text": r.display_text,
             "skill_version": r.skill_version, "report": r.reports[-1]}
    return {"consultation": public_view(state, cid), "reply": reply}


# --- admin panel (app Admin area and /admin web page) -------------------------
# Admin-only. Lists hold clinicians' registration details and de-identified case
# text only; every change is written to admin_audit.
@app.get("/v1/admin/clinicians")
def admin_clinicians(status: str = Query("pending", pattern="^(pending|verified|rejected)$"),
                     a: dict = Depends(admin)):
    rows = _dev_admin.clinicians(status) if CFG.dev_mode else db.list_clinicians(status)
    return {"clinicians": rows}


@app.patch("/v1/admin/clinicians/{clinician_id}")
def verify(clinician_id: uuid.UUID, body: VerifyIn, a: dict = Depends(admin)):
    if body.verification_status == "verified" and not body.level:
        raise HTTPException(422, "level required to verify")
    if str(clinician_id) == str(a["id"]):
        raise HTTPException(409, "admins cannot change their own verification")
    if CFG.dev_mode:
        found = _dev_admin.verify(clinician_id, body)
    else:
        found = db.set_verification(clinician_id, body.level, body.verification_status, body.evidence_note, a["id"])
    if not found:
        raise HTTPException(404, "clinician not found")
    return {"ok": True}


@app.get("/v1/admin/clinicians/{clinician_id}/consults")
def admin_clinician_consults(clinician_id: uuid.UUID, q: str | None = Query(None, max_length=100),
                             a: dict = Depends(admin)):
    q = (q or "").strip() or None
    if CFG.dev_mode:
        rows = _dev_history.list(str(clinician_id), q, None, include_hidden=True)
    else:
        rows = db.list_history(clinician_id, q, None, limit=200, include_hidden=True)
        db.audit(a["id"], "view_consult_list", clinician_id, {"q": bool(q)})
    return {"consults": rows}


@app.get("/v1/admin/consults/{conv_id}")
def admin_consult(conv_id: uuid.UUID, a: dict = Depends(admin)):
    conv = _dev_history.get(str(conv_id)) if CFG.dev_mode else db.get_conversation(conv_id)
    if not conv:
        raise HTTPException(404, "consult not found")
    if not CFG.dev_mode:
        db.audit(a["id"], "view_consult", conv_id, {"clinician_id": str(conv["clinician_id"])})
    return conv


class PdfDownloadIn(BaseModel):
    turn_id: uuid.UUID


@app.get("/v1/admin/report-notice")
def admin_report_notice(a: dict = Depends(admin)):
    """What the web admin prints around a report it saves as PDF (same wording as the app's PDF)."""
    return report_notice()


@app.post("/v1/admin/consults/{conv_id}/pdf")
def admin_consult_pdf(conv_id: uuid.UUID, body: PdfDownloadIn, a: dict = Depends(admin)):
    """Records an admin's PDF download of one delivered reply before the device builds it.
    The PDF itself is made on the admin's device; no report text is sent back here."""
    conv = _dev_history.get(str(conv_id)) if CFG.dev_mode else db.get_conversation(conv_id)
    turn = next((t for t in (conv or {}).get("turns", []) if str(t["id"]) == str(body.turn_id)), None)
    if not turn:
        raise HTTPException(404, "report not found")
    if turn["status"] != "delivered":
        raise HTTPException(409, "a held-back reply cannot be downloaded")
    if not CFG.dev_mode:
        db.audit(a["id"], "download_pdf", conv_id, {"turn_id": str(body.turn_id)})
    return {"ok": True}


@app.get("/v1/admin/incidents")
def admin_incidents(status: str | None = Query(None, pattern="^(open|triaged|fixed|wont_fix)$"),
                    a: dict = Depends(admin)):
    rows = _dev_admin.incidents(status) if CFG.dev_mode else db.list_incidents(status)
    return {"incidents": rows}


@app.get("/v1/admin/incidents/{incident_id}")
def admin_incident(incident_id: uuid.UUID, a: dict = Depends(admin)):
    row = _dev_admin.incident(incident_id) if CFG.dev_mode else db.get_incident(incident_id)
    if not row:
        raise HTTPException(404, "incident not found")
    return row


# The replies the safety check held back, as the AI wrote them — for working out why a reply was blocked.
# Only the /admin web page calls this, on the admin's click; the phone app never does (nothing reaches the
# phone without passing inspect()). Each view is written to the audit log.
@app.get("/v1/admin/incidents/{incident_id}/held-back")
def admin_incident_held_back(incident_id: uuid.UUID, a: dict = Depends(admin)):
    attempts = _dev_admin.held_back(incident_id) if CFG.dev_mode else db.held_back(incident_id)
    if attempts is None:
        raise HTTPException(404, "incident not found")
    if not CFG.dev_mode:
        db.audit(a["id"], "view_held_back", incident_id, {"attempts": len(attempts)})
    return {"attempts": attempts}


@app.patch("/v1/admin/incidents/{incident_id}")
def admin_update_incident(incident_id: uuid.UUID, body: IncidentUpdateIn, a: dict = Depends(admin)):
    if CFG.dev_mode:
        found = _dev_admin.update_incident(incident_id, body)
    else:
        found = db.update_incident(incident_id, body.status, body.reviewer_note, a["id"])
    if not found:
        raise HTTPException(404, "incident not found")
    return {"ok": True}


# The web admin page: static files from app/admin_web, served from this origin so
# no CORS is needed. No third-party scripts; strict CSP; never cached.
_ADMIN_DIR = pathlib.Path(__file__).parent / "admin_web"
_ADMIN_FILES = {"": ("index.html", "text/html"), "admin.js": ("admin.js", "text/javascript"),
                "admin.css": ("admin.css", "text/css"), "logo.png": ("logo.png", "image/png"),
                # The app's brand fonts (SIL OFL, see fonts/OFL.txt), served from here: no third-party requests.
                "nunito-extrabold.ttf": ("fonts/Nunito-ExtraBold.ttf", "font/ttf"),
                "nunitosans-regular.ttf": ("fonts/NunitoSans-Regular.ttf", "font/ttf"),
                "nunitosans-bold.ttf": ("fonts/NunitoSans-Bold.ttf", "font/ttf")}


def _supabase_url() -> str:
    # https://<project>.supabase.co/auth/v1/.well-known/jwks.json -> https://<project>.supabase.co
    return CFG.supabase_jwks_url.split("/auth/v1/", 1)[0] if "/auth/v1/" in CFG.supabase_jwks_url else ""


def _admin_headers() -> dict:
    connect = " ".join(x for x in ("'self'", _supabase_url()) if x)
    return {
        "Content-Security-Policy": (f"default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; "
                                    f"font-src 'self'; "
                                    f"connect-src {connect}; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"),
        "Cache-Control": "no-store",
        "Referrer-Policy": "no-referrer",
        "X-Content-Type-Options": "nosniff",
    }


@app.get("/admin/config.json")
def admin_config():
    return JSONResponse({"supabase_url": _supabase_url(), "supabase_publishable_key": CFG.supabase_publishable_key,
                         "dev_mode": CFG.dev_mode}, headers=_admin_headers())


@app.get("/admin")
@app.get("/admin/")
@app.get("/admin/{name}")
def admin_page(name: str = ""):
    if name not in _ADMIN_FILES:
        raise HTTPException(404, "not found")
    file, media = _ADMIN_FILES[name]
    headers = _admin_headers()
    if media.startswith(("font/", "image/")):
        headers["Cache-Control"] = "public, max-age=86400"   # logo and fonts only; pages and data stay no-store
    return Response((_ADMIN_DIR / file).read_bytes(), media_type=media, headers=headers)


# --- dev-only helper --------------------------------------------------------
@app.post("/dev/clean")
def dev_clean(body: CleanIn):
    """Preview what the cleaner would redact. DEV_MODE only."""
    if not CFG.dev_mode:
        raise HTTPException(404, "not found")
    r = deid.clean(body.text)
    return {"redactions": [{"type": x.type, "start": x.start, "end": x.end} for x in r.redactions],
            "warnings": r.warnings, "cleaned": r.text, "is_clean": r.is_clean}
