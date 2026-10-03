"""
Thin data layer (psycopg 3, DATABASE_URL = Supabase Postgres, Mumbai region).
Scaffold — not executed in the build environment; cover with integration tests
against a local Postgres on Day 4.
"""
from __future__ import annotations

import json
import os
import uuid

import psycopg
from psycopg.rows import dict_row

_DSN = os.environ.get("DATABASE_URL", "")


def _conn():
    return psycopg.connect(_DSN, row_factory=dict_row, autocommit=True)


def get_clinician(cid) -> dict | None:
    with _conn() as c:
        return c.execute("select * from clinicians where id=%s", (str(cid),)).fetchone()


def upsert_clinician_profile(cid, p: dict) -> None:
    with _conn() as c:
        c.execute(
            """insert into clinicians (id, role, registration_body, registration_number, consent_version, consent_at)
               values (%s,%s,%s,%s,%s, now())
               on conflict (id) do update set role=excluded.role, registration_body=excluded.registration_body,
                 registration_number=excluded.registration_number, consent_version=excluded.consent_version,
                 consent_at=now(), verification_status='pending', level=null""",
            (str(cid), p["role"], p["registration_body"], p.get("registration_number"), p["consent_version"]))


def set_verification(cid, level, status, note, admin_id) -> bool:
    with _conn() as c:
        row = c.execute("""update clinicians set level=%s, verification_status=%s, verification_note=%s,
                     verified_by=%s, verified_at=now() where id=%s returning id""",
                        (level if status == "verified" else None, status, note, str(admin_id), str(cid))).fetchone()
        if not row:
            return False
        c.execute("insert into admin_audit (actor_id, action, target_id, detail) values (%s,'verify',%s,%s)",
                  (str(admin_id), str(cid), json.dumps({"level": level, "status": status, "note": note})))
        return True


def new_conversation(cid) -> uuid.UUID:
    with _conn() as c:
        return c.execute("insert into conversations (clinician_id) values (%s) returning id", (str(cid),)).fetchone()["id"]


def history(conv_id, cid, max_turns: int = 6) -> list[dict]:
    """Prior turns as Messages-API history (owner-checked). Blocked turns are skipped."""
    with _conn() as c:
        owner = c.execute("select clinician_id from conversations where id=%s", (str(conv_id),)).fetchone()
        if not owner or str(owner["clinician_id"]) != str(cid):
            raise PermissionError("conversation not owned by clinician")
        rows = c.execute("""select input_deid, output_raw from turns where conversation_id=%s and status='delivered'
                            order by created_at desc limit %s""", (str(conv_id), max_turns)).fetchall()
    msgs: list[dict] = []
    for r in reversed(rows):
        msgs += [{"role": "user", "content": r["input_deid"]}, {"role": "assistant", "content": r["output_raw"]}]
    return msgs


def turns_today(cid) -> int:
    with _conn() as c:
        return c.execute("select count(*) n from turns where clinician_id=%s and created_at > now() - interval '1 day'",
                         (str(cid),)).fetchone()["n"]


def log_turn(conv_id, cid, level, body, r) -> uuid.UUID:
    with _conn() as c:
        return c.execute(
            """insert into turns (conversation_id, clinician_id, requested_mode, level, input_deid, client_redaction_counts,
                 output_raw, output_shown, status, attempts, inspector_reports, model, skill_version, prompt_hash,
                 tool_calls, verified_icd_codes, usage, latency_ms)
               values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) returning id""",
            (str(conv_id), str(cid), body.mode, level, body.text,
             json.dumps(body.client_redaction_counts), r.raw_text, r.display_text, r.status, r.attempts,
             json.dumps(r.reports), r.model, r.skill_version, r.prompt_hash, json.dumps(r.tool_calls),
             r.verified_icd_codes, json.dumps(r.usage), r.latency_ms)).fetchone()["id"]


def auto_incident(turn_id, report: dict) -> None:
    with _conn() as c:
        c.execute("insert into incidents (turn_id, source, category, note) values (%s,'inspector','blocked',%s)",
                  (str(turn_id), json.dumps(report["blocks"])))


def create_incident(turn_id, cid, category, note) -> None:
    with _conn() as c:
        owner = c.execute("select clinician_id from turns where id=%s", (str(turn_id),)).fetchone()
        if not owner or str(owner["clinician_id"]) != str(cid):
            raise PermissionError("turn not owned by clinician")
        c.execute("insert into incidents (turn_id, reported_by, source, category, note) values (%s,%s,'clinician',%s,%s)",
                  (str(turn_id), str(cid), category, note))


def log_deid_rejection(cid, counts: dict) -> None:
    with _conn() as c:
        c.execute("insert into deid_rejections (clinician_id, types) values (%s,%s)", (str(cid), json.dumps(counts)))


# --- admin (reads and updates for the admin panel; every write is audited) ---------------
_CLINICIAN_COLS = """c.id, u.email, c.role, c.registration_body, c.registration_number, c.level,
                     c.verification_status, c.verification_note, c.verified_at, c.is_admin, c.created_at"""


def list_clinicians(status: str, limit: int = 200) -> list[dict]:
    with _conn() as c:
        return c.execute(
            f"""select {_CLINICIAN_COLS} from clinicians c join auth.users u on u.id = c.id
                where c.verification_status = %s order by c.created_at limit %s""",
            (status, limit)).fetchall()


_INCIDENT_COLS = """i.id, i.turn_id, i.source, i.category, i.note, i.status, i.reviewer_note, i.created_at,
                    t.level, t.status as turn_status, t.requested_mode, t.skill_version"""


def list_incidents(status: str | None, limit: int = 200) -> list[dict]:
    with _conn() as c:
        where, args = ("where i.status = %s", (status, limit)) if status else ("", (limit,))
        return c.execute(
            f"""select {_INCIDENT_COLS} from incidents i join turns t on t.id = i.turn_id
                {where} order by i.created_at desc limit %s""", args).fetchall()


def get_incident(incident_id) -> dict | None:
    """One incident with its turn: the de-identified input, the reply as shown, and the inspector reports."""
    with _conn() as c:
        return c.execute(
            f"""select {_INCIDENT_COLS}, t.input_deid, t.output_shown, t.inspector_reports, t.attempts
                from incidents i join turns t on t.id = i.turn_id where i.id = %s""",
            (str(incident_id),)).fetchone()


def update_incident(incident_id, status: str, reviewer_note: str, admin_id) -> bool:
    with _conn() as c:
        row = c.execute("update incidents set status=%s, reviewer_note=%s where id=%s returning id",
                        (status, reviewer_note, str(incident_id))).fetchone()
        if not row:
            return False
        c.execute("insert into admin_audit (actor_id, action, target_id, detail) values (%s,'incident',%s,%s)",
                  (str(admin_id), str(incident_id), json.dumps({"status": status, "note": reviewer_note})))
        return True
