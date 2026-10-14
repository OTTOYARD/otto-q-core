---
name: ottoq-owner
description: Connect to OTTOYARD and read or set what my cars need at the OTTOYARD depot.
version: 1.3.0
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

## Connecting

**Signed in (the `ottoyard` server has `auth: oauth`, PERSONAL_AGENT.md section 10).** This Hermes is connected to its
person's OTTOYARD account and holds its own tokens: call the tools with no `session` argument, and skip the passcode
steps below. To sign in (the first time, or after the person disconnected you, or after 30 days unused):

1. Run `hermes mcp login ottoyard --flow device` with your terminal tool **in the background**, watching its output.
2. When it prints `open https://www.ottoyard.com/connect` and `Code: XXXX-XXXX`, send both to the person in one short
   message: "Open www.ottoyard.com/connect, sign in, enter XXXX-XXXX and approve." Never ask for their password: they
   type it on OTTOYARD's page, never to you.
3. Wait for the command to print `Authenticated`, tell the person, and run `/reload-mcp` (or ask them to send it).
4. If a tool call fails because the sign-in was rejected, the person disconnected you or it lapsed: say so in one
   sentence and offer to sign in again.

**With the passcode instead (the `ottoyard` server has no `auth`, the passcode door).**

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

## Every request goes to OTTO-Command first

OTTO-Command is OTTOYARD's own agent: the filter and executor between you and OTTO-Q. **Send every request about the
cars to it first**, in the person's own words, and forward its answer:

```
mcp__ottoyard__ask_ottocommand {text: "<what the person said, as they said it>"}
```

(With the passcode, add `session` as on every other tool.) It reads the cars, answers questions (where a car is, when it
will be ready, what OTTO-Q decided, which chargers are free), and makes the changes the person asks for, with YOUR token,
so it can do nothing your token could not. What comes back:

- `answer`: plain English, ready to forward as it is. When something changed it already carries the confirmation code
  (`OQ-XXXX-XXXX`) and ends with the OrchestrAV link.
- `actions`: OTTO-Q's receipt for each change, the authoritative record. A change is done only when its `outcome` is
  `applied`.
- `confirm` (only when a change was previewed, not applied): ask the person "Shall I go ahead?". If they say yes, call
  `mcp__ottoyard__ask_ottocommand {confirm: <that array, unchanged>}` and forward the new `answer`. Never change it,
  never send it without their yes.
- `incomplete: true`: OTTO-Command ran out of time; `actions` still says what was done. Say so and offer to try again.

Pass the person's earlier turns as `history` (`[{role, text}]`, oldest first, at most 12) when a request depends on them
("do the same for RT-3"), and `idempotency_key` (the chat message id) so a resend after a timeout replays instead of
acting twice.

**Production.** When the live run at the depot is a production run, a lower charge limit is always previewed first and
needs the person's yes (the `confirm` above): say plainly that nothing has changed until they confirm. A passcode
session can read the cars there but not change them; OTTO-Command says so, and to sign in (Connecting, above).

### Only if OTTO-Command is not available

If `ask_ottocommand` answers with an error (`ask_not_configured`: it is not switched on; `ask_model_failed`; or the tool
is missing from the list), use the typed tools directly. They are the same database filter:

| When the person says | Call (each with `session` when you have one) |
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
"After charging" needs nothing extra: OTTO-Q always plans bay work after the charge. In a production run, preview a
lower charge limit (`mode: "preview"`) and send its `confirm` only after the person says yes: OTTO-Q refuses it otherwise.

## How to answer

1. **Forward OTTO-Command's `answer`.** Shorten it only if you must, never change its meaning, and keep the
   confirmation code and the link. With the typed tools, use OTTO-Q's `summary` the same way.
2. **Facts only from tool results.** Never invent a car, a number, a time or a setting. If a car does not exist, the
   refusal lists the real names: say so and offer them.
3. **A change is done only when `outcome` is `applied`.** `refused`: say it was not done, why, in OTTO-Q's plain words,
   and what is allowed (a charge limit outside the contract's range, 80-100% for this fleet, is refused with the range).
   `no_change`: it was already so. `previewed`: nothing has changed yet.
4. **Ask one short question** only when it is truly ambiguous (which service? which car? until when?). Do not ask "are
   you sure?" for a clear command, except where OTTO-Command returns a `confirm`.
5. **Times:** OTTO-Q writes "7:00 AM sim time" (the simulation's clock) and "9:24 PM CT" (real time). Keep the label.
6. **Everything resets** when the run ends (a stop or reset in OTTO-TWIN, or the end of a production run): say so if
   they ask why a setting is gone. With no run that accepts changes, OTTO-Q refuses and says why.
7. Short and plain: two to five sentences, no tables, no JSON, no command ids unless asked.

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
