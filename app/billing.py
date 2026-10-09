"""
Pricing plans and report entitlements: the rules, with no web or database code.

  * The admin edits one configuration (four plans, currency, renewal and rollover rules). It is
    validated here and stored as a new version (db: pricing_config); the app reads it on every visit,
    so prices change without an app release.
  * Money is in minor units (paise for INR). The app never sends an amount: the server prices each
    order from the current configuration.
  * Pricing is OFF by default. While it is off, reports are generated exactly as before, free.
  * When it is on, a report needs one credit (a per-report purchase of that report type, or a
    subscription credit), or the clinician's own Anthropic key (BYOK) when that plan is enabled.
    BYOK uses credits only if the admin says so; it never falls back to the platform key.
"""
from __future__ import annotations

import copy
from dataclasses import dataclass

PLANS = ("per_report", "sub_30", "sub_50", "byok")
REPORT_TYPES = ("guided", "direct")
CURRENCIES = ("INR",)
MAX_PRICE = 10_000_000        # ₹1,00,000 in paise: a typo guard, not a business limit
MAX_REPORTS = 10_000
MAX_DAYS = 366
TEXT_LIMITS = {"name": 60, "description": 400, "feature": 120, "instructions": 1000}

DEFAULT_CONFIG: dict = {
    "enabled": False,
    "currency": "INR",
    "payment_method": "razorpay",
    "renewal": "immediate",      # a renewal starts now; the earlier period's credits stay usable until it ends
    "rollover": False,           # if on, unused credits of an active subscription move to the renewal's end
    "plans": {
        "per_report": {"enabled": True, "visible": True, "order": 1,
                       "name": "Pay per report",
                       "description": "Buy a single report when you need one.",
                       "features": ["No subscription", "Credit never expires"],
                       "prices": {"guided": 19900, "direct": 9900}},
        "sub_30": {"enabled": True, "visible": True, "order": 2,
                   "name": "Monthly · 30 reports",
                   "description": "30 reports a month, guided or direct.",
                   "features": ["30 reports", "Guided and direct reports"],
                   "price": 199900, "reports": 30, "duration_days": 30},
        "sub_50": {"enabled": True, "visible": True, "order": 3,
                   "name": "Monthly · 50 reports",
                   "description": "50 reports a month, guided or direct.",
                   "features": ["50 reports", "Guided and direct reports"],
                   "price": 299900, "reports": 50, "duration_days": 30},
        "byok": {"enabled": False, "visible": True, "order": 4,
                 "name": "Use My Anthropic API Key",
                 "description": "Generate reports with your own Anthropic API key. Anthropic bills you "
                                "for its usage directly.",
                 "features": ["Billed by Anthropic", "Your key is stored encrypted"],
                 "instructions": "Create a key at console.anthropic.com → API keys, then paste it here. "
                                 "Your key is checked, stored encrypted and never shown again.",
                 "fee": 0, "fee_days": 30, "consumes_credits": False, "guided": True, "direct": True},
    },
}


class ConfigError(ValueError):
    """A configuration the admin may not save; .problems lists every reason."""
    def __init__(self, problems: list[str]):
        super().__init__("; ".join(problems))
        self.problems = problems


MIN_CHARGE = 100              # Razorpay's smallest payment: ₹1


def _money(problems: list, where: str, v) -> None:
    if not isinstance(v, int) or isinstance(v, bool) or v < 0 or v > MAX_PRICE or 0 < v < MIN_CHARGE:
        problems.append(f"{where}: 0 (free) or a whole number of paise from {MIN_CHARGE} to {MAX_PRICE}")


def _positive(problems: list, where: str, v, top: int) -> None:
    if not isinstance(v, int) or isinstance(v, bool) or v < 1 or v > top:
        problems.append(f"{where}: a whole number from 1 to {top}")


def _text(problems: list, where: str, v, limit: int, required: bool = True) -> None:
    if not isinstance(v, str) or (required and not v.strip()) or len(v) > limit:
        problems.append(f"{where}: {'required, ' if required else ''}at most {limit} characters")


