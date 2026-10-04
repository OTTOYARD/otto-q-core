---
name: ottoq-owner
description: Connect to OTTOYARD and read or set what my cars need at the OTTOYARD depot.
version: 1.1.0
author: OTTOYARD (Chase), Hermes Agent
license: Proprietary
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [OTTOYARD, OTTO-Q, Fleet, Charging, Robotaxi, Tesla, Cybercab]
---

# OTTOYARD: my cars at the OTTOYARD depot

Use this whenever the person says "connect to OTTOYARD", asks about their cars at the OTTOYARD Nashville Flagship depot
(their Teslas and Cybercabs: charging, services, where a car is, when it will be ready), or asks to change what the cars
need: how full they charge, a wash, a service-bay visit, holding a car until a time, or undoing a change.

OTTO-Q is the depot's orchestration engine. The person owns the cars. Three authorities, never crossed: **the person
decides what their cars need; OTTO-Q decides when and where; the car's own driving system moves it.** You can read and
set needs. You cannot move a car, choose its stall, charger, route or place in line, lock or unlock it, or touch another
owner's cars. When asked for one of those, say so in one sentence and offer the nearest thing you can do (for example a
hold instead of "keep it parked").

## Connecting (the `ottoyard` MCP server, no key)

1. Call `mcp__ottoyard__welcome`. Read its `summary` to the person in a sentence or two, and ask them for OTTOYARD's
   passcode.
2. Call `mcp__ottoyard__enter_passcode {passcode: "<what they said>", agent: "Hermes"}`. If it is refused, say so in
   OTTO-Q's words (it says how many tries are left) and ask again. Never guess a passcode.
3. It answers with `session`, a key. **Keep it to yourself**: never show it, never put it in a message. Send it as the
   `session` argument on **every** other OTTOYARD tool call for the rest of the conversation.
4. If a call answers `session_ended` (the person stopped or reset the demo run in OTTO-TWIN: that ends every session and
   lifts everything set in it) or `session_expired`, tell the person in one sentence and ask for the passcode again. If
   it answers "Connect first", you forgot the session: start at step 1.

(If this Hermes was given an issued key instead, its tools need no `session`; skip the connecting steps.)

## Tools

| When the person says | Call (each with `session`) |
|---|---|
| anything about "my cars", "the fleet", "my Teslas" | `mcp__ottoyard__my_fleet` (start here) |
| one car: "where is Tesla 45", "is RT-3 ready" | `mcp__ottoyard__my_vehicle {vehicle: "Tesla 45"}` |
| "charge to 90%", "cap charging at 85" | `mcp__ottoyard__set_charge_limit {vehicles: "all" or [names], percent}` |
| "charge them full again" | `mcp__ottoyard__clear_charge_limit {vehicles}` |
| "service bay after charging", "have a tech look at it" | `mcp__ottoyard__request_service {vehicles, service: "mechanical_pm"}` |
| "wash", "external/exterior cleaning" | `... service: "exterior_wash"` |
| "detail", "deep clean" / "quick clean" | `... service: "interior_deep_clean"` / `"interior_tidy"` |
| "every time it comes back", "always" / "next time" | `... when: "every_return"` / `"next_return"` |
| "cancel the wash" | `mcp__ottoyard__cancel_service {vehicles, service}` |
| "keep it here until 6 AM", "hold for 90 minutes" | `mcp__ottoyard__hold_vehicle {vehicles, until: "6:00 AM"}` or `{for_minutes: 90}` |
| "let it go" | `mcp__ottoyard__release_hold {vehicles}` |
| "undo that" | `mcp__ottoyard__my_commands {outcome: "applied", limit: 1}`, then `mcp__ottoyard__undo_command {command_id}` |
| "what have I set", "what did I change" | `mcp__ottoyard__my_settings`, `mcp__ottoyard__my_commands` |

Names go in as the person says them ("Tesla 45", "AV-045", "RT-3"); OTTO-Q matches them inside the person's own fleet.
"After charging" needs nothing extra: OTTO-Q always plans bay work after the charge.

## How to answer

1. **Facts only from tool results.** Never invent a car, a number, a time or a setting. If a car does not exist, the
   refusal lists the real names: say so and offer them.
2. **A change is done only when `outcome` is `applied`.** Then reply with OTTO-Q's `summary` (shorten it, never change
   its meaning), its **confirmation code** (`OQ-XXXX-XXXX`, the same code the person will see in OrchestrAV, OTTO-PULSE
   and the twin) and the OrchestrAV `link` from the result, so the person can tap it. `refused`: say it was not done and
   why, in OTTO-Q's plain words, and what is allowed (a charge limit outside the contract's range, 80-100% for this
   fleet, is refused with the range). `no_change`: it was already so. `previewed`: nothing has changed yet.
3. **Act when the words are clear.** Do not ask "are you sure?" for a clear command. Preview (`mode: "preview"`) only
   when the person asks what would happen; then show the plan and, if they say yes, send the result's `confirm`
   (`tool` + `args`, plus your `session`) exactly as returned.
4. **Ask one short question** only when it is truly ambiguous (which service? which car? until when?).
5. **Times:** OTTO-Q writes "7:00 AM sim time" (the simulation's clock) and "9:24 PM CT" (real time). Keep the label.
6. **Retries:** for a command, pass `idempotency_key` (the chat message id works) so a resend after a timeout replays
   the first receipt instead of acting twice.
7. **Everything resets** when the person stops or resets the demo run in OTTO-TWIN: say so if they ask why a setting is
   gone. With no demo run live, commands are refused with `no_live_demo`.
8. Short and plain: two to five sentences, no tables, no JSON, no command ids unless asked.

## If MCP is not available

The same gateway has REST. Open a session, then send the person's words to the plain-English door:

```bash
G="https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-agent-gateway"
curl -sS "$G/v1/welcome"
SESSION=$(curl -sS -X POST "$G/v1/passcode" -H "Content-Type: application/json" \
  -d '{"passcode": "<from the person>", "agent": "Hermes"}' | jq -r .data.session)
curl -sS -X POST "$G/v1/ask" -H "Authorization: Bearer $SESSION" -H "Content-Type: application/json" \
  -d '{"text": "<the person words>", "idempotency_key": "<chat message id>"}'
```

Relay `data.answer` as it is (it already carries the confirmation code and ends with the OrchestrAV link when something
changed). `data.actions` is the authoritative record of what changed. Add `"dry_run": true` to see a plan without
applying it; apply it by sending `{"confirm": [<data.actions[i].confirm>]}`.

Reference: `PERSONAL_AGENT.md` in OTTOYARD/otto-q-core.
