"""
In-memory sample data for the admin panel in DEV_MODE (no database).

Everything here is invented: example.test addresses, made-up registration
numbers, and short synthetic case text with no identifiers.
"""
from __future__ import annotations

import copy
import uuid
from datetime import datetime, timedelta, timezone


def _ago(hours: float) -> str:
    return (datetime.now(timezone.utc) - timedelta(hours=hours)).isoformat()


class DevAdminStore:
    def __init__(self) -> None:
        self._clinicians = [
            {"id": "11111111-1111-4111-8111-111111111111", "email": "trainee.one@example.test",
             "role": "counsellor_trainee", "registration_body": "none", "registration_number": None,
             "level": None, "verification_status": "pending", "verification_note": None, "verified_at": None,
             "is_admin": False, "created_at": _ago(5)},
            {"id": "22222222-2222-4222-8222-222222222222", "email": "psychologist.two@example.test",
             "role": "psychologist", "registration_body": "RCI", "registration_number": "A12345",
             "level": None, "verification_status": "pending", "verification_note": None, "verified_at": None,
             "is_admin": False, "created_at": _ago(26)},
        ]
        turn = {"level": "L2", "turn_status": "blocked", "requested_mode": "A", "skill_version": "2.1.1",
                "attempts": 2, "input_deid": "34F, low mood for 3 months, poor sleep. Full plan please.",
                "output_shown": "This reply was held back by the safety check.",
                "inspector_reports": [{"passed": False, "blocks": ["MISSING_DISCLAIMER"]}]}
        self._incidents = [
            {"id": "33333333-3333-4333-8333-333333333333", "turn_id": "44444444-4444-4444-8444-444444444444",
             "source": "inspector", "category": "blocked", "note": '["MISSING_DISCLAIMER"]', "status": "open",
             "reviewer_note": None, "created_at": _ago(2), **turn},
            {"id": "55555555-5555-4555-8555-555555555555", "turn_id": "66666666-6666-4666-8666-666666666666",
             "source": "clinician", "category": "wrong_clinical", "note": "Differential missed adjustment disorder.",
             "status": "open", "reviewer_note": None, "created_at": _ago(30),
             **{**turn, "turn_status": "delivered", "output_shown": "### 1. Case History & MSE Audit\n(sample reply)"}},
        ]

    _LIST_HIDDEN = ("input_deid", "output_shown", "inspector_reports", "attempts")

    def clinicians(self, status: str) -> list[dict]:
        return [copy.deepcopy(c) for c in self._clinicians if c["verification_status"] == status]

    def verify(self, cid: uuid.UUID, body) -> bool:
        for c in self._clinicians:
            if c["id"] == str(cid):
                c.update(verification_status=body.verification_status, verification_note=body.evidence_note,
                         level=body.level if body.verification_status == "verified" else None,
                         verified_at=_ago(0))
                return True
        return False

    def incidents(self, status: str | None) -> list[dict]:
        rows = [i for i in self._incidents if status is None or i["status"] == status]
        return [{k: v for k, v in i.items() if k not in self._LIST_HIDDEN} for i in copy.deepcopy(rows)]

    def incident(self, iid: uuid.UUID) -> dict | None:
        return next((copy.deepcopy(i) for i in self._incidents if i["id"] == str(iid)), None)

    def update_incident(self, iid: uuid.UUID, body) -> bool:
        for i in self._incidents:
            if i["id"] == str(iid):
                i.update(status=body.status, reviewer_note=body.reviewer_note)
                return True
        return False


