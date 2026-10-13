// Your Counselor web admin: AI Model (which approved model writes replies, and provider API keys).
// Uses admin.js and billing.js helpers (el, put, api, icon, empty, skeletons, toast, busy, when,
// field, formDialog). Keys are sent once to the server, which checks and encrypts them; the page
// only ever shows the last 4 characters.
"use strict";

const PROVIDER = { anthropic: "Anthropic (Claude)", gemini: "Google (Gemini)" };
const KEY_SOURCE = { admin: ["Added here", "ok"], server: ["Server key", "grey"], none: ["No key", "check"] };
const AI_ACTION = { ai_model: "Model switched", ai_key_set: "Key added or replaced", ai_key_removed: "Key removed" };

let aiState = null;

async function loadAi() {
  const box = $("ai-body");
  box.replaceChildren(...skeletons(3));
  try {
    aiState = await api("GET", "/v1/admin/ai");
    renderAi();
  } catch (err) {
    if (err.message !== "signed-out") box.replaceChildren(el("p", { class: "error", text: "Couldn't load AI settings: " + err.message }));
  }
}

function renderAi() {
  const s = aiState;
  const activeModel = s.models.find((m) => m.active) || { label: s.active_model };

  const current = el("section", { class: "panel" },
    el("div", { class: "panel-head" }, el("h2", { text: "Model in use" }),
      el("span", { class: "pill ok", text: activeModel.label })),
    el("p", { class: "muted small", text: s.changed_at
      ? "Changed " + when(s.changed_at) + (s.changed_by ? " by " + s.changed_by : "") + "."
      : "The server's default model. Nobody has switched it yet." }),
    el("p", { class: "note-line", text: "Every reply, whichever model writes it, still passes the identifier cleaner and the "
      + "safety inspector. Only models on the approved list (checked against the clinical tests and signed off) can be chosen." }));

  const models = el("section", { class: "panel" },
    el("div", { class: "panel-head" }, el("h2", { text: "Approved models" })),
    el("div", { class: "ai-models" }, ...s.models.map(modelRow)));

  const keys = el("section", { class: "panel" },
    el("div", { class: "panel-head" }, el("h2", { text: "API keys" })),
    s.can_store_keys ? null : el("p", { class: "error",
      text: "Keys can't be saved until BYOK_ENCRYPTION_KEY is set on the server." }),
    el("div", { class: "ai-keys" }, ...Object.keys(PROVIDER).map((p) => keyRow(p, s.keys[p] || { source: "none" }))),
    el("p", { class: "muted small", text: "A key added here is checked with the provider, stored encrypted and used instead of "
      + "the server's key. It is never shown again. Removing it goes back to the server's key, if there is one." }));

  const hist = el("section", { class: "panel" }, el("div", { class: "panel-head" }, el("h2", { text: "Change history" })),
    s.history.length ? el("ul", { class: "history" }, ...s.history.map((h) => el("li", {},
      el("div", { class: "meta", text: when(h.at) + " · " + (h.by || "admin") }),
      el("div", { text: describeAi(h) })))) : empty("No changes yet."));

  put($("ai-body"), current, models, keys, hist);
}

function describeAi(h) {
  const d = h.detail || {};
  if (h.action === "ai_model") return `${AI_ACTION.ai_model}: ${labelOf(d.from)} → ${labelOf(d.to)}`;
  return `${AI_ACTION[h.action] || h.action}: ${PROVIDER[d.provider] || d.provider}${d.last4 ? " (…" + d.last4 + ")" : ""}`;
}

function labelOf(id) {
  const m = (aiState?.models || []).find((x) => x.id === id);
  return m ? m.label : (id || "—");
}

