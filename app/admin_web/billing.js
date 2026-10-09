// Your Counselor web admin: Pricing Plans, Subscriptions & Users, Payments & Transactions.
// Uses admin.js's helpers (el, put, api, icon, empty, skeletons, toast, busy, when, wireSeg, setSeg).
// Money is in paise on the server; shown and typed here in rupees. Every change goes through the
// backend, which validates it, needs a reason where it touches a clinician, and records it.
"use strict";

const PLAN = { per_report: "Per report", sub_30: "Monthly · 30 reports", sub_50: "Monthly · 50 reports",
               byok: "Own API key", manual: "Given by admin" };
const STATE = { active: ["Active", "ok"], scheduled: ["Starts later", "grey"], exhausted: ["Used up", "check"],
                expired: ["Expired", "grey"], cancelled: ["Cancelled", "crisis"], none: ["No plan", "grey"] };
const PAY = { paid: ["Paid", "ok"], pending: ["Pending", "check"], created: ["Not completed", "grey"],
              failed: ["Failed", "crisis"], cancelled: ["Cancelled", "grey"] };
const REFUND = { pending: "Refund in progress", refunded: "Refunded", partial: "Partly refunded", failed: "Refund failed" };
const LEDGER = { grant: "Added", reserve: "Held for a report", consume: "Used for a report", release: "Returned",
                 expire: "Expired", adjust: "Adjusted by admin", revoke: "Withdrawn" };
const AUDIT = { billing_grant: "Plan given", billing_adjust: "Credits adjusted", billing_extend: "Extended",
                billing_deactivate: "Deactivated", billing_activate: "Reactivated", billing_refund: "Refund started" };

function rupees(paise, currency = "INR") {
  if (paise == null) return "—";
  return (paise / 100).toLocaleString("en-IN", { style: "currency", currency, maximumFractionDigits: paise % 100 ? 2 : 0 });
}

// "1,999" / "1999.50" → paise; NaN if not a plain amount.
function toPaise(text) {
  const t = String(text).replace(/[₹,\s]/g, "");
  if (!/^\d+(\.\d{1,2})?$/.test(t)) return NaN;
  return Math.round(parseFloat(t) * 100);
}

function pill(map, key) {
  const [text, cls] = map[key] || [key || "—", "grey"];
  return el("span", { class: "pill " + cls, text });
}

function day(iso) {
  return iso ? new Date(iso).toLocaleDateString(undefined, { day: "numeric", month: "short", year: "numeric" }) : "—";
}

function isoDate(input, endOfDay) {
  const v = input.value;
  if (!v) return null;
  return new Date(v + (endOfDay ? "T23:59:59" : "T00:00:00")).toISOString();
}

function query(params) {
  const q = Object.entries(params).filter(([, v]) => v != null && v !== "")
    .map(([k, v]) => encodeURIComponent(k) + "=" + encodeURIComponent(v)).join("&");
  return q ? "?" + q : "";
}

function table(head, rows) {
  if (!rows.length) return null;
  return el("div", { class: "bill-table" }, el("table", {},
    el("thead", {}, el("tr", {}, ...head.map((h) => el("th", { text: h })))),
    el("tbody", {}, ...rows.map((r) => el("tr", {}, ...r.map((c) => el("td", {}, c instanceof Node ? c : String(c ?? "—"))))))));
}

function field(label, input, hint) {
  const id = input.id || ("f-" + Math.random().toString(36).slice(2));
  input.id = id;
  return el("div", { class: "field" }, el("label", { for: id, text: label }), input,
    hint ? el("p", { class: "muted small", text: hint }) : null);
}

function check(label, checked, hint) {
  const box = el("input", { type: "checkbox" });
  box.checked = !!checked;
  return { box, node: el("label", { class: "check-row" }, box, el("span", {}, el("b", { text: label }),
    hint ? el("span", { class: "muted small", text: " " + hint }) : null)) };
}

// One dialog for every billing action: fills it, runs onSubmit (which throws to show an error).
function formDialog({ title, body, ok = "Save", danger = false, onSubmit }) {
  const dlg = $("bill-dialog");
  $("bill-title").textContent = title;
  put($("bill-body"), ...body);
  $("bill-error").textContent = "";
  $("bill-ok").textContent = ok;
  $("bill-ok").className = danger ? "btn danger solid" : "btn primary";
  $("bill-cancel").onclick = () => dlg.close();
  $("bill-form").onsubmit = (e) => {
    e.preventDefault();
    busy($("bill-ok"), async () => {
      $("bill-error").textContent = "";
      try { await onSubmit(); dlg.close(); } catch (err) {
        if (err.message !== "signed-out") $("bill-error").textContent = err.message;
      }
    });
  };
  dlg.showModal();
}

