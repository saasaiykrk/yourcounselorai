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


def set_verification(cid, level, status, note, admin_id) -> None:
    with _conn() as c:
        c.execute("""update clinicians set level=%s, verification_status=%s, verification_note=%s,
                     verified_by=%s, verified_at=now() where id=%s""",
                  (level if status == "verified" else None, status, note, str(admin_id), str(cid)))
        c.execute("insert into admin_audit (actor_id, action, target_id, detail) values (%s,'verify',%s,%s)",
                  (str(admin_id), str(cid), json.dumps({"level": level, "status": status, "note": note})))


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