function modelRow(m) {
  const btn = m.active
    ? el("span", { class: "pill ok", text: "In use" })
    : el("button", { type: "button", class: "btn ghost small", text: "Switch to this",
        ...(m.key_ready ? {} : { disabled: "", title: "Add a " + PROVIDER[m.provider] + " key first" }),
        onclick: () => switchModel(m) });
  return el("div", { class: "ai-row" + (m.active ? " active" : "") },
    el("div", {}, el("b", { text: m.label }), el("span", { class: "muted small", text: " · " + PROVIDER[m.provider] }),
      el("div", { class: "muted small", text: m.note }),
      m.key_ready ? null : el("div", { class: "small error", text: "No API key for this provider yet." })),
    btn);
}

function switchModel(m) {
  const confirm = el("input", { autocomplete: "off", spellcheck: "false", placeholder: m.id });
  formDialog({
    title: "Switch to " + m.label + "?",
    ok: "Switch model",
    danger: true,
    body: [
      el("p", { text: "From now on, new replies and reports are written by " + m.label + ". Replies being written now finish "
        + "with the current model. Every server picks up the change within 30 seconds." }),
      el("p", { class: "note-line", text: "Case text (identifiers removed) will be sent to " + PROVIDER[m.provider]
        + ". Make sure the privacy policy names this provider." }),
      field("Type " + m.id + " to confirm", confirm),
    ],
    onSubmit: async () => {
      if (confirm.value.trim() !== m.id) throw new Error("Type " + m.id + " exactly to confirm.");
      await api("PUT", "/v1/admin/ai/model", { model: m.id, confirm: confirm.value.trim() });
      toast("Switched to " + m.label);
      await loadAi();
    },
  });
}

function keyRow(provider, k) {
  const [text, cls] = KEY_SOURCE[k.source] || KEY_SOURCE.none;
  const detail = k.source === "admin"
    ? "Ends in …" + k.last4 + (k.updated_at ? " · added " + when(k.updated_at) : "") + (k.updated_by ? " by " + k.updated_by : "")
    : k.source === "server" ? "Ends in …" + k.last4 + " · set on the server (Secret Manager)" : "Not set";
  return el("div", { class: "ai-row" },
    el("div", {}, el("b", { text: PROVIDER[provider] }), " ", el("span", { class: "pill " + cls, text }),
      el("div", { class: "muted small", text: detail })),
    el("div", { class: "actions" },
      el("button", { type: "button", class: "btn ghost small", text: k.source === "admin" ? "Replace key" : "Add key",
        ...(aiState.can_store_keys ? {} : { disabled: "" }), onclick: () => addKey(provider) }),
      k.source === "admin" ? el("button", { type: "button", class: "btn danger small", text: "Remove",
        onclick: () => removeKey(provider) }) : null));
}

function addKey(provider) {
  const input = el("input", { type: "password", autocomplete: "off", spellcheck: "false",
    placeholder: provider === "anthropic" ? "sk-ant-…" : "AIza…" });
  formDialog({
    title: "API key: " + PROVIDER[provider],
    ok: "Check and save",
    body: [
      field("Paste the key", input, provider === "anthropic"
        ? "From console.anthropic.com → API keys." : "From aistudio.google.com → Get API key."),
      el("p", { class: "muted small", text: "The key is checked with the provider before it is saved (no cost), then stored "
        + "encrypted. It will not be shown again." }),
    ],
    onSubmit: async () => {
      const key = input.value.trim();
      input.value = "";
      if (!key) throw new Error("Paste the key first.");
      await api("PUT", "/v1/admin/ai/keys/" + provider, { api_key: key });
      toast("Key saved for " + PROVIDER[provider]);
      await loadAi();
    },
  });
  setTimeout(() => input.focus(), 50);
}

function removeKey(provider) {
  formDialog({
    title: "Remove the " + PROVIDER[provider] + " key?",
    ok: "Remove key",
    danger: true,
    body: [el("p", { text: "The key added here is deleted. The server's own key is used again, if there is one." })],
    onSubmit: async () => {
      await api("DELETE", "/v1/admin/ai/keys/" + provider);
      toast("Key removed");
      await loadAi();
    },
  });
}

function wireAi() {
  $("refresh-ai").addEventListener("click", loadAi);
}
