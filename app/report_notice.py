"""The safety notice printed on every downloaded report (the web admin's PDF).

The same wording as the app's own PDF (mobile/lib/core/content/safety_content.dart)
and the crisis numbers of skill/clinical-assist/references/crisis-resources.md;
tests/test_report_notice.py fails if either drifts. App mechanics only: the clinical
disclaimer itself comes from the inspector.
"""
from __future__ import annotations

from .inspector import DISCLAIMER

PRECAUTIONS = (
    "For the treating clinician's professional use only. It is not a diagnosis, a prescription or a "
    "medico-legal record, and it does not replace your own assessment and clinical judgement.",
    "It contains de-identified information only. Do not add names, contact details or any other "
    "identifier to this file or to anything you attach it to.",
    "Keep it secure: store it only on a protected device or folder, do not send it by ordinary email "
    "or messaging apps, and delete it when you no longer need it.",
    "Verify every suggestion before use: diagnostic codes, tools and timelines are to be confirmed by you. "
    "Do not share it with the client or others without your clinical judgement.",
    "If there is any immediate risk to the client, follow your local crisis pathway; do not wait for or "
    "rely on this document.",
)

CRISIS_LINES = (
    ("Emergency", "112"),
    ("Tele-MANAS", "14416"),
    ("Tele-MANAS toll-free", "1-800-891-4416"),
    ("Child Helpline", "1098"),
    ("Women Helpline", "181"),
)

VERIFIED_NOTE = "Numbers verified to 24 Sep 2026; confirm your local pathway."

FOOTER = "YourCounselor · Confidential · De-identified · For professional use only"


def report_notice() -> dict:
    return {
        "precautions": list(PRECAUTIONS),
        "crisis_line": "In an emergency (India): " + " · ".join(f"{s} {n}" for s, n in CRISIS_LINES)
                       + f". {VERIFIED_NOTE}",
        "disclaimer": DISCLAIMER,
        "footer": FOOTER,
    }
