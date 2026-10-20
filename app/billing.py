"""
Pricing plans and report entitlements: the rules, with no web or database code.

  * The admin edits one configuration (the plans, currency, and how long a month and a year last). It is
    validated here and stored as a new version (db: pricing_config); the app reads it on every visit,
    so prices change without an app release.
  * Money is in minor units (paise for INR). The app never sends an amount: the server prices each
    order from the current configuration.
  * Pricing is OFF by default. While it is off, reports are generated exactly as before, free.
  * When it is on, each clinician's plan decides what they can use (FEATURES): Learn (the library;
    free for the first months), Practice (+ PDF downloads, booking page, appointments), BYOK Scale
    (+ unlimited AI-Guided Case Taking with their own Anthropic key) and Scale (+ AI-Guided reports
    every month, extra ones at Scale's price). Plans are prepaid by the month or the year.
  * A report needs a credit: Scale's monthly allowance or an extra (AI-Guided only), a per-report
    purchase of that type, or an admin grant. BYOK Scale's own-key reports use no credit and never
    fall back to the platform key. A quick (direct) consult is always bought per report.
  * A single print ("print") unlocks Print / Save as PDF for one education page for a few hours
    (24 by default). It is bought from that page, not from the plans list, and gives no credits.
"""
from __future__ import annotations

import copy
from dataclasses import dataclass

PLANS = ("per_report", "learn", "practice", "byok_scale", "scale", "print")
TIERS = ("learn", "practice", "byok_scale", "scale")          # bought by the month or the year
LISTED_PLANS = ("per_report",) + TIERS                         # on the app's plans screen
RETIRED_PLANS = ("sub_30", "sub_50", "byok")                   # kept in old orders; never sold again
PERIODS = ("month", "year")
MAX_PRINT_HOURS = 24 * 7
REPORT_TYPES = ("guided", "direct")
CURRENCIES = ("INR",)
MAX_PRICE = 10_000_000        # ₹1,00,000 in paise: a typo guard, not a business limit
MAX_REPORTS = 10_000
MAX_DAYS = 400
TEXT_LIMITS = {"name": 60, "description": 400, "feature": 120, "instructions": 1000, "badge": 30}

# What each plan unlocks. Fixed in code (the admin edits names, prices and periods, not what a plan is).
FEATURES = {
    "learn": ("library",),
    "practice": ("library", "pdf", "booking", "appointments"),
    "byok_scale": ("library", "pdf", "booking", "appointments", "guided_own_key"),
    "scale": ("library", "pdf", "booking", "appointments", "guided_included"),
}
ALL_FEATURES = frozenset(f for fs in FEATURES.values() for f in fs)
FEATURE_ROWS = (("library", "Full practice library"), ("pdf", "PDF downloads with your name"),
                ("booking", "Your booking page with your name and number"), ("appointments", "Appointments in the app"),
                ("guided", "AI-Guided Case Taking"))


def _tier(order: int, name: str, price_month: int, price_year: int, was_year: int = 0, **extra) -> dict:
    return {"enabled": True, "visible": True, "order": order, "name": name, "badge": "Launch offer",
            "description": "", "features": [], "sell_month": True, "sell_year": True,
            "price_month": price_month, "price_year": price_year, "was_month": 0, "was_year": was_year, **extra}


DEFAULT_CONFIG: dict = {
    "enabled": False,
    "currency": "INR",
    "payment_method": "razorpay",
    "renewal": "immediate",      # a renewal of the same plan starts when the current period ends
    "month_days": 30,            # how long "a month" and "a year" of a plan last
    "year_days": 365,
    "plans": {
        "per_report": {"enabled": True, "visible": True, "order": 5,
                       "name": "Pay per report",
                       "description": "Buy a single report when you need one.",
                       "features": ["No subscription", "Credit never expires"],
                       "prices": {"guided": 19900, "direct": 9900}},
        "learn": _tier(1, "Learn", 59900, 499900, trial_days=90),
        "practice": _tier(2, "Practice", 99900, 599900, 999900),
        "byok_scale": _tier(3, "BYOK Scale", 199900, 1499900, 1999900,
                            instructions="Create a key at console.anthropic.com → API keys, then paste it here. "
                                         "Your key is checked, stored encrypted and never shown again."),
        "scale": _tier(4, "Scale", 299900, 1999900, 2999900, guided_per_month=10, extra_price=12900),
        "print": {"enabled": True, "visible": True, "order": 6,
                  "name": "Print one page",
                  "description": "Print or save this page as a PDF as often as you need for 24 hours.",
                  "features": ["One page", "Print and save as PDF", "24 hours"],
                  "price": 4900, "hours": 24},
    },
}