class DevHistoryStore:
    """DEV_MODE consult history: real dev consults are recorded here, plus a
    couple of invented ones so the History screens have something to show."""

    def __init__(self) -> None:
        self._convs: dict[str, dict] = {}
        self._seed("dev-clinician", "aaaaaaaa-0000-4000-8000-000000000001", "Sleep and low mood",
                   [("A", "34F, low mood for 3 months, poor sleep, lost interest in work. Full plan please.", 30)])
        self._seed("dev-clinician", "aaaaaaaa-0000-4000-8000-000000000002", None,
                   [("B", "19M, panic attacks before exams, no medical history. Quick review.", 6),
                    ("B", "Follow-up: attacks now twice a week. What to add?", 5)])
        self._seed("22222222-2222-4222-8222-222222222222", "aaaaaaaa-0000-4000-8000-000000000003", None,
                   [("C", "40M, irritability and poor concentration for 2 months. Differentials?", 50)])

    def _seed(self, owner, cid, title, turns):
        self._convs[cid] = {"id": cid, "clinician_id": owner, "title": title, "hidden_at": None,
                            "created_at": _ago(turns[0][2]), "turns": []}
        for mode, text, hours in turns:
            self._convs[cid]["turns"].append({
                "id": str(uuid.uuid4()), "created_at": _ago(hours), "requested_mode": mode, "level": "L2",
                "input_deid": text, "status": "delivered",
                "output_shown": "### 1. Case History & MSE Audit\n(sample reply for local testing)"})

    def record(self, owner: str, conv_id: str, mode: str, level: str, text: str, shown: str, status: str,
               turn_id: str | None = None) -> None:
        conv = self._convs.setdefault(conv_id, {"id": conv_id, "clinician_id": owner, "title": None,
                                                "hidden_at": None, "created_at": _ago(0), "turns": []})
        conv["turns"].append({"id": turn_id or str(uuid.uuid4()), "created_at": _ago(0), "requested_mode": mode,
                              "level": level, "input_deid": text, "output_shown": shown, "status": status})

    def _summary(self, c: dict) -> dict:
        t = c["turns"]
        return {"id": c["id"], "title": c["title"], "created_at": c["created_at"], "hidden_at": c["hidden_at"],
                "last_at": t[-1]["created_at"], "turns": len(t), "preview": t[0]["input_deid"][:160],
                "modes": sorted({x["requested_mode"] for x in t}), "last_status": t[-1]["status"]}

    def list(self, owner: str, q: str | None, mode: str | None, include_hidden: bool = False) -> list[dict]:
        rows = []
        for c in self._convs.values():
            if c["clinician_id"] != owner or not c["turns"] or (c["hidden_at"] and not include_hidden):
                continue
            if q and q.lower() not in (c["title"] or "").lower() and not any(
                    q.lower() in t["input_deid"].lower() for t in c["turns"]):
                continue
            if mode and not any(t["requested_mode"] == mode for t in c["turns"]):
                continue
            rows.append(self._summary(c))
        return sorted(rows, key=lambda r: r["last_at"], reverse=True)

    def get(self, conv_id: str, owner: str | None = None) -> dict | None:
        c = self._convs.get(conv_id)
        if not c or (owner is not None and (c["clinician_id"] != owner or c["hidden_at"])):
            return None
        return copy.deepcopy(c)

    def rename(self, conv_id: str, owner: str, title: str | None) -> bool:
        c = self._convs.get(conv_id)
        if not c or c["clinician_id"] != owner or c["hidden_at"]:
            return False
        c["title"] = title
        return True

    def hide(self, conv_id: str, owner: str) -> bool:
        c = self._convs.get(conv_id)
        if not c or c["clinician_id"] != owner or c["hidden_at"]:
            return False
        c["hidden_at"] = _ago(0)
        return True


class DevConsultationStore:
    """DEV_MODE guided consultations (no database). Same calls as the db.* consultation functions."""

    def __init__(self) -> None:
        self._rows: dict[str, dict] = {}

    def new(self, owner: str, stage: str, state: dict) -> str:
        cid = str(uuid.uuid4())
        self._rows[cid] = {"id": cid, "owner": owner, "stage": stage, "state": copy.deepcopy(state),
                           "busy": False, "updated_at": _ago(0)}
        return cid

    def get(self, cid: str, owner: str) -> dict | None:
        r = self._rows.get(cid)
        if not r or r["owner"] != owner:
            return None
        return {"id": cid, "stage": r["stage"], "state": copy.deepcopy(r["state"]), "updated_at": r["updated_at"]}

    def claim(self, cid: str, owner: str):
        r = self._rows.get(cid)
        if not r or r["owner"] != owner:
            return None
        if r["busy"]:
            return "busy"
        r["busy"] = True
        return self.get(cid, owner)

    def save(self, cid: str, stage: str, state: dict) -> None:
        r = self._rows[cid]
        r.update(stage=stage, state=copy.deepcopy(state), busy=False, updated_at=_ago(0))

    def release(self, cid: str) -> None:
        if cid in self._rows:
            self._rows[cid]["busy"] = False

    def list_open(self, owner: str) -> list[dict]:
        rows = [r for r in self._rows.values() if r["owner"] == owner and r["stage"] != "COMPLETED"]
        return [{"id": r["id"], "stage": r["stage"], "updated_at": r["updated_at"],
                 "case_summary": (r["state"].get("case_summary") or "")[:160],
                 "questions_asked": r["state"].get("questions_asked", 0)}
                for r in sorted(rows, key=lambda r: r["updated_at"], reverse=True)][:10]
