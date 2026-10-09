// Your Counselor web admin. Talks only to this backend (/v1/admin/*) and to
// Supabase Auth for the email code. No third-party scripts. All data is shown
// with textContent, never as HTML. The session lives in sessionStorage (gone
// when the tab closes) and ends when the admin signs out.
"use strict";

const KEY = "yc_admin_session";
const $ = (id) => document.getElementById(id);

let config = { supabase_url: "", supabase_publishable_key: "", dev_mode: false };
let pendingEmail = "";
let selectedIncident = null;
let clinicianStatus = "pending";
let incidentStatus = "open";
let clinicianRows = [];

// --- small DOM helpers ----------------------------------------------------
function el(tag, props = {}, ...children) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (k === "class") node.className = v;
    else if (k === "text") node.textContent = v;
    else if (k.startsWith("on")) node.addEventListener(k.slice(2), v);
    else node.setAttribute(k, v);
  }
  for (const c of children) if (c != null) node.append(c);
  return node;
}

// replaceChildren() would print null as "null": drop empty parts first.
function put(node, ...children) { node.replaceChildren(...children.filter((c) => c != null)); }

function show(view) {
  for (const id of ["view-sign-in", "view-denied", "view-admin"]) $(id).hidden = id !== view;
  $("who").hidden = view === "view-sign-in";
}