function reasonInput(placeholder) {
  return el("input", { required: "", minlength: "3", maxlength: "300", placeholder: placeholder || "Why (required; recorded)" });
}

function needReason(input) {
  const r = input.value.trim();
  if (r.length < 3) throw new Error("Give a reason (at least 3 characters).");
  return r;
}

function clearBilling() {
  for (const id of ["pricing-body", "subs-list", "subs-detail", "pay-stats", "pay-by-plan", "pay-list", "byok-usage"]) {
    $(id).replaceChildren();
  }
  $("subs-detail").hidden = true;
}

// --- Pricing Plans ------------------------------------------------------------------------
let pricing = null;     // {version, config, active, payments_configured, byok_configured}

async function loadPricing() {
  const box = $("pricing-body");
  box.replaceChildren(...skeletons(3));
  try {
    const [p, h] = await Promise.all([api("GET", "/v1/admin/pricing"),
                                      api("GET", "/v1/admin/pricing/history").catch(() => ({ history: [] }))]);
    pricing = p;
    renderPricing(h.history);
  } catch (err) {
    if (err.message !== "signed-out") box.replaceChildren(el("p", { class: "error", text: "Couldn't load pricing: " + err.message }));
  }
}

function moneyInput(paise) {
  const input = el("input", { inputmode: "decimal", class: "money", autocomplete: "off" });
  input.value = paise === 0 ? "0" : String(paise / 100);
  return input;
}

function numberInput(n, min, max) {
  const input = el("input", { type: "number", min: String(min), max: String(max), step: "1" });
  input.value = String(n);
  return input;
}

function renderPricing(history) {
  const cfg = pricing.config;
  const form = {};      // getters that rebuild the configuration from the inputs
  const status = el("div", { class: "chips" },
    el("span", { class: "pill " + (pricing.payments_configured ? "ok" : "check"),
      text: pricing.payments_configured ? "Razorpay connected" : "Razorpay keys not set on the server" }),
    el("span", { class: "pill " + (pricing.byok_configured ? "ok" : "grey"),
      text: pricing.byok_configured ? "Own-key encryption ready" : "Own-key encryption not set up" }),
    el("span", { class: "pill grey", text: "Version " + pricing.version }));

  const on = check("Charge for reports", cfg.enabled,
    "When off, every report is free, as before. When on, a report needs a credit or the clinician's own key.");
  const roll = check("Carry unused credits into the renewal", cfg.rollover,
    "If off, unused credits end with their 30-day period.");
  const general = el("section", { class: "panel" }, el("div", { class: "panel-head" }, el("h2", { text: "General" })),
    status, on.node,
    el("div", { class: "form-grid" },
      field("Currency", el("select", { disabled: "" }, el("option", { text: "INR (₹)" }))),
      field("Payment method", el("select", { disabled: "" }, el("option", { text: "Razorpay" })))),
    el("p", { class: "muted small", text: "A renewal starts at once; credits left from the earlier period stay usable until that period ends." }),
    roll.node);
  form.enabled = () => on.box.checked;
  form.rollover = () => roll.box.checked;

  const cards = ["per_report", "sub_30", "sub_50", "byok"].map((id) => planCard(id, cfg.plans[id], form));

  const errors = el("div", { class: "error", role: "alert" });
  const save = el("button", { type: "button", class: "btn primary", text: "Save changes" });
  const reset = el("button", { type: "button", class: "btn ghost", text: "Discard changes", onclick: () => renderPricing(history) });
  save.addEventListener("click", () => busy(save, () => savePricing(form, errors, false)));

  const hist = el("section", { class: "panel" }, el("div", { class: "panel-head" }, el("h2", { text: "Change history" })),
    history.length ? el("ul", { class: "history" }, ...history.map((h) => el("li", {},
      el("div", { class: "meta", text: when(h.created_at) + " · " + (h.actor_email || "admin") + " · version " + ((h.detail || {}).version ?? "") }),
      el("ul", {}, ...Object.entries((h.detail || {}).changes || {}).map(([k, [a, b]]) =>
        el("li", { text: describeChange(k, a, b) }))))))
      : empty("No changes saved yet."));

  put($("pricing-body"), general, el("div", { class: "plan-grid" }, ...cards),
    el("div", { class: "save-bar" }, errors, el("div", { class: "row" }, reset, save)), hist);
}

