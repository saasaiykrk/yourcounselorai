"""
The AI models an admin may switch the platform to (web admin → AI Model).

CLAUDE.md rule 3: a model goes on this list only after `python -m evals.run_evals` (and the guided-
consultation evals), the clinician grading pack, a skill/clinical-assist/CHANGELOG.md entry and the
clinician-reviewed PR label. CI enforces the label for this file. Switching between listed models
is then an admin decision, recorded in admin_audit.
"""
from __future__ import annotations

APPROVED = (
    {"id": "claude-opus-5-5", "provider": "anthropic", "label": "Claude Opus 5.5",
     "note": "The pinned model: full eval suite and clinician grading."},
    {"id": "gemini-3.8-flash", "provider": "gemini", "label": "Gemini 3.8 Flash",
     "note": "Guided-consultation evals 13 Oct 2026: 16/16 cases passed the automatic checks."},
)
PROVIDERS = ("anthropic", "gemini")


def find(model_id: str) -> dict | None:
    return next((m for m in APPROVED if m["id"] == model_id), None)