def upgrade(cfg: dict) -> dict:
    """A configuration saved before the Learn/Practice/Scale plans: the retired plans and settings are
    dropped (their old orders and grants stay in the database), everything else is kept."""
    if not isinstance(cfg, dict):
        return cfg
    out = {k: v for k, v in cfg.items() if k != "rollover"}
    if isinstance(out.get("plans"), dict):
        out["plans"] = {k: v for k, v in out["plans"].items() if k not in RETIRED_PLANS}
    return out


def allowance_windows(days: int) -> int:
    """Scale's reports come per month: a year is 12 allowances, a month one."""
    return max(1, round(days / 30))


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
    cfg = upgrade(cfg)
    out = copy.deepcopy(DEFAULT_CONFIG)
    unknown = set(cfg) - set(out)
    if unknown:
        problems.append("unknown settings: " + ", ".join(sorted(unknown)))
    if "enabled" in cfg and not isinstance(cfg["enabled"], bool):
        problems.append("enabled: true or false")
    if cfg.get("currency", "INR") not in CURRENCIES:
        problems.append("currency: INR")
    if cfg.get("payment_method", "razorpay") != "razorpay":
        problems.append("payment_method: razorpay")
    if cfg.get("renewal", "immediate") not in ("immediate",):
        problems.append("renewal: immediate")
    for k in ("month_days", "year_days"):
        if k in cfg:
            _positive(problems, k, cfg[k], MAX_DAYS)
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
        for flag in ("enabled", "visible") + (("sell_month", "sell_year") if name in TIERS else ()):
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
        elif name == "print":
            _money(problems, "print.price", merged["price"])
            _positive(problems, "print.hours", merged["hours"], MAX_PRINT_HOURS)
        else:
            _text(problems, f"{name}.badge", merged["badge"], TEXT_LIMITS["badge"], required=False)
            for k in ("price_month", "price_year", "was_month", "was_year"):
                _money(problems, f"{name}.{k}", merged[k])
            for per in PERIODS:
                was, price = merged[f"was_{per}"], merged[f"price_{per}"]
                if isinstance(was, int) and isinstance(price, int) and was and was <= price:
                    problems.append(f"{name}.was_{per}: the old price must be more than the price (or 0 for none)")
            if merged["enabled"] and merged["sell_month"] is False and merged["sell_year"] is False:
                problems.append(f"{name}: sell it by the month or the year (or switch the plan off)")
            if name == "learn":
                if not isinstance(merged["trial_days"], int) or isinstance(merged["trial_days"], bool) \
                        or not 0 <= merged["trial_days"] <= MAX_DAYS:
                    problems.append(f"learn.trial_days: a whole number from 0 (no free months) to {MAX_DAYS}")
            elif name == "scale":
                _positive(problems, "scale.guided_per_month", merged["guided_per_month"], MAX_REPORTS)
                _money(problems, "scale.extra_price", merged["extra_price"])
            elif name == "byok_scale":
                _text(problems, "byok_scale.instructions", merged["instructions"], TEXT_LIMITS["instructions"],
                      required=False)
        out["plans"][name] = merged
    for k in ("enabled", "currency", "payment_method", "renewal", "month_days", "year_days"):
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
def rupees(paise: int) -> str:
    """₹12,999 style (Indian digit grouping), whole rupees unless there are paise."""
    r, p = divmod(int(paise), 100)
    s = str(r)
    if len(s) > 3:
        head, tail = s[:-3], s[-3:]
        groups = []
        while len(head) > 2:
            groups.insert(0, head[-2:])
            head = head[:-2]
        s = ",".join(([head] if head else []) + groups) + "," + tail
    return f"₹{s}" + (f".{p:02d}" if p else "")


