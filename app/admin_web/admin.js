// Your Counselor web admin. Talks only to this backend (/v1/admin/*) and to
// Supabase Auth for the email code. No third-party scripts. All data is shown
// with textContent, never as HTML. The session lives in sessionStorage (gone
// when the tab closes) and ends after 15 minutes without activity.
"use strict";

const IDLE_LIMIT_MS = 15 * 60 * 1000;
const KEY = "yc_admin_session";
const $ = (id) => document.getElementById(id);

let config = { supabase_url: "", supabase_publishable_key: "", dev_mode: false };
let pendingEmail = "";
let idleTimer = null;
let selectedIncident = null;

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
  resetSignIn();
  $("sign-in-error").textContent = message || "";
  show("view-sign-in");
}

function touch() {
  clearTimeout(idleTimer);
  idleTimer = setTimeout(() => signOut("Signed out after 15 minutes without activity."), IDLE_LIMIT_MS);
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
    const detail = typeof data.detail === "string" ? data.detail : "request failed";
    const err = new Error(detail); err.status = r.status; throw err;
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
    $("who-email").textContent = session().email || "";
    show("view-admin");
    touch();
    selectTab("clinicians");
    loadCounts();
  } catch (err) {
    if (err.message !== "signed-out") $("sign-in-error").textContent = "Couldn't reach the backend. Try again.";
  }
}

// --- tabs -------------------------------------------------------------------
function selectTab(name) {
  showConsults(false);
  $("consult-list").replaceChildren();
  $("consult-detail").replaceChildren();
  for (const t of ["clinicians", "incidents"]) {
    $("tab-" + t).setAttribute("aria-selected", String(t === name));
    $("panel-" + t).hidden = t !== name;
  }
  if (name === "clinicians") loadClinicians(); else loadIncidents();
}

async function loadCounts() {
  try {
    const [c, i] = await Promise.all([api("GET", "/v1/admin/clinicians?status=pending"),
                                      api("GET", "/v1/admin/incidents?status=open")]);
    $("count-pending").textContent = c.clinicians.length || "";
    $("count-open").textContent = i.incidents.length || "";
  } catch { /* counts are optional */ }
}

// --- registrations ------------------------------------------------------------
async function loadClinicians() {
  const list = $("clinician-list");
  const status = $("clinician-status").value;
  list.replaceChildren(el("p", { class: "muted", text: "Loading…" }));
  try {
    const { clinicians } = await api("GET", "/v1/admin/clinicians?status=" + encodeURIComponent(status));
    if (!clinicians.length) {
      list.replaceChildren(el("div", { class: "empty", text: status === "pending" ? "Nobody is waiting for approval." : "None." }));
      return;
    }
    list.replaceChildren(...clinicians.map((c) => clinicianItem(c, status)));
  } catch (err) {
    if (err.message !== "signed-out") list.replaceChildren(el("p", { class: "error", text: "Couldn't load registrations." }));
  }
}

function clinicianItem(c, status) {
  const reg = c.registration_body && c.registration_body !== "none"
    ? c.registration_body + " " + (c.registration_number || "(no number)") : "No registration given";
  const pill = c.verification_status === "verified" ? el("span", { class: "pill", text: "Verified · " + c.level })
    : c.verification_status === "rejected" ? el("span", { class: "pill crisis", text: "Rejected" })
    : el("span", { class: "pill check", text: "Waiting" });
  const item = el("div", { class: "item" },
    el("div", { class: "head" }, el("span", { class: "title", text: c.email || c.id }), pill),
    el("div", { class: "meta", text: (ROLE[c.role] || c.role) + " · " + reg }),
    el("div", { class: "meta", text: "Registered " + when(c.created_at) +
      (c.verification_note ? " · Note: " + c.verification_note : "") }));
  if (status === "verified") {
    item.append(el("div", { class: "actions" },
      el("button", { type: "button", class: "link", text: "Consults ›", onclick: () => openConsults(c) })));
  }
  if (status === "pending") {
    item.append(el("div", { class: "actions" },
      el("button", { type: "button", class: "ok", text: "Approve…", onclick: () => decide(c, "verified") }),
      el("button", { type: "button", class: "danger", text: "Reject…", onclick: () => decide(c, "rejected") })));
  }
  return item;
}

