# Crisis resources register — India
**Single source of truth.** Every other file points here instead of carrying its own list.

| Field | Value |
|---|---|
| Owner | **Clinical Safety Officer, Fabeminds Counselling Services** — *name to be assigned* |
| Deputy (covers leave / urgent change) | *to be assigned* |
| Last desk check | 2026-09-24 — secondary public sources (news, university and government-portal mirrors); **no live call test yet** |
| Next scheduled review | **2027-09-24** (annual), or sooner on any trigger below |
| Review cadence | Annual full review + event-triggered checks |

## Current entries
| Service | Number(s) | Scope | Status at last check | Notes |
|---|---|---|---|---|
| Emergency Response Support System (ERSS) | **112** | Police, fire, ambulance; all emergencies | Active | Also receives integrated child and women helpline routing in many states |
| Tele-MANAS (MoHFW national tele-mental-health) | **14416** · **1-800-891-4416** | 24×7, free, ~20 languages, routes to state cell | Active | Use as the primary mental-health crisis line |
| Child Helpline | **1098** | Children in distress; adults calling on a child's behalf | Active; integrated with ERSS-112 in states | Now run under Mission Vatsalya (WCD), not the former NGO "CHILDLINE" — use the name **Child Helpline 1098** |
| Women Helpline | **181** | Women affected by violence; links to One Stop Centres | Active; integrated with ERSS-112 in states | — |
| ~~KIRAN 1800-599-0019~~ | — | — | **Do not list** | Merged into Tele-MANAS (announced Feb 2024) and slated for phase-out; route to Tele-MANAS instead |

## Output rule for the skill
Give the numbers above as written. Add "(numbers verified to [last check date]; confirm local pathway)" only in documents that leave the chat (reports, handouts, app screens). Never add a number that is not in this register.

## Annual review procedure (owner)
1. Check each service on its official government portal (e.g., the Tele-MANAS portal under MoHFW; MoWCD / Mission Vatsalya; ERSS-112).
2. Place a **live test call** to each number from a mobile and a landline; record date, time, outcome.
3. Update the table, "Last desk check" (rename to "Last verified" once a live call is done) and "Next scheduled review".
4. Record the change in `CHANGELOG.md` and bump the skill's patch version.
5. Sign off: name, role, date.

## Event triggers (review within 7 days)
Government announcement of a merger, renumbering or discontinuation · a user or clinician reports a number not working · state-level change affecting Maharashtra (primary service region) · any release that adds a new helpline.

## Review log
| Date | Reviewer | Method | Changes |
|---|---|---|---|
| 2026-09-24 | Assistant (draft) | Desk check, secondary sources | CHILDLINE renamed Child Helpline 1098; KIRAN removed (merged into Tele-MANAS); register created |