function describeChange(path, a, b) {
  const label = path.replace(/^plans\./, "").replace(/^(\w+)/, (m) => PLAN[m] || m);
  const money = /price|fee$/.test(path) ? rupees : (v) => JSON.stringify(v);
  return label + ": " + money(a) + " → " + money(b);
}

function planCard(id, p, form) {
  const active = (pricing.active || {})[id] || 0;
  const enabled = check("On sale", p.enabled);
  const visible = check("Shown in the app", p.visible);
  const name = el("input", { maxlength: "60" }); name.value = p.name;
  const desc = el("textarea", { maxlength: "400", rows: "2" }); desc.value = p.description;
  const feats = el("textarea", { rows: "3" }); feats.value = (p.features || []).join("\n");
  const order = numberInput(p.order, 1, 99);
  const body = [field("Name", name), field("Description", desc), field("Features (one per line, up to 8)", feats)];
  let extra = () => ({});
  if (id === "per_report") {
    const g = moneyInput(p.prices.guided), d = moneyInput(p.prices.direct);
    body.push(el("div", { class: "form-grid" }, field("Guided report (₹)", g), field("Direct report (₹)", d)));
    extra = () => ({ prices: { guided: toPaise(g.value), direct: toPaise(d.value) } });
  } else if (id === "sub_30" || id === "sub_50") {
    const price = moneyInput(p.price), reports = numberInput(p.reports, 1, 10000), days = numberInput(p.duration_days, 1, 366);
    body.push(el("div", { class: "form-grid three" }, field("Price (₹)", price), field("Reports", reports), field("Valid for (days)", days)));
    extra = () => ({ price: toPaise(price.value), reports: Number(reports.value), duration_days: Number(days.value) });
  } else {
    const fee = moneyInput(p.fee), days = numberInput(p.fee_days, 1, 366);
    const credits = check("Also uses report credits", p.consumes_credits, "Off: reports with their own key need no credit.");
    const guided = check("Guided reports", p.guided), direct = check("Direct reports", p.direct);
    const instr = el("textarea", { maxlength: "1000", rows: "3" }); instr.value = p.instructions;
    body.push(el("div", { class: "form-grid" }, field("Platform fee (₹, 0 = free)", fee), field("Fee covers (days)", days)),
      credits.node, el("p", { class: "muted small", text: "Allowed for:" }), guided.node, direct.node,
      field("Instructions shown to clinicians", instr),
      el("p", { class: "notice" }, icon("key"), el("span", { text: "Keys are checked with Anthropic, stored encrypted and never shown — not even here. A failed key never falls back to the platform key." })));
    extra = () => ({ fee: toPaise(fee.value), fee_days: Number(days.value), consumes_credits: credits.box.checked,
                     guided: guided.box.checked, direct: direct.box.checked, instructions: instr.value });
  }
  body.push(field("Order in the app", order));
  form[id] = () => ({ enabled: enabled.box.checked, visible: visible.box.checked, order: Number(order.value),
                      name: name.value.trim(), description: desc.value.trim(),
                      features: feats.value.split("\n").map((f) => f.trim()).filter(Boolean), ...extra() });
  return el("section", { class: "panel plan-card" },
    el("div", { class: "panel-head" }, el("h2", { text: PLAN[id] }),
      active ? el("span", { class: "pill ok", text: active + " active" }) : el("span", { class: "pill grey", text: "No active users" })),
    el("div", { class: "toggles" }, enabled.node, visible.node), ...body);
}

