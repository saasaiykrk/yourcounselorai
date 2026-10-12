// Public booking page: /book/<link name> to book, /book/manage/<token> to see or cancel.
// No third-party code, no cookies, no storage. Everything shown is set with textContent.
"use strict";
(function () {
  const $ = (id) => document.getElementById(id);
  const PAGE_DAYS = 14;
  const parts = location.pathname.split("/").filter(Boolean);           // ["book", slug] or ["book", "manage", token]
  const browserTz = Intl.DateTimeFormat().resolvedOptions().timeZone;

  function show(id) {
    for (const s of ["loading", "missing", "book", "done", "manage"]) $(s).hidden = s !== id;
  }

  async function api(path, opts) {
    const r = await fetch(path, { headers: { "Content-Type": "application/json" }, cache: "no-store", ...opts });
    let body = null;
    try { body = await r.json(); } catch (e) { /* not JSON */ }
    if (!r.ok) {
      const d = body && body.detail;
      const err = new Error((d && d.message) || (typeof d === "string" ? d : "Something went wrong. Please try again."));
      err.status = r.status; err.code = d && d.error;
      throw err;
    }
    return body;
  }

  // --- dates in a timezone ---------------------------------------------------------------------
  function isoDay(date, tz) {                      // the calendar date of an instant in tz, "YYYY-MM-DD"
    const p = Object.fromEntries(new Intl.DateTimeFormat("en-CA", { timeZone: tz, year: "numeric", month: "2-digit",
      day: "2-digit" }).formatToParts(date).map((x) => [x.type, x.value]));
    return `${p.year}-${p.month}-${p.day}`;
  }
  function addDays(iso, n) {
    const [y, m, d] = iso.split("-").map(Number);
    return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
  }
  function dayLabel(iso) {                         // the date itself, whatever the timezone
    const [y, m, d] = iso.split("-").map(Number);
    const dt = new Date(Date.UTC(y, m - 1, d, 12));
    const f = (o) => new Intl.DateTimeFormat(undefined, { timeZone: "UTC", ...o }).format(dt);
    return { dow: f({ weekday: "short" }), dom: f({ day: "numeric" }), mon: f({ month: "short" }),
             long: f({ weekday: "long", day: "numeric", month: "long" }) };
  }
  const time = (iso, tz) => new Intl.DateTimeFormat(undefined, { timeZone: tz, hour: "numeric", minute: "2-digit" }).format(new Date(iso));
  const when = (iso, tz) => new Intl.DateTimeFormat(undefined, { timeZone: tz, weekday: "long", day: "numeric", month: "long",
    year: "numeric", hour: "numeric", minute: "2-digit" }).format(new Date(iso));
  const tzName = (tz) => tz.replace(/_/g, " ");

  // --- booking ---------------------------------------------------------------------------------
  const state = { slug: "", profile: null, today: "", first: "", last: "", days: {}, day: "", slot: "" };

  async function startBooking(slug) {
    state.slug = slug;
    try {
      state.profile = await api(`/v1/public/booking/${encodeURIComponent(slug)}`);
    } catch (e) {
      show("missing");
      if (e.status !== 404) $("missing-text").textContent = e.message;
      return;
    }
    const p = state.profile;
    document.title = `Book with ${p.display_name} · YourCounselor`;
    $("name").textContent = p.display_name;
    $("avatar").textContent = (p.display_name.replace(/^(dr|mr|mrs|ms|prof)\.?\s+/i, "")[0] || "?").toUpperCase();
    $("role").textContent = p.role;
    $("bio").textContent = p.bio || "";
    $("bio").hidden = !p.bio;
    $("length").textContent = `${p.slot_minutes}-minute appointment`;
    $("tz").textContent = `Times in ${tzName(p.timezone)}`;
    $("tz-note").textContent = browserTz && browserTz !== p.timezone
      ? `Times are shown in ${tzName(p.timezone)}, the consultant's timezone. Your time is shown underneath.` : "";
    state.today = isoDay(new Date(), p.timezone);
    state.last = addDays(state.today, p.max_advance_days);
    show("book");
    await loadDays(state.today);
  }

  async function loadDays(first) {
    state.first = first;
    $("prev").disabled = first <= state.today;
    $("next").disabled = addDays(first, PAGE_DAYS) > state.last;
    $("dates").replaceChildren();
    $("slots").replaceChildren();
    $("no-slots").hidden = $("no-dates").hidden = true;
    let data;
    try {
      data = await api(`/v1/public/booking/${encodeURIComponent(state.slug)}/slots?start=${first}&days=${PAGE_DAYS}`);
    } catch (e) {
      $("no-dates").textContent = e.message; $("no-dates").hidden = false;
      return;
    }
    state.days = Object.fromEntries(data.days.map((d) => [d.date, d.slots]));
    let pick = "";
    for (let i = 0; i < PAGE_DAYS; i++) {
      const iso = addDays(first, i);
      if (iso > state.last) break;
      const l = dayLabel(iso), has = (state.days[iso] || []).length > 0;
      const b = document.createElement("button");
      b.type = "button"; b.className = "date"; b.setAttribute("role", "option"); b.dataset.day = iso;
      b.disabled = !has; b.setAttribute("aria-label", `${l.long}${has ? "" : ", no free times"}`);
      for (const [cls, txt] of [["dow", l.dow], ["dom", l.dom], ["mon", l.mon]]) {
        const s = document.createElement("span"); s.className = cls; s.textContent = txt; b.append(s);
      }
      b.addEventListener("click", () => pickDay(iso));
      $("dates").append(b);
      if (has && !pick) pick = iso;
    }
    if (pick) pickDay(state.day && state.days[state.day] && state.days[state.day].length ? state.day : pick);
    else $("no-dates").hidden = false;
  }

  function pickDay(iso) {
    state.day = iso;
    for (const b of $("dates").children) b.setAttribute("aria-selected", String(b.dataset.day === iso));
    const tz = state.profile.timezone, slots = state.days[iso] || [];
    $("slots").replaceChildren();
    $("no-slots").hidden = slots.length > 0;
    for (const s of slots) {
      const b = document.createElement("button");
      b.type = "button"; b.className = "slot"; b.setAttribute("role", "option"); b.dataset.slot = s;
      b.textContent = time(s, tz);
      if (browserTz && browserTz !== tz) {
        const y = document.createElement("small");
        y.textContent = `${time(s, browserTz)} yours`;
        b.append(y);
      }
      b.addEventListener("click", () => pickSlot(s));
      $("slots").append(b);
    }
  }

  function pickSlot(s) {
    state.slot = s;
    for (const b of $("slots").children) b.setAttribute("aria-selected", String(b.dataset.slot === s));
    const tz = state.profile.timezone;
    $("chosen").textContent = `${when(s, tz)} (${tzName(tz)})`;
    $("form-error").textContent = "";
    $("step-details").hidden = false;
    $("step-time").hidden = true;
    $("first_name").focus();
  }

  function backToTimes() {
    $("step-details").hidden = true;
    $("step-time").hidden = false;
  }

  async function submit(ev) {
    ev.preventDefault();
    const first = $("first_name").value.trim(), email = $("email").value.trim();
    const err = (m) => { $("form-error").textContent = m; };
    if (!first) return err("Please enter your first name.");
    if (!/^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$/.test(email)) return err("Please enter a valid email address.");
    if (!$("consent").checked) return err("Please tick the box to agree to share your details.");
    $("submit").disabled = true; $("submit").textContent = "Booking…";
    try {
      const r = await api(`/v1/public/booking/${encodeURIComponent(state.slug)}`, { method: "POST", body: JSON.stringify({
        starts_at: state.slot, first_name: first, email, consent: true, website: $("website").value }) });
      done(r);
    } catch (e) {
      err(e.message);
      if (e.code === "slot_taken") {                 // someone else got it first: show fresh times
        backToTimes();
        await loadDays(state.first);
        $("no-slots").hidden = false;
        $("no-slots").textContent = e.message;
      }
    } finally {
      $("submit").disabled = false; $("submit").textContent = "Book appointment";
    }
  }

  function done(r) {
    const pending = r.status === "pending";
    $("done-badge").textContent = pending ? "…" : "✓";
    $("done-badge").className = "badge" + (pending ? " pending" : "");
    $("done-title").textContent = pending ? "Request sent" : "You're booked";
    $("done-when").textContent = `${when(r.starts_at, r.timezone)} (${tzName(r.timezone)})`;
    $("done-text").textContent = (pending
      ? `${r.display_name} will confirm your request. Until then this time is held for you.`
      : `Your appointment with ${r.display_name} is confirmed.`)
      + (r.email_sent ? " We've sent the details to your email."
        : " Please save the link below: it's how you can see or cancel this appointment.");
    $("manage-link").value = `${location.origin}/book/manage/${r.manage_token}`;
    show("done");
    window.scrollTo(0, 0);
  }

  async function copyLink() {
    const v = $("manage-link").value;
    try { await navigator.clipboard.writeText(v); } catch (e) { $("manage-link").select(); document.execCommand("copy"); }
    $("copy").textContent = "Copied";
    setTimeout(() => { $("copy").textContent = "Copy"; }, 1600);
  }

  // --- manage ----------------------------------------------------------------------------------
  const STATUS = { pending: "Waiting for confirmation", confirmed: "Confirmed", completed: "Completed",
    cancelled: "Cancelled", rejected: "Declined", expired: "Request expired", rescheduled: "Moved" };

  async function startManage(token) {
    let a;
    try {
      a = await api(`/v1/public/booking/manage/${encodeURIComponent(token)}`);
    } catch (e) {
      $("missing-text").textContent = e.status === 404 ? "This link is no longer valid." : e.message;
      return show("missing");
    }
    $("m-status").textContent = STATUS[a.status] || a.status;
    $("m-status").className = "pill " + a.status;
    $("m-when").textContent = `${when(a.starts_at, a.timezone)} (${tzName(a.timezone)})`;
    $("m-with").textContent = `with ${a.display_name}`;
    $("m-cancel").hidden = !a.can_cancel;
    $("m-confirm").hidden = true;
    $("m-rebook").hidden = !(a.slug && !a.can_cancel);
    if (a.slug) $("m-rebook").href = `/book/${a.slug}`;
    show("manage");
    $("m-cancel").onclick = () => { $("m-cancel").hidden = true; $("m-confirm").hidden = false; };
    $("m-keep").onclick = () => { $("m-cancel").hidden = false; $("m-confirm").hidden = true; };
    $("m-yes").onclick = async () => {
      $("m-yes").disabled = true;
      try {
        await api(`/v1/public/booking/manage/${encodeURIComponent(token)}/cancel`, { method: "POST" });
        await startManage(token);
      } catch (e) {
        $("m-error").textContent = e.message;
      } finally {
        $("m-yes").disabled = false;
      }
    };
  }

  document.addEventListener("DOMContentLoaded", () => {
    $("prev").addEventListener("click", () => loadDays(addDays(state.first, -PAGE_DAYS) < state.today ? state.today : addDays(state.first, -PAGE_DAYS)));
    $("next").addEventListener("click", () => loadDays(addDays(state.first, PAGE_DAYS)));
    $("back").addEventListener("click", backToTimes);
    $("step-details").addEventListener("submit", submit);
    $("copy").addEventListener("click", copyLink);
    if (parts[0] === "book" && parts[1] === "manage" && parts[2]) startManage(parts[2]);
    else if (parts[0] === "book" && parts[1]) startBooking(parts[1]);
    else show("missing");
  });
})();