function decide(c, decision) {
  const dlg = $("decide");
  $("decide-title").textContent = decision === "verified" ? "Approve registration" : "Reject registration";
  $("decide-who").textContent = (c.email || "") + " · " + (ROLE[c.role] || c.role);
  $("decide-level-row").hidden = decision !== "verified";
  $("decide-level").value = c.role === "counsellor_trainee" ? "L1" : c.role === "psychiatrist" ? "L3" : "L2";
  $("decide-note").value = "";
  $("decide-error").textContent = "";
  $("decide-ok").textContent = decision === "verified" ? "Approve" : "Reject";
  $("decide-ok").className = decision === "verified" ? "primary" : "primary danger";

  $("decide-cancel").onclick = () => dlg.close();
  $("decide-form").onsubmit = (e) => {
    e.preventDefault();
    const note = $("decide-note").value.trim();
    if (note.length < 3) { $("decide-error").textContent = "Say how you checked the registration."; return; }
    busy($("decide-ok"), async () => {
      try {
        await api("PATCH", "/v1/admin/clinicians/" + encodeURIComponent(c.id), {
          verification_status: decision,
          level: decision === "verified" ? $("decide-level").value : null,
          evidence_note: note,
        });
        dlg.close();
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
               F: "Notes", G: "Audit only", auto: "Auto" };

function showConsults(on) {
  $("panel-clinicians").hidden = on;
  $("panel-consults").hidden = !on;
}

async function openConsults(c) {
  showConsults(true);
  $("consults-who").textContent = c.email || c.id;
  const list = $("consult-list");
  $("consult-detail").hidden = true;
  list.replaceChildren(el("p", { class: "muted", text: "Loading…" }));
  try {
    const { consults } = await api("GET", "/v1/admin/clinicians/" + encodeURIComponent(c.id) + "/consults");
    if (!consults.length) { list.replaceChildren(el("div", { class: "empty", text: "No consults yet." })); return; }
    list.replaceChildren(...consults.map((x) => el("button", {
      type: "button", class: "item clickable", onclick: () => openConsult(x.id),
    },
    el("div", { class: "head" }, el("span", { class: "title", text: x.title || x.preview }),
      x.hidden_at ? el("span", { class: "pill", text: "Deleted by clinician" })
        : x.last_status === "blocked" ? el("span", { class: "pill check", text: "Held back" }) : null),
    el("div", { class: "meta", text: when(x.last_at || x.created_at) + " · " +
      (x.modes || []).map((m) => MODE[m] || m).join(", ") + (x.turns > 1 ? " · " + x.turns + " messages" : "") }))));
  } catch (err) {
    if (err.message !== "signed-out") list.replaceChildren(el("p", { class: "error", text: "Couldn't load consults." }));
  }
}

async function openConsult(id) {
  const box = $("consult-detail");
  box.hidden = false;
  box.replaceChildren(el("p", { class: "muted", text: "Loading…" }));
  try {
    const d = await api("GET", "/v1/admin/consults/" + encodeURIComponent(id));
    const parts = [el("h2", { text: d.title || "Consult" })];
    if (d.hidden_at) parts.push(el("p", { class: "muted small", text: "Deleted from the clinician's history " + when(d.hidden_at) }));
    d.turns.forEach((t, i) => {
      parts.push(el("h3", { text: (i === 0 ? "Case" : "Follow-up") + " · " + (MODE[t.requested_mode] || t.requested_mode) +
        " · " + t.level + " · " + when(t.created_at) }));
      parts.push(el("pre", { text: t.input_deid }));
      parts.push(el("h3", { text: t.status === "delivered" ? "Reply as shown" : "Reply (held back by the safety check)" }));
      parts.push(el("pre", { text: t.output_shown }));
    });
    box.replaceChildren(...parts);
  } catch (e) {
    if (e.message !== "signed-out") box.replaceChildren(el("p", { class: "error", text: "Couldn't load this consult." }));
  }
}

// --- reports ------------------------------------------------------------------
async function loadIncidents() {
  const list = $("incident-list");
  const status = $("incident-status").value;
  list.replaceChildren(el("p", { class: "muted", text: "Loading…" }));
  try {
    const q = status ? "?status=" + encodeURIComponent(status) : "";
    const { incidents } = await api("GET", "/v1/admin/incidents" + q);
    if (!incidents.length) { list.replaceChildren(el("div", { class: "empty", text: "No reports here." })); return; }
    list.replaceChildren(...incidents.map(incidentItem));
  } catch (err) {
    if (err.message !== "signed-out") list.replaceChildren(el("p", { class: "error", text: "Couldn't load reports." }));
  }
}

function incidentItem(i) {
  const pillClass = i.status === "open" ? "pill check" : "pill";
  return el("button", {
    type: "button", class: "item clickable" + (selectedIncident === i.id ? " selected" : ""),
    onclick: () => openIncident(i.id),
  },
  el("div", { class: "head" }, el("span", { class: "title", text: CATEGORY[i.category] || i.category }),
    el("span", { class: pillClass, text: STATUS[i.status] || i.status })),
  el("div", { class: "meta", text: (i.source === "inspector" ? "Automatic" : "Reported by clinician") +
    " · " + when(i.created_at) + " · " + i.level + " · reply " + i.turn_status }));
}

async function openIncident(id) {
  selectedIncident = id;
  const box = $("incident-detail");
  box.hidden = false;
  box.replaceChildren(el("p", { class: "muted", text: "Loading…" }));
  for (const b of $("incident-list").children) b.classList?.remove("selected");
  try {
    const i = await api("GET", "/v1/admin/incidents/" + encodeURIComponent(id));
    const statusSel = el("select", { id: "detail-status" },
      ...Object.entries(STATUS).map(([v, t]) => { const o = el("option", { value: v, text: t }); o.selected = v === i.status; return o; }));
    const noteBox = el("textarea", { id: "detail-note", maxlength: "2000", placeholder: "What you found and did" });
    noteBox.value = i.reviewer_note || "";
    const err = el("p", { class: "error", role: "alert" });
    const save = el("button", { type: "button", class: "primary", text: "Save" });
    save.addEventListener("click", () => busy(save, async () => {
      err.className = "error";
      err.textContent = "";
      try {
        await api("PATCH", "/v1/admin/incidents/" + encodeURIComponent(id),
                  { status: statusSel.value, reviewer_note: noteBox.value.trim() });
        loadIncidents(); loadCounts();
        err.className = "saved";
        err.textContent = "Saved.";
      } catch (e) { if (e.message !== "signed-out") err.textContent = "Couldn't save: " + e.message; }
    }));
    box.replaceChildren(
      el("h2", { text: CATEGORY[i.category] || i.category }),
      el("p", { class: "muted small", text: (i.source === "inspector" ? "Automatic" : "Reported by clinician") +
        " · " + when(i.created_at) + " · mode " + i.requested_mode + " · " + i.level + " · skill " + i.skill_version +
        " · " + i.attempts + " attempt(s)" }),
      i.note ? el("h3", { text: "Report note" }) : null, i.note ? el("pre", { text: i.note }) : null,
      el("h3", { text: "Case as sent (de-identified)" }), el("pre", { text: i.input_deid || "" }),
      el("h3", { text: "Reply as shown to the clinician" }), el("pre", { text: i.output_shown || "" }),
      el("h3", { text: "Safety-check reports" }), el("pre", { text: JSON.stringify(i.inspector_reports, null, 2) }),
      el("label", { for: "detail-status", text: "Status" }), statusSel,
      el("label", { for: "detail-note", text: "Reviewer note" }), noteBox,
      save, err);
  } catch (e) {
    if (e.message !== "signed-out") box.replaceChildren(el("p", { class: "error", text: "Couldn't load this report." }));
  }
}

// --- start --------------------------------------------------------------------
async function start() {
  try { config = await (await fetch("/admin/config.json")).json(); } catch { /* keep defaults */ }
  wireSignIn();
  $("tab-clinicians").addEventListener("click", () => selectTab("clinicians"));
  $("tab-incidents").addEventListener("click", () => selectTab("incidents"));
  $("clinician-status").addEventListener("change", loadClinicians);
  $("incident-status").addEventListener("change", loadIncidents);
  $("refresh-clinicians").addEventListener("click", () => { loadClinicians(); loadCounts(); });
  $("consults-back").addEventListener("click", () => selectTab("clinicians"));
  $("refresh-incidents").addEventListener("click", () => { loadIncidents(); loadCounts(); });
  for (const evt of ["click", "keydown"]) document.addEventListener(evt, () => { if (session()) touch(); });

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