def validate(cfg: dict) -> dict:
    """Returns the normalised configuration, or raises ConfigError listing every problem."""
    problems: list[str] = []
    if not isinstance(cfg, dict):
        raise ConfigError(["configuration must be an object"])
    out = copy.deepcopy(DEFAULT_CONFIG)
    unknown = set(cfg) - set(out)
    if unknown:
        problems.append("unknown settings: " + ", ".join(sorted(unknown)))
    for k in ("enabled", "rollover"):
        if k in cfg and not isinstance(cfg[k], bool):
            problems.append(f"{k}: true or false")
    if cfg.get("currency", "INR") not in CURRENCIES:
        problems.append("currency: INR")
    if cfg.get("payment_method", "razorpay") != "razorpay":
        problems.append("payment_method: razorpay")
    if cfg.get("renewal", "immediate") not in ("immediate",):
        problems.append("renewal: immediate")
    plans = cfg.get("plans", {})
    if not isinstance(plans, dict) or set(plans) - set(PLANS):
        problems.append("plans: only " + ", ".join(PLANS))
        plans = {}
    for name in PLANS:
        p = plans.get(name, {})
        if not isinstance(p, dict):
            problems.append(f"{name}: must be an object")
            continue
        base = out["plans"][name]
        extra = set(p) - set(base)
        if extra:
            problems.append(f"{name}: unknown settings " + ", ".join(sorted(extra)))
        merged = {**base, **{k: v for k, v in p.items() if k in base}}
        for flag in ("enabled", "visible") + (("consumes_credits", "guided", "direct") if name == "byok" else ()):
            if not isinstance(merged[flag], bool):
                problems.append(f"{name}.{flag}: true or false")
        _positive(problems, f"{name}.order", merged["order"], 99)
        _text(problems, f"{name}.name", merged["name"], TEXT_LIMITS["name"])
        _text(problems, f"{name}.description", merged["description"], TEXT_LIMITS["description"], required=False)
        if not isinstance(merged["features"], list) or len(merged["features"]) > 8:
            problems.append(f"{name}.features: at most 8")
        else:
            for i, f in enumerate(merged["features"]):
                _text(problems, f"{name}.features[{i}]", f, TEXT_LIMITS["feature"])
        if name == "per_report":
            prices = merged["prices"]
            if not isinstance(prices, dict) or set(prices) != set(REPORT_TYPES):
                problems.append("per_report.prices: guided and direct")
            else:
                for t in REPORT_TYPES:
                    _money(problems, f"per_report.prices.{t}", prices[t])
        elif name in ("sub_30", "sub_50"):
            _money(problems, f"{name}.price", merged["price"])
            _positive(problems, f"{name}.reports", merged["reports"], MAX_REPORTS)
            _positive(problems, f"{name}.duration_days", merged["duration_days"], MAX_DAYS)
        else:
            _money(problems, "byok.fee", merged["fee"])
            _positive(problems, "byok.fee_days", merged["fee_days"], MAX_DAYS)
            _text(problems, "byok.instructions", merged["instructions"], TEXT_LIMITS["instructions"], required=False)
            if merged["enabled"] and not (merged["guided"] or merged["direct"]):
                problems.append("byok: allow guided or direct reports (or switch the plan off)")
        out["plans"][name] = merged
    for k in ("enabled", "currency", "payment_method", "renewal", "rollover"):
        if k in cfg:
            out[k] = cfg[k]
    if out["enabled"] and not any(out["plans"][n]["enabled"] for n in PLANS):
        problems.append("pricing is on but every plan is off: switch one plan on, or pricing off")
    if problems:
        raise ConfigError(problems)
    return out


def diff(old: dict, new: dict, prefix: str = "") -> dict:
    """{"plans.sub_30.price": [old, new], ...} — what an admin changed, for the audit log."""
    out = {}
    for k in sorted(set(old) | set(new)):
        a, b, path = old.get(k), new.get(k), f"{prefix}{k}"
        if isinstance(a, dict) and isinstance(b, dict):
            out.update(diff(a, b, path + "."))
        elif a != b:
            out[path] = [a, b]
    return out


def newly_disabled(old: dict, new: dict) -> list[str]:
    """Plans switched off (or pricing switched off) by this change."""
    return [n for n in PLANS if old["plans"][n]["enabled"] and not new["plans"][n]["enabled"]]


# --- what the app sees ---------------------------------------------------------------
def public_plans(cfg: dict) -> dict:
    """Enabled, visible plans in display order. Prices in minor units plus currency."""
    plans = []
    for name in sorted(PLANS, key=lambda n: cfg["plans"][n]["order"]):
        p = cfg["plans"][name]
        if not (p["enabled"] and p["visible"]):
            continue
        row = {"id": name, "kind": "per_report" if name == "per_report" else "byok" if name == "byok"
               else "subscription", "name": p["name"], "description": p["description"],
               "features": list(p["features"]), "order": p["order"]}
        if name == "per_report":
            row["prices"] = dict(p["prices"])
        elif name == "byok":
            row.update(fee=p["fee"], fee_days=p["fee_days"], instructions=p["instructions"],
                       consumes_credits=p["consumes_credits"],
                       report_types=[t for t in REPORT_TYPES if p[t]])
        else:
            row.update(price=p["price"], reports=p["reports"], duration_days=p["duration_days"])
        plans.append(row)
    return {"enabled": cfg["enabled"], "currency": cfg["currency"], "plans": plans}


@dataclass(frozen=True)
class Price:
    plan: str
    report_type: str | None
    amount: int
    currency: str
    credits: int                 # credits granted on payment
    days: int | None             # validity; None = no expiry


class NotPurchasable(Exception):
    def __init__(self, detail: str):
        super().__init__(detail)
        self.detail = detail


def price_for(cfg: dict, plan: str, report_type: str | None) -> Price:
    """What a new order costs and grants, from the current configuration only."""
    if not cfg["enabled"]:
        raise NotPurchasable("pricing is switched off")
    if plan not in PLANS:
        raise NotPurchasable("unknown plan")
    p = cfg["plans"][plan]
    if not p["enabled"]:
        raise NotPurchasable("this plan is not available")
    if plan == "per_report":
        if report_type not in REPORT_TYPES:
            raise NotPurchasable("choose guided or direct")
        return Price(plan, report_type, p["prices"][report_type], cfg["currency"], 1, None)
    if report_type is not None:
        raise NotPurchasable("report_type is only for per-report purchases")
    if plan == "byok":
        if p["fee"] <= 0:
            raise NotPurchasable("no fee is due for this plan")
        return Price(plan, None, p["fee"], cfg["currency"], 0, p["fee_days"])
    return Price(plan, None, p["price"], cfg["currency"], p["reports"], p["duration_days"])


class NoCredit(Exception):
    """No usable credit for this report type."""


class AlreadyCharged(Exception):
    """This request was already generated and charged: it is not generated or charged again."""


class InProgress(Exception):
    """The same request is being generated right now."""