async function savePricing(form, errors, confirmDisable) {
  errors.replaceChildren();
  const config = { ...pricing.config, enabled: form.enabled(), rollover: form.rollover(), plans: {} };
  for (const id of ["per_report", "sub_30", "sub_50", "byok"]) config.plans[id] = form[id]();
  const bad = [];
  const money = (v, where) => { if (Number.isNaN(v)) bad.push(where + ": enter an amount in rupees, like 199 or 199.50"); };
  money(config.plans.per_report.prices.guided, "Per report · guided");
  money(config.plans.per_report.prices.direct, "Per report · direct");
  money(config.plans.sub_30.price, PLAN.sub_30); money(config.plans.sub_50.price, PLAN.sub_50);
  money(config.plans.byok.fee, "Own API key · fee");
  if (bad.length) { errors.replaceChildren(el("ul", {}, ...bad.map((b) => el("li", { text: b })))); return; }
  try {
    const r = await api("PUT", "/v1/admin/pricing", { config, confirm_disable: confirmDisable });
    const n = Object.keys(r.changes || {}).length;
    toast(n ? "Saved " + n + " change" + (n > 1 ? "s" : "") + " (version " + r.version + ")" : "Nothing changed");
    loadPricing();
  } catch (err) {
    if (err.message === "signed-out") return;
    const d = err.data || {};
    if (d.error === "confirm_disable") {
      const list = el("ul", {}, ...Object.entries(d.affected).map(([p, n]) =>
        el("li", { text: (PLAN[p] || p) + ": " + n + " clinician" + (n > 1 ? "s" : "") + " on it now" })));
      formDialog({ title: "Stop selling these plans?", ok: "Yes, save", danger: true,
        body: [list, el("p", { class: "muted small", text: "Their current plans keep working until they end. New purchases stop." })],
        onSubmit: () => savePricing(form, errors, true) });
      return;
    }
    if (d.error === "invalid_config") {
      errors.replaceChildren(el("p", { text: "Please fix:" }), el("ul", {}, ...d.problems.map((x) => el("li", { text: x }))));
      return;
    }
    errors.textContent = "Couldn't save: " + err.message;
  }
}

// --- Subscriptions & Users ---------------------------------------------------------------------
let subsTimer = null;

async function loadSubs() {
  const list = $("subs-list");
  list.replaceChildren(...skeletons(4));
  try {
    const { users } = await api("GET", "/v1/admin/billing/users" + query({
      q: $("subs-q").value.trim(), plan: $("subs-plan").value, state: $("subs-state").value, payment: $("subs-pay").value,
      since: isoDate($("subs-since")), until: isoDate($("subs-until"), true) }));
    if (!users.length) { list.replaceChildren(empty("No clinicians match.", "search")); return; }
    list.replaceChildren(...users.map((u) => el("button", {
      type: "button", class: "row-item sev-low", onclick: (e) => { markSelected(list, e.currentTarget); openSub(u); } },
      el("div", { class: "head" }, el("span", { class: "title", text: u.full_name || u.email || u.id }),
        u.plan ? pill(STATE, u.state) : el("span", { class: "pill grey", text: "No plan" })),
      el("div", { class: "meta", text: [u.plan ? PLAN[u.plan] : null, u.remaining + " credits left", u.reports_charged + " reports charged",
        u.last_order ? "last payment " + ((PAY[u.last_order.status] || [u.last_order.status])[0]).toLowerCase() + " " + day(u.last_order.created_at) : null,
        u.byok_status ? "own key " + u.byok_status : null].filter(Boolean).join(" · ") }))));
  } catch (err) {
    if (err.message !== "signed-out") list.replaceChildren(el("p", { class: "error", text: "Couldn't load: " + err.message }));
  }
}