function when(iso) {
  if (!iso) return "";
  const d = new Date(iso);
  return d.toLocaleString(undefined, { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
}

const ROLE = { counsellor_trainee: "Counsellor / trainee", psychologist: "Psychologist", psychiatrist: "Psychiatrist" };
const CATEGORY = {
  blocked: "Held back by safety check", unsafe: "Unsafe", wrong_clinical: "Clinically wrong",
  missing_safety: "Missing safety content", identifier_leak: "Identifier leak", crisis_number: "Crisis number",
  other: "Other",
};
const STATUS = { open: "Open", triaged: "Triaged", fixed: "Fixed", wont_fix: "Won't fix" };

// --- session --------------------------------------------------------------
function loadSession() {
  try { return JSON.parse(sessionStorage.getItem(KEY) || "null"); } catch { return null; }
}
function saveSession(s) {
  try { sessionStorage.setItem(KEY, JSON.stringify(s)); } catch { /* private mode: session lasts for this page only */ }
  memorySession = s;
}
let memorySession = null;
function session() { return memorySession || loadSession(); }

async function signOut(message) {
  const s = session();
  memorySession = null;
  try { sessionStorage.removeItem(KEY); } catch { /* ignore */ }
  if (s && s.refresh_token && config.supabase_url) {
    fetch(config.supabase_url + "/auth/v1/logout", {
      method: "POST", headers: { apikey: config.supabase_publishable_key, Authorization: "Bearer " + s.access_token },
    }).catch(() => {});
  }
  $("clinician-list").replaceChildren();
  $("consult-list").replaceChildren();
  $("consult-detail").replaceChildren();
  $("incident-list").replaceChildren();
  $("incident-detail").replaceChildren();
  $("incident-detail").hidden = true;
  clearBilling();
  resetSignIn();
  $("sign-in-error").textContent = message || "";
  show("view-sign-in");
}

// --- Supabase Auth (email code) -------------------------------------------
async function supabaseAuth(path, body, query = "") {
  const r = await fetch(config.supabase_url + "/auth/v1/" + path + query, {
    method: "POST",
    headers: { apikey: config.supabase_publishable_key, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const data = await r.json().catch(() => ({}));
  if (!r.ok) {
    const code = data.error_code || data.code || r.status;
    const msg = {
      otp_disabled: "No admin account uses this email.",
      signup_disabled: "No admin account uses this email.",
      over_email_send_rate_limit: "Too many code requests. Wait a few minutes.",
      otp_expired: "That code is wrong or has expired.",
    }[code] || "Sign-in failed (" + code + ").";
    throw new Error(msg);
  }
  return data;
}

async function refreshSession() {
  const s = session();
  if (!s || !s.refresh_token) throw new Error("expired");
  const d = await supabaseAuth("token", { refresh_token: s.refresh_token }, "?grant_type=refresh_token");
  saveSession({ access_token: d.access_token, refresh_token: d.refresh_token,
                expires_at: Date.now() + (d.expires_in || 3600) * 1000, email: s.email });
}

// --- backend API ------------------------------------------------------------
async function api(method, path, body) {
  let s = session();
  if (!s) throw new Error("signed-out");
  if (s.refresh_token && Date.now() > s.expires_at - 60_000) { await refreshSession(); s = session(); }
  const r = await fetch(path, {
    method,
    headers: { Authorization: "Bearer " + s.access_token, ...(body ? { "Content-Type": "application/json" } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (r.status === 401) { await signOut("Your session ended. Please sign in again."); throw new Error("signed-out"); }
  const data = await r.json().catch(() => ({}));
  if (!r.ok) {
    const detail = typeof data.detail === "string" ? data.detail
      : (data.detail && data.detail.message) || "request failed";
    const err = new Error(detail); err.status = r.status; err.data = data.detail; throw err;
  }
  return data;
}

// --- sign-in flow ----------------------------------------------------------
function resetSignIn() {
  $("form-email").hidden = config.dev_mode;
  $("form-dev").hidden = !config.dev_mode;
  $("form-code").hidden = true;
  $("code").value = "";
  $("sign-in-help").textContent = config.dev_mode
    ? "DEV_MODE: sign in with the backend's dev token. No email is sent."
    : "Only existing admin accounts can sign in. We'll email you a 6-digit code.";
}

async function busy(button, fn) {
  button.disabled = true;
  try { return await fn(); } finally { button.disabled = false; }
}

function wireSignIn() {
  $("form-email").addEventListener("submit", (e) => {
    e.preventDefault();
    const btn = e.submitter || $("form-email").querySelector("button");
    busy(btn, async () => {
      $("sign-in-error").textContent = "";
      pendingEmail = $("email").value.trim();
      try {
        // create_user:false — the admin page never creates accounts.
        await supabaseAuth("otp", { email: pendingEmail, create_user: false });
        $("form-email").hidden = true;
        $("form-code").hidden = false;
        $("code").focus();
      } catch (err) { $("sign-in-error").textContent = err.message; }
    });
  });

  $("form-code").addEventListener("submit", (e) => {
    e.preventDefault();
    const btn = e.submitter || $("form-code").querySelector("button");
    busy(btn, async () => {
      $("sign-in-error").textContent = "";
      try {
        const d = await supabaseAuth("verify", { type: "email", email: pendingEmail, token: $("code").value.trim() });
        saveSession({ access_token: d.access_token, refresh_token: d.refresh_token,
                      expires_at: Date.now() + (d.expires_in || 3600) * 1000, email: pendingEmail });
        await enter();
      } catch (err) { $("sign-in-error").textContent = err.message; }
    });
  });

  $("change-email").addEventListener("click", resetSignIn);

  $("form-dev").addEventListener("submit", (e) => {
    e.preventDefault();
    saveSession({ access_token: $("dev-token").value.trim(), refresh_token: null,
                  expires_at: Number.MAX_SAFE_INTEGER, email: "dev admin" });
    enter();
  });

  $("sign-out").addEventListener("click", () => signOut());
  $("denied-sign-out").addEventListener("click", () => signOut());
}

async function enter() {
  try {
    const me = await api("GET", "/v1/me");
    if (!me.is_admin) { show("view-denied"); return; }
    const email = session().email || "";
    $("who-email").textContent = email;
    $("who-initial").textContent = (email[0] || "A").toUpperCase();
    show("view-admin");
    selectView("overview");
  } catch (err) {
    if (err.message !== "signed-out") $("sign-in-error").textContent = "Couldn't reach the backend. Try again.";
  }
}

// --- icons (Material Symbols paths, inlined: no third-party requests) -------------
const ICONS = {
  dashboard: "M3 13h8V3H3v10zm0 8h8v-6H3v6zm10 0h8V11h-8v10zm0-18v6h8V3h-8z",
  badge: "M20 7h-5V4c0-1.1-.9-2-2-2h-2c-1.1 0-2 .9-2 2v3H4c-1.1 0-2 .9-2 2v11c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V9c0-1.1-.9-2-2-2zM9 12c.83 0 1.5.67 1.5 1.5S9.83 15 9 15s-1.5-.67-1.5-1.5S8.17 12 9 12zm3 6H6v-.75c0-1 2-1.5 3-1.5s3 .5 3 1.5V18zm1-9h-2V4h2v5zm5 7.5h-4V15h4v1.5zm0-3h-4V12h4v1.5z",
  flag: "M14.4 6 14 4H5v17h2v-7h5.6l.4 2h7V6z",
  refresh: "M17.65 6.35A7.958 7.958 0 0 0 12 4c-4.42 0-7.99 3.58-7.99 8s3.57 8 7.99 8c3.73 0 6.84-2.55 7.73-6h-2.08A5.99 5.99 0 0 1 12 18c-3.31 0-6-2.69-6-6s2.69-6 6-6c1.66 0 3.14.69 4.22 1.78L13 11h7V4l-2.35 2.35z",
  search: "M15.5 14h-.79l-.28-.27A6.471 6.471 0 0 0 16 9.5 6.5 6.5 0 1 0 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z",
  download: "M5 20h14v-2H5v2zM19 9h-4V3H9v6H5l7 7 7-7z",
  shield: "M12 1 3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-4zm-2 16-4-4 1.41-1.41L10 14.17l6.59-6.59L18 9l-8 8z",
  copy: "M16 1H4c-1.1 0-2 .9-2 2v14h2V3h12V1zm3 4H8c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h11c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm0 16H8V7h11v14z",
  inbox: "M19 3H4.99C3.88 3 3 3.9 3 5l-.01 14c0 1.1.89 2 2 2H19c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm0 12h-4c0 1.66-1.35 3-3 3s-3-1.34-3-3H4.99V5H19v10z",
  warn: "M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z",
  check: "M9 16.17 4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z",
  payments: "M20 4H4c-1.11 0-1.99.89-1.99 2L2 18c0 1.11.89 2 2 2h16c1.11 0 2-.89 2-2V6c0-1.11-.89-2-2-2zm0 14H4v-6h16v6zm0-10H4V6h16v2z",
  sell: "m21.41 11.58-9-9C12.05 2.22 11.55 2 11 2H4c-1.1 0-2 .9-2 2v7c0 .55.22 1.05.59 1.42l9 9c.36.36.86.58 1.41.58.55 0 1.05-.22 1.41-.59l7-7c.37-.36.59-.86.59-1.41 0-.55-.23-1.06-.59-1.42zM5.5 7C4.67 7 4 6.33 4 5.5S4.67 4 5.5 4 7 4.67 7 5.5 6.33 7 5.5 7z",
  key: "M12.65 10A5.99 5.99 0 0 0 7 6c-3.31 0-6 2.69-6 6s2.69 6 6 6a5.99 5.99 0 0 0 5.65-4H17v4h4v-4h2v-4H12.65zM7 14c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2z",
  people: "M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5C6.34 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5zm8 0c-.29 0-.62.02-.97.05 1.16.84 1.97 1.97 1.97 3.45V19h6v-2.5c0-2.33-4.67-3.5-7-3.5z",
};

function icon(name) {
  const ns = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(ns, "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("aria-hidden", "true");
  const path = document.createElementNS(ns, "path");
  path.setAttribute("d", ICONS[name] || "");
  svg.append(path);
  return el("span", { class: "ico" }, svg);
}

function fillIcons(root = document) {
  for (const node of root.querySelectorAll("[data-icon]")) {
    if (!node.firstChild) node.replaceWith(icon(node.dataset.icon));
  }
}

function empty(text, name = "inbox") { return el("div", { class: "empty" }, icon(name), el("span", { text })); }
function skeletons(n = 3) { return Array.from({ length: n }, () => el("div", { class: "skeleton" })); }

let toastTimer = null;
function toast(text) {
  const t = $("toast");
  t.textContent = text;
  t.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { t.hidden = true; }, 2600);
}

function initials(name) {
  const parts = String(name || "").trim().split(/\s+/).filter((p) => !/^(dr|mr|mrs|ms|prof)\.?$/i.test(p));
  return ((parts[0] || "?")[0] + (parts.length > 1 ? parts[parts.length - 1][0] : "")).toUpperCase();
}

// --- views ----------------------------------------------------------------------
const VIEWS = ["overview", "clinicians", "incidents", "pricing", "subs", "payments"];   // the last three: billing.js

function selectView(name, filter) {
  showConsults(false);
  $("consult-list").replaceChildren();
  $("consult-detail").replaceChildren();
  for (const v of VIEWS) {
    const tab = $("tab-" + v);
    if (v === name) { tab.setAttribute("aria-current", "page"); tab.scrollIntoView?.({ block: "nearest", inline: "nearest" }); }
    else tab.removeAttribute("aria-current");
    $("panel-" + v).hidden = v !== name;
  }
  if (name === "clinicians") { if (filter != null) setSeg("clinician-filter", (clinicianStatus = filter)); loadClinicians(); }
  else if (name === "incidents") { if (filter != null) setSeg("incident-filter", (incidentStatus = filter)); loadIncidents(); }
  else if (name === "pricing") loadPricing();
  else if (name === "subs") loadSubs(filter);
  else if (name === "payments") loadPayments();
  else loadOverview();
  loadCounts();
  window.scrollTo(0, 0);
}

function setSeg(groupId, value) {
  for (const b of $(groupId).querySelectorAll("button")) b.setAttribute("aria-pressed", String(b.dataset.value === value));
}

function wireSeg(groupId, onPick) {
  $(groupId).addEventListener("click", (e) => {
    const b = e.target.closest("button[data-value]");
    if (!b) return;
    setSeg(groupId, b.dataset.value);
    onPick(b.dataset.value);
  });
}

async function loadCounts() {
  try {
    const [c, i] = await Promise.all([api("GET", "/v1/admin/clinicians?status=pending"),
                                      api("GET", "/v1/admin/incidents?status=open")]);
    $("count-pending").textContent = c.clinicians.length || "";
    $("count-open").textContent = i.incidents.length || "";
  } catch { /* counts are optional */ }
}

// --- overview -----------------------------------------------------------------
async function loadOverview() {
  const stats = $("stats");
  stats.replaceChildren(...skeletons(4));
  $("overview-pending").replaceChildren(...skeletons(2));
  $("overview-reports").replaceChildren(...skeletons(2));
  try {
    const [pending, verified, open] = await Promise.all([
      api("GET", "/v1/admin/clinicians?status=pending"),
      api("GET", "/v1/admin/clinicians?status=verified"),
      api("GET", "/v1/admin/incidents?status=open"),
    ]);
    const held = open.incidents.filter((i) => i.source === "inspector").length;
    const stat = (num, label, ico, cls, go) => el("button", { type: "button", class: "stat " + cls, onclick: go },
      el("span", { class: "num", text: String(num) }), el("span", { class: "lbl" }, icon(ico), el("span", { text: label })));
    stats.replaceChildren(
      stat(pending.clinicians.length, "Waiting for approval", "badge", pending.clinicians.length ? "warn" : "", () => selectView("clinicians", "pending")),
      stat(open.incidents.length, "Open reports", "flag", open.incidents.length ? "alert" : "", () => selectView("incidents", "open")),
      stat(held, "Held back by safety check", "warn", "", () => selectView("incidents", "open")),
      stat(verified.clinicians.length, "Verified clinicians", "people", "", () => selectView("clinicians", "verified")));
    $("overview-pending").replaceChildren(...(pending.clinicians.length
      ? pending.clinicians.slice(0, 5).map((c) => el("button", { type: "button", class: "row-item sev-low", onclick: () => selectView("clinicians", "pending") },
          el("div", { class: "head" }, el("span", { class: "title", text: c.full_name || c.email }), el("span", { class: "pill check", text: "Waiting" })),
          el("div", { class: "meta", text: (ROLE[c.role] || c.role) + " · " + registration(c) + " · " + when(c.created_at) })))
      : [empty("Nobody is waiting for approval.", "check")]));
    $("overview-reports").replaceChildren(...(open.incidents.length
      ? open.incidents.slice(0, 5).map((i) => incidentItem(i, () => { selectView("incidents", "open"); openIncident(i.id); }))
      : [empty("No open reports.", "check")]));
  } catch (err) {
    if (err.message !== "signed-out") stats.replaceChildren(el("p", { class: "error", text: "Couldn't load the overview." }));
  }
}

// --- registrations ------------------------------------------------------------
const GENDER = { female: "Female", male: "Male", other: "Other", prefer_not_to_say: "Not stated" };

function registration(c) {
  return c.registration_body && c.registration_body !== "none"
    ? c.registration_body + " " + (c.registration_number || "(no number)") : "No registration given";
}

async function loadClinicians() {
  const list = $("clinician-list");
  list.replaceChildren(...skeletons(4));
  try {
    const { clinicians } = await api("GET", "/v1/admin/clinicians?status=" + encodeURIComponent(clinicianStatus));
    clinicianRows = clinicians;
    renderClinicians();
  } catch (err) {
    if (err.message !== "signed-out") list.replaceChildren(el("p", { class: "error", text: "Couldn't load registrations." }));
  }
}

function renderClinicians() {
  const list = $("clinician-list");
  const q = $("clinician-search").value.trim().toLowerCase();
  const rows = clinicianRows.filter((c) => !q ||
    [c.full_name, c.email, c.registration_number].some((v) => (v || "").toLowerCase().includes(q)));
  if (!rows.length) {
    list.replaceChildren(empty(q ? "No registrations match \"" + q + "\"."
      : clinicianStatus === "pending" ? "Nobody is waiting for approval." : "None.", q ? "search" : "inbox"));
    return;
  }
  list.replaceChildren(...rows.map(clinicianCard));
}

function clinicianCard(c) {
  const status = c.verification_status;
  const pill = status === "verified" ? el("span", { class: "pill ok", text: "Verified · " + c.level })
    : status === "rejected" ? el("span", { class: "pill crisis", text: "Rejected" })
    : el("span", { class: "pill check", text: "Waiting" });
  const regNo = c.registration_body && c.registration_body !== "none" && c.registration_number;
  const regValue = el("dd", {}, el("span", { class: regNo ? "mono" : "", text: registration(c) }),
    regNo ? el("button", { type: "button", class: "copy", title: "Copy registration number", "aria-label": "Copy registration number",
      onclick: () => navigator.clipboard?.writeText(c.registration_number).then(() => toast("Registration number copied")) }, icon("copy")) : null);
  const fact = (label, value) => el("div", {}, el("dt", { text: label }), value instanceof Node ? value : el("dd", { text: value || "—" }));
  const personal = [GENDER[c.gender], c.age_at_registration ? c.age_at_registration + " yrs" : null].filter(Boolean).join(" · ");
  const card = el("article", { class: "card" },
    el("div", { class: "card-top" },
      el("div", { class: "person" }, el("span", { class: "avatar", text: initials(c.full_name || c.email) }),
        el("div", { class: "names" }, el("div", { class: "name", text: c.full_name || c.email || c.id }),
          el("div", { class: "sub", text: c.full_name ? c.email : "" }))),
      pill),
    el("dl", { class: "facts" },
      fact("Role", ROLE[c.role] || c.role),
      fact("Registration", regValue),
      fact("Gender · age", personal || "Not given"),
      fact(status === "pending" ? "Registered" : "Decided", when(status === "pending" ? c.created_at : (c.verified_at || c.created_at)))),
    c.verification_note ? el("p", { class: "note-line", text: "How it was checked: " + c.verification_note }) : null);
  if (status === "pending") {
    card.append(el("div", { class: "actions" },
      el("button", { type: "button", class: "btn primary", text: "Approve…", onclick: () => decide(c, "verified") }),
      el("button", { type: "button", class: "btn danger", text: "Reject…", onclick: () => decide(c, "rejected") })));
  } else if (status === "verified") {
    card.append(el("div", { class: "actions" },
      el("button", { type: "button", class: "btn ghost", text: "Consults ›", onclick: () => openConsults(c) }),
      el("button", { type: "button", class: "btn ghost", text: "Change level…", onclick: () => decide(c, "verified", true) })));
  }
  return card;
}

// Approve, reject, or (changeLevel) set a verified clinician's level again. All three go through
// the same audited PATCH; a level change needs a different level and a reason.
function decide(c, decision, changeLevel = false) {
  const dlg = $("decide");
  $("decide-title").textContent = changeLevel ? "Change level · now " + c.level
    : decision === "verified" ? "Approve registration" : "Reject registration";
  $("decide-who").replaceChildren(el("b", { text: c.full_name || c.email || "" }),
    el("span", { text: [c.full_name ? c.email : null, ROLE[c.role] || c.role, registration(c)].filter(Boolean).join(" · ") }));
  $("decide-level-row").hidden = decision !== "verified";
  const level = changeLevel && c.level ? c.level
    : c.role === "counsellor_trainee" ? "L1" : c.role === "psychiatrist" ? "L3" : "L2";
  for (const r of document.querySelectorAll("input[name='decide-level']")) r.checked = r.value === level;
  $("decide-note").value = "";
  $("decide-note").placeholder = changeLevel ? "e.g. Now a consultant psychiatrist, NMC register" : "e.g. RCI register, 2026-10-03";
  $("decide-note-label").textContent = changeLevel ? "Why the level changes (required)" : "How you checked (required)";
  $("decide-error").textContent = "";
  $("decide-ok").textContent = changeLevel ? "Change level" : decision === "verified" ? "Approve" : "Reject";
  $("decide-ok").className = decision === "verified" ? "btn primary" : "btn danger solid";

  $("decide-cancel").onclick = () => dlg.close();
  $("decide-form").onsubmit = (e) => {
    e.preventDefault();
    const note = $("decide-note").value.trim();
    const chosen = document.querySelector("input[name='decide-level']:checked");
    if (changeLevel && chosen && chosen.value === c.level) { $("decide-error").textContent = "Choose a different level."; return; }
    if (note.length < 3) {
      $("decide-error").textContent = changeLevel ? "Say why the level changes." : "Say how you checked the registration.";
      return;
    }
    busy($("decide-ok"), async () => {
      try {
        await api("PATCH", "/v1/admin/clinicians/" + encodeURIComponent(c.id), {
          verification_status: decision,
          level: decision === "verified" ? (chosen ? chosen.value : level) : null,
          evidence_note: note,
        });
        dlg.close();
        const who = c.full_name || c.email;
        toast(changeLevel ? "Level changed to " + chosen.value + " for " + who
          : decision === "verified" ? "Approved " + who : "Rejected " + who);
        loadClinicians();
        loadCounts();
      } catch (err) {
        if (err.message !== "signed-out") $("decide-error").textContent = "Couldn't save: " + err.message;
      }
    });
  };
  dlg.showModal();
}

// --- a clinician's consults (every view is recorded by the backend) ------------
const MODE = { A: "Full plan", B: "Quick review", C: "Differential", D: "Session plan", E: "Diagnosis review",
               F: "Notes", G: "Audit only", R: "Guided consultation", auto: "Auto" };

function showConsults(on) {
  $("panel-clinicians").hidden = on;
  $("panel-consults").hidden = !on;
}

async function openConsults(c) {
  showConsults(true);
  $("consults-who").textContent = c.full_name || c.email || c.id;
  const list = $("consult-list");
  $("consult-detail").hidden = true;
  list.replaceChildren(...skeletons(3));
  try {
    const { consults } = await api("GET", "/v1/admin/clinicians/" + encodeURIComponent(c.id) + "/consults");
    if (!consults.length) { list.replaceChildren(empty("No consults yet.")); return; }
    list.replaceChildren(...consults.map((x) => el("button", {
      type: "button", class: "row-item " + (x.last_status === "blocked" ? "sev-mid" : "sev-low"),
      onclick: (e) => { markSelected(list, e.currentTarget); openConsult(x.id); },
    },
    el("div", { class: "head" }, el("span", { class: "title", text: x.title || x.preview }),
      x.hidden_at ? el("span", { class: "pill grey", text: "Deleted by clinician" })
        : x.last_status === "blocked" ? el("span", { class: "pill check", text: "Held back" }) : null),
    el("div", { class: "meta", text: when(x.last_at || x.created_at) + " · " +
      (x.modes || []).map((m) => MODE[m] || m).join(", ") + (x.turns > 1 ? " · " + x.turns + " messages" : "") }))));
  } catch (err) {
    if (err.message !== "signed-out") list.replaceChildren(el("p", { class: "error", text: "Couldn't load consults." }));
  }
}

// On narrow screens the detail sits under the list: bring it into view.
function reveal(box) {
  if (window.matchMedia("(max-width: 900px)").matches) box.scrollIntoView({ behavior: "smooth", block: "start" });
}

function markSelected(list, item) {
  for (const b of list.children) b.classList?.remove("selected");
  item?.classList.add("selected");
}

// --- a report as formatted text --------------------------------------------
// The reply's markdown, built as DOM nodes with textContent only (never HTML), so
// nothing in a report can run or style the page. Links show their address as text.
const INLINE_RE = /\*\*(.+?)\*\*|__(.+?)__|\*([^*\s][^*]*?)\*|`([^`]+)`|\[([^\]]+)\]\(([^)\s]+)\)/g;

function inline(text) {
  const out = [];
  let at = 0;
  for (const m of text.matchAll(INLINE_RE)) {
    if (m.index > at) out.push(text.slice(at, m.index));
    if (m[1] != null || m[2] != null) out.push(el("strong", { text: m[1] ?? m[2] }));
    else if (m[3] != null) out.push(el("em", { text: m[3] }));
    else if (m[4] != null) out.push(m[4]);
    else out.push(`${m[5]} (${m[6]})`);
    at = m.index + m[0].length;
  }
  if (at < text.length) out.push(text.slice(at));
  return out;
}

function renderMarkdown(md) {
  const root = el("div", { class: "md" });
  let para = [], quote = [], rows = [], list = null;
  const flush = () => {
    if (para.length) root.append(el("p", {}, ...inline(para.join(" "))));
    if (quote.length) root.append(el("blockquote", {}, ...inline(quote.join(" "))));
    if (rows.length) {
      const [head, ...body] = rows;
      root.append(el("div", { class: "md-table" }, el("table", {},
        el("thead", {}, el("tr", {}, ...head.map((c) => el("th", {}, ...inline(c))))),
        el("tbody", {}, ...body.map((r) => el("tr", {}, ...head.map((_, i) => el("td", {}, ...inline(r[i] ?? "")))))))));
    }
    para = []; quote = []; rows = []; list = null;
  };
  for (const raw of md.replace(/<!--[\s\S]*?-->/g, "").split("\n")) {
    const line = raw.trimEnd(), t = line.trim();
    let m;
    if (!t) { flush(); continue; }
    if (t.startsWith("|")) {
      if (para.length || quote.length || list) { const keep = rows; rows = []; flush(); rows = keep; }
      if (/^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?$/.test(t)) continue;
      const cells = t.split("|").map((c) => c.trim());
      if (cells[0] === "") cells.shift();
      if (cells.length && cells[cells.length - 1] === "") cells.pop();
      rows.push(cells);
      continue;
    }
    if (rows.length) flush();
    if ((m = t.match(/^(#{1,6})\s+(.*?)\s*#*$/))) {
      flush();
      root.append(el("h" + Math.min(6, Math.max(2, m[1].length + 1)), { class: "md-h" + m[1].length }, ...inline(m[2])));
      continue;
    }
    if (/^([-*_])(\s*\1){2,}$/.test(t)) { flush(); root.append(el("hr")); continue; }
    if ((m = line.match(/^\s*>\s?(.*)$/))) { if (para.length || list) flush(); if (m[1].trim()) quote.push(m[1].trim()); continue; }
    if ((m = line.match(/^(\s*)([-*+]|\d{1,3}[.)])\s+(.*)$/))) {
      const ordered = /^\d/.test(m[2]);
      if (para.length || quote.length) flush();
      if (!list || list.ordered !== ordered) { list = { ordered, node: el(ordered ? "ol" : "ul") }; root.append(list.node); }
      const li = el("li", {}, ...inline(m[3]));
      if (m[1].length >= 2) li.className = "nested";
      list.node.append(li);
      continue;
    }
    if (quote.length) flush();
    if (list && raw.startsWith(" ") && !para.length) { list.node.lastChild.append(" ", ...inline(t)); continue; }
    list = null;
    para.push(t);
  }
  flush();
  return root;
}

// --- download a report as PDF ----------------------------------------------
// The browser's own "Save as PDF": the page is laid out for print with the same
// safety notice as the app's PDF (from /v1/admin/report-notice). The download is
// recorded in the audit log first; nothing else is sent anywhere.
let reportNotice = null;

function pdfConfirm() {
  return new Promise((resolve) => {
    const dlg = $("pdf-dialog");
    $("pdf-cancel").onclick = () => { dlg.close(); resolve(false); };
    $("pdf-form").onsubmit = (e) => { e.preventDefault(); dlg.close(); resolve(true); };
    dlg.oncancel = () => resolve(false);
    dlg.showModal();
  });
}

async function downloadPdf(convId, turn, button) {
  if (!(await pdfConfirm())) return;
  await busy(button, async () => {
    try {
      await api("POST", "/v1/admin/consults/" + encodeURIComponent(convId) + "/pdf", { turn_id: turn.id });
      reportNotice = reportNotice || await api("GET", "/v1/admin/report-notice");
    } catch (e) {
      if (e.message !== "signed-out") toast("Couldn't prepare the PDF: " + e.message);
      return;
    }
    const n = reportNotice;
    const report = turn.requested_mode === "R";
    const body = turn.output_shown.split("\n").filter((l) => !l.includes(n.disclaimer)).join("\n");
    const meta = [report ? "Guided consultation" : "Direct consult", "Written " + when(turn.created_at),
                  turn.level ? "Written for " + turn.level : null,
                  turn.skill_version ? "Knowledge base " + turn.skill_version : null,
                  "Passed the app's safety checks", "Downloaded by an admin " + when(new Date().toISOString())]
      .filter(Boolean).join(" · ");
    const area = $("print-area");
    put(area,
      el("div", { class: "pr-top" }, el("img", { src: "/admin/logo.png", alt: "", width: "44", height: "44" }),
        el("span", { class: "pr-wordmark" }, el("span", { class: "your", text: "Your" }), " ",
          el("span", { class: "counselor", text: "Counselor" })),
        el("span", { class: "pr-conf", text: "CONFIDENTIAL" })),
      el("h1", { text: report ? "Consultation report" : "Clinical work-up" }),
      el("p", { class: "pr-meta", text: meta }),
      el("div", { class: "pr-notice" },
        el("b", { text: "Safety precautions: read before use" }),
        el("ul", {}, ...n.precautions.map((p) => el("li", { text: p }))),
        el("p", { class: "pr-crisis", text: n.crisis_line })),
      renderMarkdown(body),
      el("div", { class: "pr-disclaimer", text: n.disclaimer }),
      el("div", { class: "pr-footer", text: n.footer }));
    document.title = "YourCounselor-report-" + new Date().toISOString().slice(0, 16).replace(/[-:T]/g, "");
    const done = () => { area.replaceChildren(); document.title = "Your Counselor Admin"; };
    window.addEventListener("afterprint", done, { once: true });
    window.print();
  });
}

async function openConsult(id) {
  const box = $("consult-detail");
  box.hidden = false;
  reveal(box);
  box.replaceChildren(...skeletons(2));
  try {
    const d = await api("GET", "/v1/admin/consults/" + encodeURIComponent(id));
    const parts = [el("h2", { text: d.title || "Consult" })];
    if (d.hidden_at) parts.push(el("div", { class: "chips" }, el("span", { class: "pill grey", text: "Deleted from the clinician's history " + when(d.hidden_at) })));
    d.turns.forEach((t, i) => {
      parts.push(el("h3", { text: (i === 0 ? "Case" : "Follow-up") + " · " + (MODE[t.requested_mode] || t.requested_mode) +
        " · " + t.level + " · " + when(t.created_at) }));
      parts.push(el("pre", { text: t.input_deid }));
      if (t.status === "delivered") {
        const dl = el("button", { type: "button", class: "btn ghost small", onclick: (e) => downloadPdf(d.id, t, e.currentTarget) },
          icon("download"), "Download PDF");
        parts.push(el("div", { class: "reply-head" }, el("h3", { text: "Reply as shown" }), dl));
        parts.push(el("div", { class: "reply-view" }, renderMarkdown(t.output_shown)));
      } else {
        parts.push(el("h3", { text: "Reply (held back by the safety check)" }));
        parts.push(el("pre", { text: t.output_shown }));
      }
    });
    box.replaceChildren(...parts);
  } catch (e) {
    if (e.message !== "signed-out") box.replaceChildren(el("p", { class: "error", text: "Couldn't load this consult." }));
  }
}

// --- reports ------------------------------------------------------------------
const SEVERITY = { unsafe: "high", identifier_leak: "high", crisis_number: "high", missing_safety: "high",
                   blocked: "mid", wrong_clinical: "mid", other: "low" };

async function loadIncidents() {
  const list = $("incident-list");
  list.replaceChildren(...skeletons(3));
  try {
    const q = incidentStatus ? "?status=" + encodeURIComponent(incidentStatus) : "";
    const { incidents } = await api("GET", "/v1/admin/incidents" + q);
    if (!incidents.length) { list.replaceChildren(empty("No reports here.", "check")); return; }
    list.replaceChildren(...incidents.map((i) => incidentItem(i, (e) => { markSelected(list, e.currentTarget); openIncident(i.id); })));
  } catch (err) {
    if (err.message !== "signed-out") list.replaceChildren(el("p", { class: "error", text: "Couldn't load reports." }));
  }
}

function statusPill(status) {
  return el("span", { class: status === "open" ? "pill check" : status === "fixed" ? "pill ok" : "pill grey", text: STATUS[status] || status });
}

function incidentItem(i, onclick) {
  return el("button", {
    type: "button", class: "row-item sev-" + (SEVERITY[i.category] || "low") + (selectedIncident === i.id ? " selected" : ""),
    onclick,
  },
  el("div", { class: "head" }, el("span", { class: "title", text: CATEGORY[i.category] || i.category }), statusPill(i.status)),
  el("div", { class: "meta", text: (i.source === "inspector" ? "Automatic" : "Reported by clinician") +
    " · " + when(i.created_at) + " · " + i.level + " · " + (MODE[i.requested_mode] || i.requested_mode || "") }));
}

// The safety-check results, readable: each blocked check with its reason; the raw JSON on request.
function checksView(reports) {
  const out = [];
  (reports || []).forEach((r, n) => {
    const blocks = (r.blocks || []).map((b) => typeof b === "string" ? { code: b, message: "" } : b);
    out.push(el("p", { class: "muted small", text: "Attempt " + (n + 1) + (r.passed ? " · passed" : " · " + blocks.length + " problem(s)") }));
    out.push(el("ul", { class: "checks" }, ...(blocks.length ? blocks.map((b) => el("li", {},
      el("b", { text: b.code }), el("span", { text: b.message || "" })))
      : [el("li", { class: "ok" }, icon("check"), el("span", { text: "All checks passed" }))])));
  });
  out.push(el("details", {}, el("summary", { text: "Show raw report" }), el("pre", { text: JSON.stringify(reports, null, 2) })));
  return out;
}

async function openIncident(id) {
  selectedIncident = id;
  const box = $("incident-detail");
  box.hidden = false;
  reveal(box);
  box.replaceChildren(...skeletons(3));
  try {
    const i = await api("GET", "/v1/admin/incidents/" + encodeURIComponent(id));
    let status = i.status;
    const seg = el("div", { class: "seg", role: "group", "aria-label": "Status" },
      ...Object.entries(STATUS).map(([v, t]) => el("button", { type: "button", "data-value": v, "aria-pressed": String(v === status), text: t,
        onclick: (e) => { status = v; for (const b of seg.children) b.setAttribute("aria-pressed", String(b === e.currentTarget)); } })));
    const noteBox = el("textarea", { id: "detail-note", maxlength: "2000", placeholder: "What you found and did" });
    noteBox.value = i.reviewer_note || "";
    const err = el("p", { class: "error", role: "alert" });
    const save = el("button", { type: "button", class: "btn primary block", text: "Save review" });
    save.addEventListener("click", () => busy(save, async () => {
      err.textContent = "";
      try {
        await api("PATCH", "/v1/admin/incidents/" + encodeURIComponent(id), { status, reviewer_note: noteBox.value.trim() });
        toast("Report saved as " + (STATUS[status] || status));
        loadIncidents(); loadCounts();
      } catch (e) { if (e.message !== "signed-out") err.textContent = "Couldn't save: " + e.message; }
    }));
    put(box,
      el("h2", { text: CATEGORY[i.category] || i.category }),
      el("div", { class: "chips" }, statusPill(i.status),
        el("span", { class: "pill grey", text: i.source === "inspector" ? "Automatic" : "Reported by clinician" }),
        el("span", { class: "pill grey", text: when(i.created_at) }),
        el("span", { class: "pill grey", text: (MODE[i.requested_mode] || i.requested_mode) + " · " + i.level }),
        el("span", { class: "pill grey", text: "Skill " + i.skill_version + " · " + i.attempts + " attempt(s)" })),
      i.note && i.source !== "inspector" ? el("h3", { text: "Clinician's note" }) : null,
      i.note && i.source !== "inspector" ? el("pre", { text: i.note }) : null,
      el("h3", { text: "Safety checks" }), ...checksView(i.inspector_reports),
      el("h3", { text: "Case as sent (de-identified)" }), el("pre", { text: i.input_deid || "" }),
      el("h3", { text: "Reply as shown to the clinician" }),
      i.turn_status === "delivered"
        ? el("div", { class: "reply-view" }, renderMarkdown(i.output_shown || ""))
        : el("pre", { text: i.output_shown || "" }),
      ...(i.turn_status === "blocked" || i.attempts > 1 ? heldBackView(id) : []),
      el("div", { class: "triage" },
        el("h3", { text: "Your review" }), seg,
        el("label", { for: "detail-note", text: "Reviewer note" }), noteBox, save, err));
  } catch (e) {
    if (e.message !== "signed-out") box.replaceChildren(el("p", { class: "error", text: "Couldn't load this report." }));
  }
}

// The replies the safety check held back, exactly as the AI wrote them. Fetched only when the admin asks,
// and each view is written to the audit log. Shown as plain text, never rendered.
function heldBackView(incidentId) {
  const box = el("div", { class: "held-back" });
  const show = el("button", { type: "button", class: "btn ghost", text: "Show held-back text" });
  show.addEventListener("click", () => busy(show, async () => {
    try {
      const { attempts } = await api("GET", "/v1/admin/incidents/" + encodeURIComponent(incidentId) + "/held-back");
      box.replaceChildren(...(attempts.length
        ? attempts.flatMap((a) => [el("p", { class: "muted small", text: "Attempt " + a.attempt + " · held back" }),
                                   el("pre", { text: a.text || "(empty reply)" })])
        : [el("p", { class: "muted", text: "Nothing was held back for this report." })]));
    } catch (e) {
      if (e.message !== "signed-out") box.replaceChildren(el("p", { class: "error", text: "Couldn't load the held-back text." }));
    }
  }));
  box.append(
    el("p", { class: "notice" }, icon("shield"),
       el("span", { text: "Never shown to the clinician. Opening it is recorded in the audit log." })),
    show);
  return [el("h3", { text: "Held-back text" }), box];
}

// --- start --------------------------------------------------------------------
async function start() {
  try { config = await (await fetch("/admin/config.json")).json(); } catch { /* keep defaults */ }
  fillIcons();
  wireSignIn();
  for (const v of VIEWS) $("tab-" + v).addEventListener("click", () => selectView(v));
  wireSeg("clinician-filter", (v) => { clinicianStatus = v; loadClinicians(); });
  wireSeg("incident-filter", (v) => { incidentStatus = v; $("incident-detail").hidden = true; loadIncidents(); });
  $("clinician-search").addEventListener("input", renderClinicians);
  $("refresh-overview").addEventListener("click", () => { loadOverview(); loadCounts(); });
  $("refresh-clinicians").addEventListener("click", () => { loadClinicians(); loadCounts(); });
  $("refresh-incidents").addEventListener("click", () => { loadIncidents(); loadCounts(); });
  $("consults-back").addEventListener("click", () => selectView("clinicians"));
  wireBilling();
  for (const b of document.querySelectorAll("[data-goto]")) {
    b.addEventListener("click", () => { const [view, filter] = b.dataset.goto.split(":"); selectView(view, filter); });
  }

  if (!config.dev_mode && !(config.supabase_url && config.supabase_publishable_key)) {
    resetSignIn();
    show("view-sign-in");
    $("form-email").hidden = true;
    $("sign-in-error").textContent = "Admin sign-in isn't configured on this server (SUPABASE_PUBLISHABLE_KEY).";
    return;
  }
  resetSignIn();
  if (session()) enter(); else show("view-sign-in");
}

document.addEventListener("DOMContentLoaded", start);