def feature_text(cfg: dict, plan: str, key: str) -> str | None:
    """One cell of the plans table: what this plan gives for this row, or None for "Not included"."""
    have = FEATURES[plan]
    if key != "guided":
        return "Included" if key in have else None
    if "guided_own_key" in have:
        return "Unlimited, with your own AI key"
    if "guided_included" in have:
        p = cfg["plans"]["scale"]
        return f"{p['guided_per_month']} per month · extra {rupees(p['extra_price'])} each"
    return None


def public_plans(cfg: dict) -> dict:
    """Enabled, visible plans in display order, and the comparison table. Prices in minor units."""
    plans = []
    for name in sorted(LISTED_PLANS, key=lambda n: cfg["plans"][n]["order"]):
        p = cfg["plans"][name]
        if not (p["enabled"] and p["visible"]):
            continue
        row = {"id": name, "kind": "per_report" if name == "per_report" else "tier", "name": p["name"],
               "description": p["description"], "features": list(p["features"]), "order": p["order"]}
        if name == "per_report":
            row["prices"] = dict(p["prices"])
        else:
            row.update(badge=p["badge"], includes=list(FEATURES[name]),
                       periods=[per for per in PERIODS if p[f"sell_{per}"]],
                       **{k: p[k] for k in ("price_month", "price_year", "was_month", "was_year")},
                       table={k: feature_text(cfg, name, k) for k, _ in FEATURE_ROWS})
            if name == "learn":
                row["trial_days"] = p["trial_days"]
            if name == "scale":
                row.update(guided_per_month=p["guided_per_month"], extra_price=p["extra_price"])
            if name == "byok_scale":
                row["instructions"] = p["instructions"]
        plans.append(row)
    return {"enabled": cfg["enabled"], "currency": cfg["currency"], "plans": plans,
            "rows": [{"key": k, "label": label} for k, label in FEATURE_ROWS],
            "month_days": cfg["month_days"], "year_days": cfg["year_days"]}


@dataclass(frozen=True)
class Price:
    plan: str
    report_type: str | None
    amount: int
    currency: str
    credits: int                 # credits granted on payment (Scale: every month's reports together)
    days: int | None             # validity; None = no expiry
    item: str | None = None      # single print: the education page (slug)
    period: str | None = None    # a plan: month · year


class NotPurchasable(Exception):
    def __init__(self, detail: str):
        super().__init__(detail)
        self.detail = detail


def price_for(cfg: dict, plan: str, report_type: str | None, item: str | None = None,
              period: str | None = None) -> Price:
    """What a new order costs and grants, from the current configuration only. "scale_extra" is one
    more AI-Guided report for someone on Scale (the caller checks they are)."""
    if not cfg["enabled"]:
        raise NotPurchasable("pricing is switched off")
    if plan == "scale_extra":
        p = cfg["plans"]["scale"]
        if not p["enabled"]:
            raise NotPurchasable("this plan is not available")
        if report_type not in (None, "guided") or item is not None or period is not None:
            raise NotPurchasable("an extra report is one AI-Guided report")
        return Price(plan, "guided", p["extra_price"], cfg["currency"], 1, None)
    if plan not in PLANS:
        raise NotPurchasable("unknown plan")
    p = cfg["plans"][plan]
    if not p["enabled"]:
        raise NotPurchasable("this plan is not available")
    if plan in TIERS:
        if report_type is not None or item is not None:
            raise NotPurchasable("a plan is bought by the month or the year")
        if period not in PERIODS or not p[f"sell_{period}"]:
            raise NotPurchasable("choose monthly or yearly")
        days = cfg[f"{period}_days"]
        credits = p["guided_per_month"] * allowance_windows(days) if plan == "scale" else 0
        return Price(plan, None, p[f"price_{period}"], cfg["currency"], credits, days, period=period)
    if period is not None:
        raise NotPurchasable("only a plan has a period")
    if plan == "print":
        if report_type is not None or not item:
            raise NotPurchasable("choose the page to print")
        return Price(plan, None, p["price"], cfg["currency"], 0, None, item)
    if item is not None:
        raise NotPurchasable("a page is only for a single print")
    if report_type not in REPORT_TYPES:
        raise NotPurchasable("choose guided or direct")
    return Price(plan, report_type, p["prices"][report_type], cfg["currency"], 1, None)


class NoCredit(Exception):
    """No usable credit for this report type."""


class AlreadyCharged(Exception):
    """This request was already generated and charged: it is not generated or charged again."""


class InProgress(Exception):
    """The same request is being generated right now."""