async function openSub(u) {
  const box = $("subs-detail");
  box.hidden = false;
  reveal(box);
  box.replaceChildren(...skeletons(3));
  try {
    const d = await api("GET", "/v1/admin/billing/users/" + encodeURIComponent(u.id));
    const reload = () => { openSub(u); loadSubs(); };
    const ents = d.entitlements.map((e) => el("div", { class: "ent" },
      el("div", { class: "head" }, el("b", { text: PLAN[e.plan] + (e.report_type ? " · " + e.report_type : "") }), pill(STATE, e.state)),
      el("div", { class: "meta", text: (e.plan === "byok" ? "Access to own-key reports" : e.credits_used + " of " + e.credits_total + " used · " + e.remaining + " left") +
        " · " + day(e.starts_at) + " → " + (e.expires_at ? day(e.expires_at) : "no end") + (e.note ? " · " + e.note : "") }),
      el("div", { class: "actions" },
        e.expires_at ? el("button", { type: "button", class: "btn ghost small", text: "Extend…", onclick: () => extendDialog(e, reload) }) : null,
        el("button", { type: "button", class: "btn ghost small", text: e.state === "cancelled" ? "Reactivate…" : "Deactivate…",
          onclick: () => statusDialog(e, e.state === "cancelled", reload) }))));
    const k = d.byok;
    put(box,
      el("h2", { text: u.full_name || u.email || u.id }),
      el("p", { class: "muted small", text: [u.full_name ? u.email : null, u.level, u.verification_status].filter(Boolean).join(" · ") }),
      el("div", { class: "actions" },
        el("button", { type: "button", class: "btn primary small", text: "Give a plan…", onclick: () => grantDialog(u, reload) }),
        el("button", { type: "button", class: "btn ghost small", text: "Adjust credits…", onclick: () => adjustDialog(u, reload) })),
      el("h3", { text: "Plans and credits" }), ...(ents.length ? ents : [empty("No plans or credits.")]),
      el("h3", { text: "Own Anthropic key" }),
      el("p", { class: "small", text: k ? "Status: " + k.status + " · ends in …" + k.last4 + " · last checked " + when(k.validated_at) +
        (k.last_error ? " · last problem: " + k.last_error : "") : "Not connected." }),
      el("h3", { text: "Payments" }),
      table(["Date", "Plan", "Amount", "Status", "Razorpay payment"], d.orders.map((o) => [when(o.created_at),
        PLAN[o.plan] + (o.report_type ? " · " + o.report_type : ""), rupees(o.amount, o.currency),
        el("span", {}, pill(PAY, o.status), o.refund_status ? el("span", { class: "pill grey", text: REFUND[o.refund_status] }) : null),
        el("span", { class: "mono small", text: o.provider_payment_id || "—" })])) || el("p", { class: "muted small", text: "No payments." }),
      el("h3", { text: "Credit history" }),
      table(["Date", "What", "Credits", "Type", "Reason"], d.ledger.map((l) => [when(l.created_at), LEDGER[l.kind] || l.kind,
        (l.amount > 0 ? "+" : "") + l.amount, l.report_type || "any", l.reason || ""])) || el("p", { class: "muted small", text: "Nothing yet." }),
      el("h3", { text: "Admin changes" }),
      table(["Date", "Admin", "Change", "Details"], d.audit.map((a) => [when(a.created_at), a.actor_email || "admin",
        AUDIT[a.action] || a.action, auditDetail(a.detail)])) || el("p", { class: "muted small", text: "None." }));
  } catch (err) {
    if (err.message !== "signed-out") box.replaceChildren(el("p", { class: "error", text: "Couldn't load: " + err.message }));
  }
}

function auditDetail(d) {
  if (!d) return "";
  return Object.entries(d).filter(([k]) => !/_id$|^id$/.test(k))
    .map(([k, v]) => k.replace(/_/g, " ") + ": " + (typeof v === "object" ? JSON.stringify(v) : v)).join(" · ");
}

function grantDialog(u, done) {
  const plan = el("select", {}, el("option", { value: "sub_30", text: PLAN.sub_30 }), el("option", { value: "sub_50", text: PLAN.sub_50 }),
    el("option", { value: "manual", text: "Report credits (choose how many)" }), el("option", { value: "byok", text: "Own-key access (no fee)" }));
  const credits = el("input", { type: "number", min: "1", max: "10000", placeholder: "From the plan" });
  const days = el("input", { type: "number", min: "1", max: "366", placeholder: "From the plan" });
  const reason = reasonInput("e.g. Beta tester, complimentary month");
  formDialog({ title: "Give a plan to " + (u.full_name || u.email), ok: "Give plan",
    body: [field("Plan", plan), el("div", { class: "form-grid" }, field("Credits", credits), field("Days", days)),
           el("p", { class: "muted small", text: "No payment is taken. Leave credits and days empty to use the plan's own." }),
           field("Reason", reason)],
    onSubmit: async () => {
      const r = needReason(reason);
      if (plan.value === "manual" && !credits.value) throw new Error("Say how many credits to give.");
      await api("POST", "/v1/admin/billing/users/" + encodeURIComponent(u.id) + "/grant", {
        plan: plan.value, credits: credits.value ? Number(credits.value) : null, days: days.value ? Number(days.value) : null, reason: r });
      toast("Plan given");
      done();
    } });
}

