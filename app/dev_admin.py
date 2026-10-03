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