function adjustDialog(u, done) {
  const delta = el("input", { type: "number", min: "-10000", max: "10000", step: "1", placeholder: "e.g. 5 or -2" });
  const reason = reasonInput("e.g. Report failed twice; goodwill");
  formDialog({ title: "Adjust credits · " + (u.full_name || u.email), ok: "Adjust",
    body: [field("Credits to add (use a minus sign to remove)", delta), field("Reason", reason)],
    onSubmit: async () => {
      const r = needReason(reason);
      const n = Number(delta.value);
      if (!Number.isInteger(n) || n === 0) throw new Error("Enter a whole number other than 0.");
      const res = await api("POST", "/v1/admin/billing/users/" + encodeURIComponent(u.id) + "/adjust", { delta: n, reason: r });
      toast("Credits adjusted · " + res.balance.any + " general credits now");
      done();
    } });
}

function extendDialog(e, done) {
  const days = el("input", { type: "number", min: "1", max: "366", value: "7" });
  const reason = reasonInput("e.g. Service outage on 3 Oct");
  formDialog({ title: "Extend " + PLAN[e.plan], ok: "Extend",
    body: [el("p", { class: "muted small", text: "Now ends " + day(e.expires_at) + "." }), field("Add days", days), field("Reason", reason)],
    onSubmit: async () => {
      const r = needReason(reason);
      const res = await api("POST", "/v1/admin/billing/entitlements/" + encodeURIComponent(e.id) + "/extend", { days: Number(days.value), reason: r });
      toast("Now ends " + day(res.expires_at));
      done();
    } });
}

function statusDialog(e, activate, done) {
  const reason = reasonInput(activate ? "e.g. Deactivated by mistake" : "e.g. Payment disputed");
  formDialog({ title: (activate ? "Reactivate " : "Deactivate ") + PLAN[e.plan] + "?", ok: activate ? "Reactivate" : "Deactivate",
    danger: !activate,
    body: [el("p", { class: "muted small", text: activate ? "Its unused credits can be used again until it ends."
      : "Its unused credits stop working at once. No money is refunded: use Payments → Refund for that." }), field("Reason", reason)],
    onSubmit: async () => {
      await api("POST", "/v1/admin/billing/entitlements/" + encodeURIComponent(e.id) + "/status", { active: activate, reason: needReason(reason) });
      toast(activate ? "Reactivated" : "Deactivated");
      done();
    } });
}

// --- Payments & Transactions -------------------------------------------------------------------
let payStatus = "";

async function loadPayments() {
  $("pay-stats").replaceChildren(...skeletons(4));
  $("pay-list").replaceChildren(...skeletons(3));
  const range = { since: isoDate($("pay-since")), until: isoDate($("pay-until"), true) };
  try {
    const [sum, list, usage] = await Promise.all([
      api("GET", "/v1/admin/payments/summary" + query(range)),
      api("GET", "/v1/admin/payments" + query({ ...range, status: payStatus, plan: $("pay-plan").value, q: $("pay-q").value.trim() })),
      api("GET", "/v1/admin/byok/usage").catch(() => null)]);
    renderSummary(sum.by_plan);
    renderPaymentList(list.payments);
    renderUsage(usage);
  } catch (err) {
    if (err.message !== "signed-out") {
      $("pay-stats").replaceChildren(el("p", { class: "error", text: "Couldn't load payments: " + err.message }));
      $("pay-list").replaceChildren();
    }
  }
}

function renderSummary(rows) {
  const total = (k) => rows.reduce((s, r) => s + Number(r[k] || 0), 0);
  const stat = (num, label, ico, cls) => el("div", { class: "stat " + cls },
    el("span", { class: "num", text: num }), el("span", { class: "lbl" }, icon(ico), el("span", { text: label })));
  put($("pay-stats"),
    stat(rupees(total("collected")), "Collected (" + total("paid_count") + " paid)", "check", ""),
    stat(rupees(total("refunded")), "Refunded", "refresh", ""),
    stat(rupees(total("pending")), "Pending · not counted (" + total("pending_count") + ")", "warn", total("pending_count") ? "warn" : ""),
    stat(rupees(total("failed")), "Failed · not counted (" + total("failed_count") + ")", "flag", ""));
  put($("pay-by-plan"), table(["Plan", "Paid", "Collected", "Refunded", "Pending (not counted)", "Failed"],
    rows.map((r) => [PLAN[r.plan] || r.plan, r.paid_count, rupees(r.collected, r.currency), rupees(r.refunded, r.currency),
      rupees(r.pending, r.currency) + " · " + r.pending_count, rupees(r.failed, r.currency) + " · " + r.failed_count]))
    || el("p", { class: "muted small", text: "No payments in this period." }));
}

function renderPaymentList(rows) {
  put($("pay-list"), table(["Date", "Clinician", "Plan", "Amount", "Status", "Razorpay", ""], rows.map((o) => {
    const left = o.amount - (o.refunded_amount || 0);
    const canRefund = o.status === "paid" && o.provider_payment_id && o.refund_status !== "pending" && left > 0;
    return [when(o.created_at), el("span", {}, el("b", { text: o.full_name || "—" }), el("br"), el("span", { class: "muted small", text: o.email || "" })),
      PLAN[o.plan] + (o.report_type ? " · " + o.report_type : ""), rupees(o.amount, o.currency),
      el("span", {}, pill(PAY, o.status), o.refund_status ? el("span", { class: "pill grey",
        text: REFUND[o.refund_status] + (o.refunded_amount ? " " + rupees(o.refunded_amount, o.currency) : "") }) : null,
        o.failure_reason && o.status !== "paid" ? el("div", { class: "muted small", text: o.failure_reason }) : null),
      el("span", { class: "mono small", text: [o.provider_order_id, o.provider_payment_id].filter(Boolean).join("\n") || "—" }),
      canRefund ? el("button", { type: "button", class: "btn ghost small", text: "Refund…", onclick: () => refundDialog(o, left) }) : ""];
  })) || empty("No transactions match."));
}

function refundDialog(o, left) {
  const amount = moneyInput(left);
  const revoke = check("Withdraw this purchase's unused credits", true);
  const reason = reasonInput("e.g. Bought the wrong plan");
  formDialog({ title: "Refund " + (o.full_name || o.email || "payment"), ok: "Refund through Razorpay", danger: true,
    body: [el("p", { class: "muted small", text: PLAN[o.plan] + " · paid " + rupees(o.amount, o.currency) + " on " + day(o.paid_at || o.created_at) +
             ". Up to " + rupees(left, o.currency) + " can be refunded. This can't be undone." }),
           field("Amount (₹)", amount), revoke.node, field("Reason", reason)],
    onSubmit: async () => {
      const r = needReason(reason);
      const paise = toPaise(amount.value);
      if (Number.isNaN(paise) || paise < 100 || paise > left) throw new Error("Enter an amount from ₹1 to " + rupees(left, o.currency) + ".");
      const res = await api("POST", "/v1/admin/payments/" + encodeURIComponent(o.id) + "/refund",
        { amount: paise, revoke_credits: revoke.box.checked, reason: r });
      toast(res.refund.status === "processed" ? "Refunded" : "Refund started; Razorpay will confirm it");
      loadPayments();
    } });
}

function renderUsage(u) {
  if (!u) { $("byok-usage").replaceChildren(el("p", { class: "muted small", text: "Not available." })); return; }
  const OUT = { ok: "Delivered", held_back: "Held back by safety check", invalid_key: "Key refused", no_access: "No model access",
                rate_limited: "Rate limited", insufficient_balance: "Anthropic balance too low", provider_error: "Anthropic error" };
  put($("byok-usage"),
    el("p", { class: "small", text: "Keys connected: " + (Object.entries(u.keys || {}).map(([k, n]) => n + " " + k).join(", ") || "none") }),
    table(["Result", "Report type", "Reports", "Clinicians"], (u.usage || []).map((r) => [OUT[r.outcome] || r.outcome, r.report_type, r.n, r.clinicians]))
      || el("p", { class: "muted small", text: "No reports with own keys yet." }));
}

// --- wiring ------------------------------------------------------------------------------------
function wireBilling() {
  $("refresh-pricing").addEventListener("click", loadPricing);
  $("refresh-subs").addEventListener("click", () => loadSubs());
  $("refresh-payments").addEventListener("click", loadPayments);
  for (const id of ["subs-plan", "subs-state", "subs-pay", "subs-since", "subs-until"]) $(id).addEventListener("change", () => loadSubs());
  $("subs-q").addEventListener("input", () => { clearTimeout(subsTimer); subsTimer = setTimeout(loadSubs, 300); });
  wireSeg("pay-filter", (v) => { payStatus = v; loadPayments(); });
  for (const id of ["pay-plan", "pay-since", "pay-until"]) $(id).addEventListener("change", loadPayments);
  let t = null;
  $("pay-q").addEventListener("input", () => { clearTimeout(t); t = setTimeout(loadPayments, 300); });
}
