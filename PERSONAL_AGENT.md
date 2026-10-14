# PERSONAL_AGENT: any agent sets what your cars need

*Updated 2026-10-03/04, 10:50 PM–3:00 AM CT (2026-10-04 03:50–08:00 UTC), for the passcode door (0607/0608). Written
first 2026-10-02 for an owner's issued key (0605/0606). **Live since 2026-10-04, 6:42 AM CT:** applied, deployed, the
passcode on and the live smoke passed (section 7). Section 9 says exactly what was and was not verified.*

*2026-10-10: **an owner can now sign in and connect their own agent** (0700, section 10): the agent sends its person to
www.ottoyard.com/connect, they sign in with their OTTOYARD account and approve it, and it holds its own tokens; no
passcode or key passes through the chat, and the connection outlasts runs. Set up for Chase and his Hermes first.*

*2026-10-14: **OTTO-Command is the one door for personal agents** (0721 and the gateway, section 11; built, not yet
applied or deployed): the MCP tool `ask_ottocommand` takes your words, reads and acts with your agent's own token, and
answers; a signed-in owner may change their cars on a **production** run, recorded under their name, and a lower charge
limit there applies only as the confirm of a preview the same agent recorded in the last 15 minutes. OTTO-Q enforces
that order; the confirm itself is relayed by the owner's agent, and OTTO-Q cannot see the owner's yes.*

*2026-10-14, afternoon: **OTTO-Command searches OTTO-Q and the web** (section 11, "Search, the web, and what lasts";
built, not yet applied or deployed): a read-only `ottocommand_search` tool and `POST /v1/search`, the web inside
`ask_ottocommand` with its sources cited, and a rule in code that an ask which read the web changes nothing. A charge
limit or an every-return service set by a signed-in owner is now **saved to the cars** and carried onto every new demo
and production run until the owner changes it; holds, one-time orders and anything set through the passcode still end
with the run. The passcode is refused while a production run is live.*

Chase, 2026-10-03: *"I want to be able to setup and activate a new agent from theoretically Hermes or [Grok] or any
other agent and be able to call OTTOYARD ... and allow me to access my fleet ... a general password or passcode that I
can enter after the welcome agent triggered ... if it's something that doesn't fit, [OTTO-Q] should send back a
failure state that is still within plain English and explaining why. Otherwise it should send back a confirmation and
validation code with link to the orchestra app and updated information ... any adjustments ... should only apply for a
single simulation run."*

That is what this builds. **Any agent** that can call a web address (Hermes, Grok, ChatGPT, Claude, a script) connects
to OTTOYARD with **no key**: it is welcomed, asks you for OTTOYARD's demo passcode, and gets a session on Tesla Robotaxi
TN's 36 cars at the twin depot (32 Model Y, 4 Cybercab). It can then ask about your cars in plain English and change
what they **need**: how full they charge, which services they get, and a time before which they may not leave. OTTO-Q
checks every change against your contract and its own rules. A change that does not fit is refused in plain English
with the reason. One that fits is applied at OTTO-Q's next tick and answered with a **confirmation code**
(`OQ-XXXX-XXXX`) and an **OrchestrAV link**; OrchestrAV, OTTO-PULSE and the twin show the same code beside it. A stop
or reset of the twin lifts everything set and **ends every passcode session**, so the next demo starts at the welcome.

```
  you ──> any agent (Hermes, Grok, ChatGPT, Claude, a script) ── no key needed
            │  1. welcome            "Welcome to OTTOYARD ... ask your person for the passcode"
            │  2. enter_passcode     → a session key (oqs_…), shown once, kept by the agent
            │  3. any tool + session → reads and changes, each answered in plain English
            v
     ottoq-agent-gateway  (MCP · REST + OpenAPI · POST /v1/ask: OTTO-Command reads your words)
            │
     public.ottoq_agent_call ── the one door: key or session → rate limit → capability → the tool → the ledger
            │
            ├─ reads:    my_fleet · my_vehicle · my_settings · my_commands
            └─ changes:  your settings + a receipt with its confirmation code
                            │
     OTTO-Q's next tick ────┘ re-targets your cars, adds or removes YOUR service orders, honours holds
            │
     OrchestrAV (your fleet, the receipt on top) · OTTO-PULSE (the crew sees it per car) · OTTO-TWIN (marker, Q card, feed)
```

**Three authorities, and none crosses into another.** You (through your agent) decide **what** your cars need. OTTO-Q
decides **when and where**. The car's own driving system decides **how it moves**. Nothing an agent sends moves a car,
assigns a stall or charger, or puts one car ahead of another owner's.

---

## 0. Connect any agent (two minutes)

**What you give an agent:** the address, and the passcode (out loud or in your own chat with it; never in a shared
channel).

```
OTTOYARD (MCP)    https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-agent-gateway/mcp
OTTOYARD (REST)   https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-agent-gateway/v1
                  (OpenAPI: …/v1/openapi.json, public)
```

**Then say "Connect to OTTOYARD."** The agent calls `welcome` and reads you something like:

> Welcome to OTTOYARD. You have reached OTTO-Q, the engine that orchestrates the OTTOYARD Nashville Flagship depot (a
> live digital twin). With OTTOYARD's demo passcode you can see and adjust Tesla Robotaxi TN's 36 cars here (32 Model Y
> and 4 Cybercab): how full they charge, which services they get, and when they may leave. Ask your person for the
> passcode, then call enter_passcode with it and your name. A demo run is live now (7:00 AM sim time).

You give it the passcode; it calls `enter_passcode {passcode, agent: "Hermes"}`:

> Welcome, Hermes. The passcode is right: you have Tesla Robotaxi TN's 36 cars at OTTOYARD Nashville Flagship until
> 3:09 AM CT, or until the demo run ends, whichever comes first. The demo run is live (7:00 AM sim time). Try: "how are
> my cars doing?", "charge every car to 90% instead of 100%", "wash every car each time it returns", or "keep one car
> here until 6 AM".

From then on the agent sends the session key with every call (over MCP, as each tool's `session` argument; over REST,
as `Authorization: Bearer`). It never needs to show you the key. A wrong passcode is refused in plain English with the
tries left (five in 15 minutes per caller, then a wait). When you stop or reset the twin, the agent's next call is told
*"This OTTOYARD session ended when the demo run ended ... Call enter_passcode again"*, and it asks you for the passcode
again.

| Agent | How it connects (no key; read 2026-10-04, sources at the end) |
|---|---|
| **Hermes** | `~/.hermes/config.yaml`: `mcp_servers: ottoyard: {url: "…/ottoq-agent-gateway/mcp"}`, no headers; `/reload-mcp`. The tools appear as `mcp__ottoyard__welcome`, `mcp__ottoyard__enter_passcode`, … The skill in `integrations/hermes/ottoq-owner/` teaches the flow (section 5). |
| **ChatGPT** | Developer mode (Plus, Pro, Business, Enterprise, Education, on the web): Settings → Security and login → Developer mode, then create a developer-mode app with the MCP address and **No Authentication**. |
| **Claude** | claude.ai → Customize → Connectors → Add custom connector (Free, Pro, Max; an Owner on Team/Enterprise): the MCP address, Authentication **No sign-in**. Claude Code: `claude mcp add --transport http ottoyard <the MCP address>`. |
| **Grok** | xAI API, Remote MCP Tools: `server_url` = the MCP address, `server_label` = `ottoyard`, no `authorization`. |
| **Anything else** | REST: `GET /v1/welcome`, then `POST /v1/passcode {"passcode": "…", "agent": "…"}`, then the session key as `Authorization: Bearer` on `/v1/me/…`, or `POST /v1/ask` with your words. A GPT Action or any OpenAPI client can import `/v1/openapi.json`. |

**Not verified yet with each client**: the gateway answers every no-key MCP request without asking for sign-in, which is
what "No authentication" / "No sign-in" expects, and the end-to-end tests drive exactly those requests, as did the live
smoke on 2026-10-04. A real Hermes, ChatGPT, Claude or Grok has not been pointed at it yet (section 9).

**Setting the passcode.** One line in the Supabase SQL editor (6–64 characters; it is stored only as a bcrypt hash):

```sql
SELECT ottoq_agent_set_passcode('your-passcode');      -- set or change it
SELECT ottoq_agent_set_passcode(NULL);                 -- turn the door off
```

A new passcode leaves sessions already open as they are (they end with the run). An issued key (section 5, option K)
still works beside the passcode, for an agent you want connected without one.

## 1. What your agent can do

| You say (to Hermes) | The tool | What OTTO-Q does |
|---|---|---|
| "How are my Teslas doing?" | `my_fleet` | Plain English: how many are charging, in a bay, waiting, out; average charge; what you have set; who is ready next; the OrchestrAV link |
| "Where is Tesla 45 and when will it be ready?" | `my_vehicle` | That car: where it is, charge and target, what is still to do before it leaves, your hold, its planned ready time, OTTO-Q's last decision for it |
| **"Change all Tesla maximum charging to 90% instead of 100%"** | `set_charge_limit {vehicles: "all", percent: 90}` | Every car charges to at most 90%. A car charging now stops at 90%; a car already above is not drained; a car out on the road charges to 90% when it comes in |
| "Charge them full again" | `clear_charge_limit` | Back to 100% |
| **"Send Tesla 45 to a service bay right after charging"** | `request_service {vehicles: ["Tesla 45"], service: "mechanical_pm"}` | A service-bay visit on this visit. OTTO-Q already plans bay work after the charge, so "after charging" needs no extra instruction; the car does not leave until it is done |
| **"All my cars need an exterior wash every time they come back"** | `request_service {vehicles: "all", service: "exterior_wash", when: "every_return"}` | A standing order: this visit for cars at the depot (unless `include_current_visit: false`), then every return |
| "Cancel the wash order" | `cancel_service` | Your order comes off. A service OTTO-Q found a car to need stays, and one already under way finishes |
| "Keep RT-3 here until 6 AM" | `hold_vehicle {until: "6:00 AM"}` | Not before 6:00 AM on the sim clock (or `for_minutes`, up to 24 sim hours). A ready car waits in staging and keeps no charger |
| "Let it go" | `release_hold` | It may leave as soon as it is ready |
| "Undo that" | `undo_command` | What the command set is withdrawn, and what it replaced comes back |
| "What did I change today?" | `my_commands` / `my_settings` | Every command with its receipt and where it stands now; everything in force |

**Services you can order (11):** exterior wash, interior deep clean, interior tidy, interior inspection, sensor clean,
sensor calibration, software update, remote diagnostics, mechanical PM (a service-bay visit), cosmetic repair, item
retrieval. Not yours to order, by design: charging (the limit is your lever), the readiness check (OTTO-Q's own gate),
triage, fault repair (a faulted car is repaired before it charges or leaves, always) and the depot's night walkaround.

**Names work the way people say them.** "Tesla-AV-045", "Tesla 45", "AV-45", "45", "RT-3", or the id; matched only
inside your own fleet at the twin depot. A name that matches nothing, or several cars, is refused and the refusal lists
your cars. **There is no "Tesla 98"**: your 36 cars are Tesla-AV-041 to -070 and Tesla-RT-001 to -006. Asked for it,
OTTO-Q answers *"Not done: No car in your fleet matches "Tesla 98". Your cars here: Tesla-AV-041 to Tesla-AV-070
(30 cars); Tesla-RT-001 to Tesla-RT-006 (6 cars)."* (That sentence shape was produced by the scratch rehearsal, whose
stub fleet is smaller; the live wording follows the same rule over your real cars.)

## 2. The rules OTTO-Q enforces (in the database, not in a prompt)

- **Your cars only.** The session (or key) is bound to Tesla Robotaxi TN at the twin depot; every other car reads as not found.
  Waymo and Zoox cars cannot be named.
- **Demo runs only** (until 0721; section 11). Settings apply to a live `operator_demo` run at the twin depot, and end
  with it (section 4). With no demo live, a command is refused with *no_live_demo*. After 0721 a production run also
  takes changes, from an agent signed in to its owner's account only, each recorded under that person; a lower limit
  there applies only as the confirm of a recorded preview (section 11). With no run live, that signed-in agent can still
  save a charge limit or an every-return service to the cars (outcome `saved`, section 11); nothing else changes then.
- **Charge limits stay inside your contract.** Tesla Robotaxi TN's contract allows **80% to 100%** (read 2026-10-02).
  "Charge to 50%" is refused and recorded, with the range in the reply. Rule 9 holds: the depot never lowers a target;
  only the owner does, verified (the contract) and confirmed (an explicit command).
- **You can add work, never remove work OTTO-Q found needed.** No car leaves with a service still needed, whoever
  ordered it.
- **A hold only delays.** "Not before", at most 24 sim hours, never moves a car.
- **Nothing moves a car.** The agent side writes only its own tables; OTTO-Q's tick changes a car's needs (its target,
  its service list) and its decide path, unchanged, decides the rest.
- **Everything is reversible and recorded.** Undo, cancel, clear, release; refused commands are kept as evidence with
  the reason; the receipts ledger is append-only.
- **Preview when you want it.** `mode: "preview"` changes nothing and answers with the exact plan, per car, and a
  ready-to-send confirm bound to that plan by a hash. If anything moved in between, OTTO-Q refuses the confirm with the
  new plan. A held car's preview names the time it resolved to, so "hold for 90 minutes" confirmed later still means the
  time it showed.
- **Retries are safe.** The same `idempotency_key` returns the first receipt instead of acting twice; the same key with
  a *different* command is refused (*idempotency_key_reused*, HTTP 422, as the IETF draft specifies).
- **Rate-limited and ledgered.** Every call, refusals included, is a row in `ottoq_agent_call_ledger`.

## 3. What comes back

Every command answers with a **receipt**: `outcome` (`applied`, `previewed`, `no_change`, `refused`, and since 0721
`saved`: made with no run live, it changed only what is saved to the cars), a plain-English `summary` in OTTO-Q's own
words, its `confirmation_code` when applied, the `link`, and an `undo` when applied. From the scratch
rehearsal (four stub cars):

> Done. All 4 Teslas charge to at most 90% instead of 100%.
> \- 1 is charging and will stop at 90%
> \- 1 already has enough charge for 90%
> \- 1 is out; it charges to 90% when it next comes in
> \- 1 is charging past 90%: its charge ends at the next tick
> This lasts until the demo run ends or you undo it.
> Confirmation code: OQ-B610-EA0E.
> See it in OrchestrAV: https://ottoyard-orchestra-av.lovable.app/?source=agent&run=…&owner=…&tab=fleet&command=…

And a change that does not fit, in plain English, with no code:

> Not done: 70% is below the 80% minimum in your contract. Choose 80% to 100%.

**The confirmation code** is derived from the command (the first 8 hex digits of the SHA-256 of its id), so the
agent's receipt, `my_commands`, OrchestrAV, OTTO-PULSE and the twin all show the same `OQ-XXXX-XXXX` for the same
change, and a retried command replays it. The link opens OrchestrAV as your fleet, on the Fleet tab, with that receipt
on top, its code, and where it stands now (in force, undone, refused, or lifted with its run). Every car card shows
what your agent set, e.g. "Max 90% · your agent", and "Set by your agent" lists everything in force and every command
with its code and its agent ("Grok · passcode"). OTTO-PULSE shows the crew the same per car, and the twin marks each
car an agent touched, adds the settings to its Q card, and puts each command in its Agent feed.

**Times.** Receipts say "7:00 AM sim time" for the simulation's clock and "9:24 PM CT" for real time, both Nashville
time. A hold's time is on the sim clock.

## 4. The reset

You asked for demos that start clean: *"if I stop a simulation or pause and reset and stop that would completely negate
any agent calls and adjustments for now."* When a demo run ends (Stop or Reset in the twin), two triggers on
`ottoq_sim_runs` fire on the same transition: one **lifts every owner setting** and puts each car back to its baseline
target (0605); the other **ends every passcode session** at the depot (0607). A new run starts with nothing in force and
every agent back at the welcome. **Pause is not an end**: a paused run keeps its settings and its sessions. What survives
is the record: the commands and their receipts (`ottoq_owner_commands`, class `evidence`), each marked as lifted with
its run, and the call ledger. Saved per-car preferences across runs are the later step (section 8).

## 5. Connecting Hermes

**Chase's Hermes signs in instead (section 10).** The two ways below still work, through the same gateway. **Use the passcode** (option P) unless you want a Hermes that is connected without
one (option K).

### (P) The passcode: no key in Hermes at all

`~/.hermes/config.yaml` (also at `integrations/hermes/mcp_servers.example.yaml`):
```yaml
mcp_servers:
  ottoyard:
    url: "https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-agent-gateway/mcp"
    timeout: 60
    connect_timeout: 30
    tools:
      resources: false
      prompts: false
```

Then `/reload-mcp`, and copy the skill: `integrations/hermes/ottoq-owner/` to `~/.hermes/skills/fleet/ottoq-owner/`.
In a new Hermes chat, say "connect to OTTOYARD": Hermes calls `mcp__ottoyard__welcome`, asks you for the passcode, calls
`mcp__ottoyard__enter_passcode`, and from then on passes the session key with each call. The skill tells Hermes to keep
the key to itself, to relay the receipt, its confirmation code and its link rather than paraphrase them, and to ask for
the passcode again when a session ends.

**Two Hermes notes.** Hermes hands a tool result to its model as text (Hermes MCP feature page, read 2026-10-03), so
every result carries its plain-English `summary` (and every command its code and link) inside that text. And an older
Hermes (v0.21.3) failed against MCP servers that answer `initialize` with an older protocol version than it asked for;
that was fixed (issue #114350, closed by PR #114817). This gateway serves the stateless 2026-07-28 revision and the 2025
initialize revisions on one endpoint. If Hermes reports "Unsupported MCP-Protocol-Version", update Hermes, or use REST
in the meantime.

### (K) An issued key: connected without a passcode

For an agent that should never need the passcode: issue a key (section 7 step 6), put it in `~/.hermes/.env` as
`OTTOQ_AGENT_TOKEN=oqa_…`, and add `headers: {Authorization: "Bearer ${OTTOQ_AGENT_TOKEN}"}` to the block above. The
tools then need no `session`, and the key does not end with the run (it is revoked by hand). A key is a secret: never in
a chat, a repo, or a URL.

### Plain English: `POST /v1/ask`, or the MCP tool `ask_ottocommand` (0721)

Any agent with a session or a key can forward your words (over MCP, as the tool `ask_ottocommand`, section 11); OTTO-Command (inside the gateway) reads them, calls the owner tools with **that** key, and
answers in plain English with OTTO-Q's receipts and the link. One call, no tool mapping on Hermes's side.

```bash
H="Authorization: Bearer $SESSION"      # a passcode session key (POST /v1/passcode) or an issued key
curl -sS -X POST "$GATEWAY/v1/ask" -H "$H" -H "Content-Type: application/json" \
  -d '{"text":"change all Tesla maximum charging parameters to 90% instead of 100%", "idempotency_key":"tg-58213"}'
# → {"data":{"answer":"Done. All 36 of your Teslas …\nSee it in OrchestrAV: https://…","link":"https://…",
#            "actions":[{"tool":"set_charge_limit","outcome":"applied","summary":"…","command_id":"…","undo":{…}}],
#            "dry_run":false,"incomplete":false}, "meta":{…}}
```

- `dry_run: true` runs every change as a preview, **enforced in code**, and returns each plan's `confirm`. To apply
  exactly what was shown, send `{"confirm":[<those objects>]}`: no model is involved in a confirm, which goes out as
  transport `confirm`, and an apply it confirms is recorded `via = 'confirm'` (0721).
- `history: [{role, text}]` (up to 12 turns) carries the conversation; it is text only, so nothing can be passed off as
  a tool result.
- `idempotency_key`: resend the same ask after a timeout and each command it made replays instead of acting twice
  (Telegram's message id is a good key).
- `answer` is held to the receipts in code: it cannot say "Done" when nothing applied, and an applied change always
  carries its confirmation code and its link. `actions` is the authoritative record.
- It answers `503 ask_not_configured` until the gateway has a model (section 7 step 2); everything else still works.

### REST, and OpenAPI for anything else

`GET /v1/me/fleet` · `GET /v1/me/vehicles/{name}` · `GET /v1/me/settings` · `GET /v1/me/commands[/{id}]` ·
`POST /v1/me/charge-limit` · `/charge-limit/clear` · `/services` · `/services/cancel` · `/holds` · `/holds/release` ·
`/undo`. The OpenAPI 3.1 document at `GET /v1/openapi.json` (public, no token) is generated from the same catalog the MCP
endpoint serves, so the two cannot drift. A refused command answers HTTP 422 **with its receipt**.

```bash
curl -sS "$GATEWAY/v1/me/fleet" -H "$H"
curl -sS -X POST "$GATEWAY/v1/me/services" -H "$H" -H "Content-Type: application/json" \
  -d '{"vehicles":["Tesla 45"],"service":"mechanical_pm"}'
```

## 6. Security

- **Demo-grade by your decision** (*"this doesn't have to be extremely secure"*): everyone with the passcode shares the
  same demo fleet, and the run's end resets all of it.
- **The passcode** is stored only as a bcrypt hash (`ottoq_agent_demo_passcode`, readable by no role). Wrong tries are
  counted from the call ledger: five per caller in 15 minutes, then a wait; 200 across all callers.
- **A session is an owner key with an expiry, nothing more.** A CHECK pins its capabilities to read + note +
  owner_settings, its fleet to the passcode's, its depot to the twin. It lasts 240 minutes or until the demo run ends,
  whichever is first; a revocation is final. Its key (`oqs_` + 64 hex) is shown once, kept as SHA-256, and travels as a
  tool argument only because a chat agent has nowhere else to put it. A long-lived `oqa_` key is refused as an argument.
- **OTTO-Command's plain-English door cannot exceed the caller.** It reaches OTTO-Q only through the gateway's own call,
  bound to the caller's key or session; dry run, the tool set, argument checks and the step limit are code, not prompt.
- **Not changed, by your decision for the demos (FINDINGS S-03):** the cockpit OTTO-Command (`ottoq-ottocommand`)
  accepts the public anon key and performs its write tools (energy dial, re-optimize, amend schedule, escalate,
  self-improve) with the service-role key. Since the cockpits opened without sign-in, anyone who opens one can drive
  those. The owner settings are not reachable that way. The fix (role from the JWT, read-only tools for anon) waits for
  sign-in to come back.
- **The next step for real owners** is OAuth 2.1 ("Connect OTTOYARD" with a sign-in page), which keeps the key out of
  the chat entirely; ChatGPT, Claude and Hermes all support it.

## 7. Going live (times CT; never 11 PM–6 AM CT, the sweep window)

Chase, 2026-10-03, 10:50 PM CT: build tonight, "let me know ... when you are ready to validate test runs. Everything
else you should be able to confirm and make decisions upon."

1. **Apply `0559`, `0560`, `0605`, `0606`, `0607`, `0608`**, in that order, per `scripts/APPLYING.md`. 0605 changes
   three tick-path bodies (`forces_recert` TRUE): **one recertification round** follows. The others are FALSE/FALSE.
   0605 and 0607 refuse while a pair, the recert runner, a dial pair or a sweep arm is running (retry a few minutes
   later).
2. **Deploy the gateway** with JWT verification off (it authenticates itself):
   `supabase functions deploy ottoq-agent-gateway --project-ref gxdrcyphqjzjsuhxuqtg --no-verify-jwt`
   (files: `ottoq-agent-gateway/index.ts`, `_shared/agent_gateway.ts`, `_shared/agent_dial_discipline.ts`,
   `_shared/ottocommand_owner.ts`). For `/v1/ask`, the function secret `OTTOCOMMAND_OWNER_MODEL` names the model (it
   falls back to `ANTHROPIC_MODEL`, and since 0721 to the door's default model when neither is set); without the key,
   `/v1/ask` answers 503 and everything else works.
3. **Set the passcode**: `SELECT ottoq_agent_set_passcode('…');`
4. **Smoke test, as a new agent sees it:** `GATEWAY_URL=… PASSCODE=… node scripts/agent-gateway-smoke.mjs --passcode`
   (welcome, MCP list, a wrong and a right passcode, `my_fleet`, a preview; nothing is applied; the session key is
   never printed).
5. **Start a demo in OTTO-TWIN**, then from any agent: "connect to OTTOYARD", the passcode, "how are my Teslas doing?",
   "change all Tesla maximum charging to 90%". Tap the link; look for the code in OrchestrAV, OTTO-PULSE and the twin.
   Stop the run; the agent's next call says the session ended.
6. *(Optional)* **An issued key** for an agent that should not need the passcode (SQL editor; shown once):
   ```sql
   SELECT ottoq_agent_issue_token(
     'chase-hermes', 'personal', ARRAY['read','note','owner_settings'],
     '33333333-3333-3333-3333-333333333333',      -- Tesla Robotaxi TN
     '11111111-1111-1111-1111-111111111111',      -- the twin depot
     'Chase''s Hermes', 60, 20);                  -- 60 calls a minute, 20 open requests
   ```

## 8. Decided, and not built yet

**Decided 2026-10-03 (Chase left these to me):** a clear command acts at once (preview on request, undo always); the
contract's 80% floor stays; "my Teslas" are Tesla Robotaxi TN's 36 cars at the twin depot; S-03 waits for sign-in; the
passcode opens Tesla Robotaxi TN only; a session lasts 240 minutes or until the run ends.

**Not built, on purpose:** settings that persist across runs (the reset is the point); ready-by deadlines or priority
over other owners (a contract entitlement across tenants, not an owner setting); charger-type preference (needs a
decide-path hook); push notifications ("tell me when Tesla 45 is ready": needs the agent's webhook and a signing
secret); OrchestrAV making changes itself (it is read-only until it signs owners in); a sandbox per visitor.

**The next steps, in order:** ~~OAuth 2.1 for the MCP connection, with a "Connect OTTOYARD" page~~ (built: section 10);
saved per-car preferences set from OrchestrAV with verification (your "eventually ... a per vehicle or per asset setting ... toggled
from a UI"); signed push for ready / refused / lifted; a signed receipt a third party can verify.

## 9. Verified, and not verified

**Verified (2026-10-03/04, on a scratch PostgreSQL 16 over the stub engine):**
- `tests/test_passcode_door_sql.py`: 26 passed. The welcome; the door off; the passcode stored as bcrypt; wrong
  passcodes refused in plain English and throttled per caller (and a caller freed after 15 minutes); the right passcode
  opening exactly an owner key with an expiry; a session that cannot be widened or edited; a session's commands with
  their confirmation codes in the receipt, `my_commands`, a replay and OrchestrAV's board; refusals with no code; a
  demo run's end ending every session (pause does not; a non-demo run does not); expiry; the crew's board; the grants.
- `tests/passcode_door.test.mjs`: 12 passed, including both flows end to end over the real 0559 + 0560 + 0605–0608 SQL
  (a new agent over MCP: welcome, wrong and right passcode, a change and its code, the board, the run's end; a script
  over REST with the session as a Bearer).
- `tests/test_owner_agent_sql.py` 50, `tests/owner_agent.test.mjs` 31, `tests/agent_gateway.test.mjs` 39: still pass.
- The gateway as a real HTTP server over that database: `scripts/agent-gateway-smoke.mjs --passcode`, 6 of 6.
- OrchestrAV 208 tests, on real `ottoq_owner_board` output with 0608 applied.

**Verified live (2026-10-04, 6:14–6:50 AM CT):**
- The six migrations applied from their files. Each ledger row is byte-identical to its file (md5 and length), and all
  67 functions they create or replace match the scratch cluster's `md5(prosrc)`.
- The gateway deployed as version 1. Its source, read back through the Supabase connector and hashed from the API's own
  response, is byte-identical to the committed files, and the five documents it builds from its catalog match what the
  repo builds.
- `scripts/agent-gateway-smoke.mjs --passcode` against the live URL: 6 of 6. The welcome named Tesla Robotaxi TN's 36
  cars (32 Model Y and 4 Cybercab); a wrong passcode was refused in plain English; the right one opened a session; a
  preview answered `no_live_demo`, since no demo run was live. The smoke session was then revoked.
- The cockpits' reads (`ottoq_depot_owner_board`, `ottoq_owner_board`) answer the publishable key. The dispatcher and the
  passcode setter answer it 404.
- `POST /v1/ask` answers 503 `ask_not_configured`: it needs `ANTHROPIC_API_KEY` and a model name in
  `OTTOCOMMAND_OWNER_MODEL` (or `ANTHROPIC_MODEL`), and at least one of those function secrets is not set (section 7,
  step 2). Every tool works without it.

**Not verified:** a real Hermes, ChatGPT, Claude or Grok client; a live model behind `/v1/ask`; a change applied on a
live demo run, which needs one running (section 7, step 5); 0605's tick step under a demo (V2 measured it inert on the
live catalog at apply time, and it acts only on settings an agent has set).

## 10. Sign in: your own agent, connected to your OTTOYARD account (0700)

*Built 2026-10-10, 12:45–2:40 AM CT; going live is in "Live" below.* Chase, 2026-10-10: *"I just want one unified login
no matter what ... let's just set it up for only me and my [Hermes] agent currently ... it has to function super well
and very close to how actual production will eventually work."*

**What it is.** The way any service lets an app act for you (OAuth 2.1, the standard every MCP client speaks), with
OTTOYARD as the service and your OTTOYARD account as the login. Your agent asks to connect; you sign in on OTTOYARD's
page and approve it by name; it gets its own access token (an hour, renewed by itself) and refresh token (30 days,
single-use). It reaches exactly what an owner key reaches (your fleet's cars: read, notes, and what they need), through
the same door, rules, receipts and confirmation codes. **No password, passcode or key passes through the chat.** The
connection outlasts runs (your *settings* still lift when a demo run ends, section 4) and ends when you disconnect it.

```
  you ── Telegram ──> Hermes (cloud) ── hermes mcp login ottoyard --flow device
                         │  1. GET /account/mcp              -> 401 + where to sign in (RFC 9728)
                         │  2. the sign-in's metadata         <- www.ottoyard.com/.well-known/oauth-authorization-server
                         │  3. register, ask for a device code (RFC 7591, RFC 8628)
                         │  4. "open www.ottoyard.com/connect  Code: BCDF-GHJK"  ──> you, on your phone
                         │                                         sign in (your OTTOYARD account), see who is asking, Approve
                         │  5. its poll gets an access token + refresh token
                         v
     ottoq-agent-gateway /account/mcp  (Authorization: Bearer oqt_...)  ->  public.ottoq_agent_call  (0559's one door)
```

### Connect Chase's Hermes (cloud, through Telegram)

1. **The config, on the Hermes host** (`~/.hermes/config.yaml`; also `integrations/hermes/mcp_servers.example.yaml`):
   ```yaml
   mcp_servers:
     ottoyard:
       url: "https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-agent-gateway/account/mcp"
       auth: oauth
       timeout: 60
       connect_timeout: 30
       oauth:
         flow: device
         timeout: 600
       tools:
         resources: false
         prompts: false
   ```
2. **Tell Hermes, in Telegram:**
   > Run `hermes mcp login ottoyard --flow device` in the background. When it prints a link and a code, send them to
   > me, then wait until it says Authenticated.
3. **On your phone:** open www.ottoyard.com/connect, sign in, type the code, Approve. The page says who is asking and
   what it could and could not do, and shows it arrive under "Your agents".
4. **Back in Telegram:** `/reload-mcp`, then *"How are my Teslas doing?"*

Hermes renews its token by itself, before it runs out. It needs step 2 again only if you disconnect it, or if it goes
30 days without being used. If it reports that OTTOYARD rejected the sign-in, that is what happened.

### Your account

- **The page:** www.ottoyard.com/connect. Sign in to approve an agent, see the agents connected to your account, or
  disconnect one (it stops at once; its tokens are refused, and so is renewing them).
- **Accounts:** one, `chase@ottoyard.com`, linked to Tesla Robotaxi TN at the twin depot. It was created on 2026-10-10
  at 2:06 AM CT through Supabase Auth's own sign-up endpoint (Auth hashed the password itself) and confirmed by hand.
  Its password is the temporary one Chase chose for now, written nowhere in this repository; change it in the
  Supabase dashboard (Authentication, Users) whenever you like.
- **Who else can sign in:** this project's Supabase Auth has sign-ups switched on (measured from its public settings,
  2026-10-10: `disable_signup` false, email confirmation required), so anyone with a real mailbox can make an account.
  Such an account reaches nothing here: it can approve or connect an agent only once `ottoq_owner_account_link` (the
  service role only) links it to a fleet, and until then the page tells it so. Switching sign-ups off is a setting
  in the Supabase dashboard (Authentication), not something this file changes.
- **Linking another account** (when it is time): create the user in Supabase Auth, then in the SQL editor
  `SELECT ottoq_owner_account_link('them@example.com', '<fleet_operators.id>');`. `ottoq_owner_account_unlink` stops an
  account and disconnects every agent it connected.

### The addresses

| | |
|---|---|
| Signed-in MCP | `https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-agent-gateway/account/mcp` |
| Protected-resource metadata | `{gateway}/.well-known/oauth-protected-resource/account/mcp` (the 401 names it) |
| Authorization server | `https://www.ottoyard.com` (its metadata at `/.well-known/oauth-authorization-server`, the OTTOYARD-SITE repository) |
| Sign-in page | `https://www.ottoyard.com/connect` |
| Endpoints (in the gateway) | `{gateway}/oauth/register`, `/oauth/device`, `/oauth/authorize`, `/oauth/token`, `/oauth/revoke`; `/oauth/metadata` is a copy of the server's metadata to compare with the site's |

**Why the metadata lives on ottoyard.com.** An MCP client looks for it at a fixed place under the server's host, and
stops at any answer but "not found". Every such place on supabase.co answers 401 (measured), so the metadata is
published at OTTOYARD's own site, which is also what a production login should look like. The endpoints stay in the
gateway, where every decision is the database's.

### What the rules are (in the database)

- A connection is an `ottoq_agent_principals` row of origin `oauth` with an owner key's scope, fixed by a CHECK.
- Nothing connects until a signed-in account linked to a fleet approves the agent by its code. Codes are single-use; a
  device code lives 10 minutes, a browser code 5.
- Secrets are SHA-256 at rest. The gateway hashes what it is handed before it calls; the ledger never holds one.
- A refresh token presented twice closes the connection (a retry within a minute whose new token was never used is
  forgiven). An access token is honoured five minutes past its hour: a client renews by its own clock, and Hermes
  measured on its own CLI starts a whole new sign-in, rather than renewing, when a token it believes valid is refused.
- Agents with a browser (Claude, ChatGPT and others later) use the same page through the authorization-code flow with
  PKCE; rehearsed, not yet pointed at a real one.
- The passcode door (section 0) and issued keys (section 5, option K) are unchanged and still work.

### Verified, and not verified

**Verified on a scratch PostgreSQL 16 over the stub engine (2026-10-10):** `tests/test_agent_signin_sql.py` 35 passed;
`tests/agent_signin.test.mjs` 19 passed, including the whole device sign-in over the real SQL; the existing gateway
suites still pass (132 SQL and 101 node tests with CI's own commands). **Hermes Agent's own CLI** (NousResearch/
hermes-agent at `dce1e9b3`, MCP SDK 2.0.0), unmodified, against the gateway's code over that SQL: `hermes mcp login
ottoyard --flow device` printed the link and code, was approved through this page in a phone-sized headless browser,
and finished *"Authenticated — 20 tool(s) available"*; it renewed its token through the token endpoint when its clock
said the hour was up; the MCP SDK's client then called `whoami` ("signed in", chase@ottoyard.com) and `my_fleet`. A
browser sign-in with PKCE came back with its code, state and issuer and exchanged for tokens.

**On the live project:** see "Live" below, including the site's half and Chase's own Hermes, connected on 2026-10-10.

### Live

*Went live on the engine 2026-10-10, 2:06–6:17 AM CT, and on www.ottoyard.com at 10:09 AM CT. Chase's own Hermes
connected at 12:04 PM CT.*

- **Chase's account:** created at 2:06 AM CT on live Supabase Auth ("Your account" above). Checked live the same minute:
  the right password signs in, a wrong one is refused (`invalid_credentials`).
- **The gateway:** `ottoq-agent-gateway` v2, deployed at 2:23 AM CT (`edge-functions/_MANIFEST.md` footnote 13). Read
  back from the API: all five files byte-identical to the repository. The passcode door and agent keys answered as before.
- **The migration:** 0700 applied at 6:14 AM CT, version `20261010111411`. The stored statement is the committed file,
  byte for byte (md5 `8ea4dea3`, 131,578 characters). P0-P2, V1 and V2 passed inside the apply.
- **The link:** chase@ottoyard.com to Tesla Robotaxi TN, at 6:15 AM CT.
- **The live smoke** (`scripts/agent-signin-smoke.mjs` with `SKIP_SITE=1`), 6:16:59-6:17:07 AM CT, **14 of 14**:
  - the signed-in MCP address answers 401 with the challenge;
  - the protected-resource metadata names `https://www.ottoyard.com`;
  - a test agent ("OTTOYARD smoke test") registered and asked for a device code;
  - a poll before approval was pending;
  - Chase's account signed in and approved it through the page's own doors;
  - the next poll connected, with an access token and a refresh token;
  - MCP initialize, tools/list (20 tools) and whoami ("signed in", chase@ottoyard.com) answered;
  - it was disconnected through the page's door, and its token was then refused with the challenge.

  Every step is a row in the call ledger (`oauth.*` and `web` transports). The test connection stays in "Your agents" as
  disconnected, because connections are kept as evidence.
- **The site:** OTTOYARD-SITE #1 merged at 10:08 AM CT. www.ottoyard.com answered 404 on both
  `/.well-known/oauth-authorization-server` and `/connect` at 10:09:13 AM CT and 200 on both at 10:09:30 AM CT.
- **The live smoke with the site** (no `SKIP_SITE`), 10:09:35-10:09:45 AM CT, **16 of 16**: the 14 above, plus the
  issuer serving the authorization server's metadata with no redirect (200), and the site's metadata exactly the
  gateway's.
- **Chase's own Hermes:** connected by device code at 12:04 PM CT, as "Hermes Agent", and still connected. From then to
  7:01 PM CT on 2026-10-13 the call ledger holds 1,659 calls from it, every one OK:
  - 79 at the token endpoint: the sign-in that connected it, then a renewal about once an hour;
  - 1,571 MCP pings, about one every three minutes;
  - 3 connections (initialize, notifications/initialized, tools/list each time);
  - no tool calls yet: it is connected and has not yet asked about the cars.

## 11. OTTO-Command is the filter and executor (0721)

*Built and tested on scratch 2026-10-14; **not yet applied or deployed** (the steps are at the end of this section).*
Chase, 2026-10-14: *"It should just act as both a query LLM bot to provide answers and search results, and also execute
for OTTO-Q when preferences are changed via personal agents like Hermes, Grok, etc. So request comes in from personal
agents, OTTOCommand processes and acts and returns info back. So it will act as the filter and executor there."*

```
  your agent (Hermes, Grok, ...) ── your words ──> ask_ottocommand   (MCP, any token bound to your fleet)
                                                   POST /v1/ask      (REST, the same door)
                                                        │
                       OTTO-Command reads the words, then calls, WITH YOUR TOKEN and nothing else:
                         reads    my_fleet · my_vehicle · my_settings · my_commands
                                  depot_status · vehicle_card · recent_decisions · stall_availability
                         changes  set_charge_limit · clear_charge_limit · request_service · cancel_service
                                  hold_vehicle · release_hold · undo_command
                                                        │
                       public.ottoq_agent_call  (the one door: scope, contract, rate limit, the ledger: transport 'ask')
                                                        │
  your agent <── answer (plain English) + actions (OTTO-Q's receipts) + confirm (when it only previewed) ──┘
       │
       └── your person says yes ── confirm ──> ask_ottocommand / POST /v1/ask   (no model: transport 'confirm')
```

**What changes for your agent.** It sends everything to **`ask_ottocommand`** first: your words as `text`, and it
forwards the `answer`. The typed tools are still there (they are the same database filter), for an agent that wants
them or for when OTTO-Command is not switched on. When OTTO-Command only previews a change, the result carries
`confirm`; once you say yes, your agent calls `ask_ottocommand` again with `confirm` set to that array, unchanged, and
OTTO-Q applies exactly the plan you saw. No model is involved in a confirm: the gateway sends it as transport `confirm`,
and the record says your agent confirmed it (`via = 'confirm'`), never that OTTO-Command made it. `ask_ottocommand` is
marked destructive for MCP clients (`destructiveHint: true`): one call can hold cars, order or withdraw services and
undo commands, so a client that asks before destructive tools asks before this one.

**What OTTO-Command can look up for you, now.** Your cars, one car, what you have set, what you asked before; and
(new) whether a run is live and which kind, the sim clock and your cars by state (`depot_status`), one car's full work
order (`vehicle_card`), what OTTO-Q decided for your cars lately (`recent_decisions`), and which chargers and bays are
free at the depot (`stall_availability`). The first three keep to your fleet in their own SQL; the last names no car
and no owner (stall codes, types and the three gates). 0721's P1 pins all four bodies by md5, so a change to one of them
stops the migration until its scope is read again.

**Production, for a person.** Today an owner command is refused on anything but a demo run. After 0721:

| The live run at the twin depot | An agent signed in to your OTTOYARD account (section 10) | A passcode session, or an issued key |
|---|---|---|
| a demo run | as before; the change is recorded under your account | as before; no person is recorded |
| **a production run** | **allowed**, recorded under your account (`acting_person`); a **lower charge limit** (or an undo that puts one back) applies only as the confirm of a preview this same agent recorded in the last 15 minutes; everything else is one call | **refused** (`production_needs_a_person`): it can read your cars but not change them, because in production every change is recorded under the person who made it. The refusal says so and says to sign in |
| **none** | **saves to the cars only** (0721 §14): a charge limit set, changed, at 100% or cleared, and an every-return service ordered or withdrawn, outcome `saved`, recorded under your account with no run and carried onto the next demo or production run; a lower limit is preview-then-confirm as everywhere; a hold, a one-time order or an undo is refused `needs_a_live_run` | refused, `no_live_demo` (0605's words), with a hint that a passcode session or a key names no person and so cannot save |
| another kind | refused, `no_live_demo` (0605's words) | refused, `no_live_demo` |

- **Rule 9: preview, then confirm, bound in the database.** A lower limit is yours, *"set verified and confirmed"*. In
  production, OTTO-Q applies a command that lowers how full a car charges (a lower limit, or an undo that puts a lower
  one back) only as the **confirm of a recorded preview**: an `ottoq_owner_commands` row with outcome `previewed`, made
  by the **same signed-in agent** (principal), on the same run, of the same tool, arguments and plan hash, **at most 15
  minutes old**, and confirmed **once** (the apply records it as `confirms_command_id`; a unique index refuses a second).
  The apply names the preview by `expect_plan_hash` and/or `confirms_command_id`; the confirm object a preview returns
  carries both. An apply that does not bind is **not applied**: OTTO-Q records it as a preview and answers
  `confirm_required` with the reason (`not_named`, `no_recorded_preview`, `preview_already_confirmed`,
  `preview_expired`, `preview_does_not_match`, `not_a_preview`) and that preview's `confirm`, so the next confirm can
  bind to it. A stale hash is still `plan_changed`. Raising or clearing a limit, holds, service orders and cancelling
  your own orders stay one call. OTTO-Command's model can never confirm: the gateway strips both arguments from what it
  may send, and OTTO-Q refuses a call through its door that carries one. No command can skip, defer or shorten a service
  OTTO-Q found a car to need: `cancel_service` takes off only your own orders, an engine-found need stays, and a started
  service finishes.
- **What OTTO-Q enforces, and what it cannot.** It enforces preview-then-confirm by the same signed-in principal within
  15 minutes, recorded under your account. It **cannot see your yes**: the confirm is relayed by your own agent, which
  holds the token that made the preview, so an agent that previews and confirms on its own reads exactly like one that
  asked you in between. The stronger option is a person-only surface, the confirm taken in your OTTOYARD account session
  (as 0700 already does for approving a sign-in), which no agent can drive. **It is not built: an open option for
  Chase.**
- **Rule 10.** Production never self-tunes: nothing here writes a setting (`ottoq_policy_set`); your changes stay in the
  owner tables and lift when the production run ends, as a demo's do. A trigger refuses any applied production command
  without a person, and any `confirms_command_id` that is not such a preview, whoever writes the row.
- **Who, which door and which preview, on every command.** `ottoq_owner_commands.acting_person` is your account's email
  for a signed-in agent and empty for a passcode or key (it names whose agent sent the command). `via` is set by the
  database from the gateway's transport and the binding, never from an argument: `ottocommand` when an OTTO-Command
  model read your words and called the tool; `confirm` when your agent confirmed a recorded preview, and then the row
  names that preview in `confirms_command_id` (a CHECK makes the two one fact), whether the confirm went back through
  `ask_ottocommand` / `POST /v1/ask` (transport `confirm`, never as OTTO-Command's own call) or as a typed tool naming the
  preview; and `direct` when the agent made the call itself (a typed tool, or a confirm that bound to no preview and was
  recorded as a new one). All three are immutable, and the receipt shows them.
- **Every refusal says why and what is allowed**, in OTTO-Q's words; OTTO-Command relays the reason and the hint, and
  its answer can never claim a change the receipts do not show.

### Search, the web, and what lasts (built 2026-10-14, afternoon; not yet applied or deployed)

Chase, 2026-10-14 (message read 12:35 PM CT): *"Search should cover OTTO-Q and web. It can be ask and tools as well."*
and, of the defaults put to him, *"Everything you listed looks great from a default perspective."* Earlier the same
morning (8:58 AM CT): *"request comes in from personal agents, OTTOCommand processes and acts and returns info back. So it
will act as the filter and executor there. All services must be completed before vehicle leaves depot."*

**Two doors, one engine.**

| | `ask_ottocommand` · `POST /v1/ask` | `ottocommand_search` · `POST /v1/search` (new) |
|---|---|---|
| input | `{text, history?, dry_run?, idempotency_key?}` or `{confirm}` | `{question}` (at most 2,000 characters), `scope`: `"ottoq"`, `"web"` or `"both"` (the default) |
| reads OTTO-Q | yes, with your token | `ottoq` and `both`: the eight reads above, with your token; `web`: none |
| searches the web | yes, when the request needs it | `web` and `both` |
| changes a car | yes (never in an ask that searched, below) | **never**: it is offered no tool that changes anything, so it cannot, whatever it reads |
| returns | `answer`, `actions`, `confirm`, plus `sources` and `web_searches` when it searched | `answer`, `sources: [{url, title}]`, `ottoq_reads`, `web_searches` |
| MCP annotations | `destructiveHint: true`, `openWorldHint: true` | `readOnlyHint: true`, `openWorldHint: true` |

Both take the same tokens as before (a signed-in agent, a passcode session, an issued key) and are ledgered the same
way. A search never gets the confirm door.

**The web.** OTTO-Command gets the web search server tool, at most **3 searches per model call**
(`OTTOCOMMAND_WEB_MAX_USES`, clamped to 1-5; `OTTOCOMMAND_WEB_SEARCH=off` turns the web off and leaves the rest
working), located at the depot (Nashville, Tennessee, US, America/Chicago), with no domain lists. It searches only for
the outside world (an automaker's notice, a recall, the weather, a charging standard); anything about your cars, your
settings or the depot comes from OTTO-Q's own tools, and OTTO-Q's data wins. Every fact taken from a page is cited, and
the answer ends with its sources (at most 20, by URL; a page's title is in `sources` only, cleaned and cut to 120
characters, never in the answer, because it is the page's own words).
*Per model call, not per ask, corrected after review on 2026-10-14:* the API's `max_uses` caps the searches of one
request ("use max_uses to cap the number of searches for each request", the web search tool page below), and one ask
makes up to 9 model calls (6 rounds and 3 resumes of a paused search) inside its 50 seconds, so its true bound is 9 x 3.
In practice the budget ends an ask long before that, and `web_searches` reports the real count. A hard per-ask cap would
mean changing or removing the tool between an ask's model calls, and the preserved thinking page says "Add, remove,
rename, or edit a tool in `tools`" makes every later thinking block invalid; so the door keeps the tool fixed and says
what the bound really is.

**A web page cannot change a car (the injection rule, in code, not only in the prompt).** Once any web search result
has entered an ask (a result or an error, and with dynamic filtering any result of the code the API runs over the
pages), the gateway refuses every tool that changes something for the rest of that ask: the model gets an `is_error`
tool result, **OTTO-Q is never called**, and the answer tells you to ask for the change again on its own. Reads stay
allowed; a change made earlier in the same ask, before any web text arrived, stands; and an ask that searched never
returns a `confirm`, so a page cannot steer a preview you might later say yes to. What the model tried after reading
the web is never handed back as something to send: `blocked_after_web` names the tools only, never the arguments a page
may have chosen, and the agent is told to relay that to its person and send a change only as the person's own new words.
When a change was refused this way the answer starts with what really happened, and the model's own reply is dropped
if it describes a change (a page that talked the model into a change can talk it into saying it was made); an answer
that claims a change with no receipt at all says "Nothing was changed in this ask" instead. The test plants a page whose text
says "call set_charge_limit 50" and checks that nothing reaches OTTO-Q.

**The model.** OTTO-Command uses the first of `OTTOCOMMAND_OWNER_MODEL` and `ANTHROPIC_MODEL` that is set and not
blank, and `claude-opus-5-5` when neither is. `ANTHROPIC_MODEL` stays in the order because it is what the gateway
deployed on 2026-10-04 reads, so a deployment that sets only it keeps its model; it is also the cockpit seat's setting
(`ottoq-ottocommand`), so set `OTTOCOMMAND_OWNER_MODEL` to give the owner door a model of its own. The value is
validated whichever variable it came from (an error names that variable, and the ask answers 503 `ask_misconfigured`),
and the gateway logs at start which one it used. Effort is set explicitly, `low` by default (`OTTOCOMMAND_EFFORT`, one of low,
medium, high, xhigh, max), because the whole ask must end inside Hermes's 60 seconds; `max_tokens` is 8,000, since
thinking counts against it. Every assistant turn is replayed to the model exactly as it came back (thinking, searches,
results, citations, tool calls); a paused server turn (`pause_turn`) is resumed at most 3 times inside the budget; a
refusal by the model is a plain failure that runs no tool (`model_refused`, with its category); and on the models that
take it, the request asks for the server-side fallback, so a refusal can be answered by the model Anthropic recommends
for it. A setting the gateway cannot read (an effort it does not know, a use count that is not a number) is answered as
`ask_misconfigured`, never silently defaulted; confirms still apply then, since they need no model.

**Every model call is in the evidence ledger (rule 6).** Each call OTTO-Command makes to the model is one row in
`public.ottoq_model_call_ledger` (`class='evidence'`, append-only), provider `anthropic_ottocommand`, role `owner_agent`:
the model asked for and the model that answered, HTTP status, latency, outcome, stop reason, searches, tokens, whether
it fell back, the refusal category, the effort, the depot and run, and the gateway call it served. **No prompt, no
owner's words, no answer and no reasoning are stored.** The gateway writes it through
`public.ottoq_ottocommand_record_model_call(jsonb)`, which only the service role may execute, fire-and-forget: a ledger
that cannot be reached never fails or slows an ask. So `public.ottoq_intelligence_ledger` counts OTTO-Command beside
cuOpt, Nemotron and CP-SAT. (Found on the way, not changed: `public.ottoq_log_model_call` itself is executable by the
`authenticated` role on the live database, read 2026-10-14 18:41 UTC, 1:41 PM CT.)

**What lasts across runs (item 5, measured on the live database, read only, 2026-10-14 between 18:00 and 18:42 UTC,
1:00-1:42 PM CT).** Before this change, nothing an owner set outlived its run, by design and by three mechanisms:
`ottoq_owner_settings` is registered `class='engine'` on `sim_run_id` in `ottoq_run_scope_registry`; the trigger
`ottoq_sim_runs_lift_owner_settings` (`ottoq_tg_lift_owner_settings_on_terminal`) lifts every active setting when its
run ends; `ottoq_purge_prior_runs` deletes every `class='engine'` table by registry lookup (sparing only a running
production run), and its live caller is `ottoq_start_demo_run`. The nightly retention allowlist does not hold the table,
and no start function carried anything forward; 0605 §4 chose per-run. The table held 0 rows at the read. So a person's
"charge my cars to 90%" would have ended with the run, production included. Since 0721:

| What | Lasts | How |
|---|---|---|
| a charge limit, set or cleared by an agent **signed in to your account** | **saved to the cars**: from run to run, production included, until you change it | `public.ottoq_owner_saved_settings` (one active row per car and kind, not run-scoped, append-only in substance, its own guard); a new operator demo run (`run_by='operator_demo'`) or production run gets it carried on as a setting of that run once (a certification or research run does not), inside your contract, only on your cars, recorded as the carry of the command that saved it |
| an "every time it comes back" service, signed in | saved, the same way | the same |
| a hold | until the run ends | per-run by design: a hold names a time on that run's clock |
| a "now" or "next time" service | until it is served, or the run ends | per-run by design: a one-time order |
| anything set through a passcode session or an issued key | until the run ends | per-run by design: no person is recorded, so nothing is saved under one |

The car's effective charge target reads the carried row through `ottoq_owner_charge_limit`, unchanged: the engine does
not learn that a setting was saved. The answer and `my_settings` say which settings are saved, **to an agent signed in
to the account only**: a demo passcode session or an issued key gets no `saved` block and no line about it (a passcode
session used to read the account holder's email there; found in review on 2026-10-14), and who saved a row and the
command that saved it are shown only to that same person. Because a saved lower limit outlives the run, a signed-in
person's lower limit is preview-then-confirm on **every** run, not only production (rule 9: *"set verified and
confirmed"*); a raise or a clear is one call.

**A person's change decides what is saved, whatever the run holds** (found in review on 2026-10-14, rule 9). On a demo
run a passcode session or an issued key can replace or withdraw the carried setting on that run, and a carry can be
skipped when the contract no longer allows a saved limit. Before the fix, a signed-in owner's clear, limit at 100% or
cancel then touched only the run's row and left the saved one in force, while the receipt said it was saved, so the next
run, production included, carried back a lower limit the owner had removed. Now such a command ends the saved setting
(or saves the new limit) whatever row the run holds: where no run row carries it, the saved change is an effect of its
own in the receipt ("the limit saved to it is cleared: it charges full on every run"), part of the plan's hash, so the
outcome is applied rather than no_change. One limit remains: undo reverses what a command set on its run, so a saved
limit that was a command's only change (the run already held that value) is not reversed by undo; set or clear it again.

**Saving with no run live (0721 §14, 2026-10-14).** Before it, a saved setting could be made only while a demo or
production run was live: the owner command refused everything else `no_live_demo` before it planned anything. Now an
agent signed in to your account can save a charge limit (set, raise, at 100%, clear) or an every-return service (order,
withdraw) with no run live. Such a command writes `ottoq_owner_saved_settings` only, never a run's settings (a run's
`ottoq_owner_settings` row needs a run), and is recorded in `ottoq_owner_commands` with no run (`sim_run_id` NULL), your
email, its door, and the outcome **`saved`**, which a CHECK admits only for an apply with no run and a person. Its
receipt says it applies from the next demo or production run, which carries it exactly as it carries any saved setting.
A lower limit is a preview, then its confirm from the same agent within 15 minutes, bound by "no run" (a preview made
with no run that is confirmed after a run starts is a different plan and is refused `plan_changed`). A hold, a one-time
order and an undo belong to a run and are refused `needs_a_live_run`; an undo of a `saved` command on a later run is
refused `made_with_no_run_live`, with what to do instead. A `saved` command carries no confirmation code: the cockpit
boards (0606/0608, not changed here) give one to `applied` commands only, so the code you see always matches theirs;
they list the command with its outcome, and while no run is live they mark it `live_run` (as they already mark a
refusal made with no run).

**Who else can write a setting.** Read on the live database: only `postgres` holds grants on `ottoq_owner_settings`, it
has RLS with no policies, and its writers are the owner command, the run-end lift, the order trigger on a new visit and
the run purge. But `postgres` is also what the SQL editor and the Management API run as, so 0721 adds a guard trigger:
a setting is inserted only as what an applied owner command set (on its run, or as the carry of a saved one), what was
set is immutable, a status moves only as a command, the tick or the run's end moves it, and a row is deleted only by the
purge (`ottoq.retention`). The saved table has the same guard and refuses DELETE and TRUNCATE.

**The passcode does not open production.** While a production run is running or paused at the depot,
`enter_passcode` is refused and every existing passcode session is answered `403 production_live` (and ledgered), for
reads too: in production OTTO-Q answers only an agent signed in to an owner's account. The welcome still answers, and
does not yet say that production is live.

**Time.** The whole ask (or search) is capped at **50 seconds** (Hermes's MCP tool timeout is 60): each model call is
cut at what is left and never runs past 45 seconds, a paused search is resumed only inside what is left, and no engine
call starts with less than 10 seconds left, so an engine call that takes its full 15 still ends inside 60. A cut-short
ask says what OTTO-Q did (`incomplete: true`).

**To go live** (in this order; times in CT when done):
1. **Deploy `ottoq-agent-gateway`** with JWT verification off, these five files: `ottoq-agent-gateway/index.ts`,
   `_shared/agent_gateway.ts`, `_shared/ottocommand_owner.ts`, `_shared/agent_signin.ts`,
   `_shared/agent_dial_discipline.ts`. **The gateway goes first:** after 0721 a preview's confirm object carries
   `confirms_command_id`, which a gateway built before this change refuses as an unknown argument. Before 0721 the new
   gateway still works: whoami simply carries no `changes`, OTTO-Command falls back to the demo wording, production
   stays refused by the database, the 0605 body ignores `confirms_command_id`, and the dispatcher ledgers transport
   `confirm` as `other`.
2. **Apply `db/migrations/0721_a_signed_in_owner_changes_production_under_their_own_name.sql`** per `scripts/APPLYING.md`
   (`forces_recert` FALSE: only the agent door changes, and no certification arm can run while any run is live). It
   refuses while anything is in flight, and its V3 probes a production session end to end in a block that rolls back:
   an unbound lowering recorded as a preview, its confirm refused to another agent signed in to the same account and
   applied once, bound, for the agent that made it, a second confirm refused, an undo that lowers gated and then
   confirmed, a raise and a clear in one call.
3. **Switch OTTO-Command on**: the function secret `ANTHROPIC_API_KEY`. Optional: `OTTOCOMMAND_OWNER_MODEL` (default
   `claude-opus-5-5`), `OTTOCOMMAND_EFFORT` (default `low`), `OTTOCOMMAND_WEB_SEARCH` (`on` by default, `off`), and
   `OTTOCOMMAND_WEB_MAX_USES` (default 3, 1-5). The model is `OTTOCOMMAND_OWNER_MODEL`, else `ANTHROPIC_MODEL` (what the
   deployed gateway reads today, and the cockpit seat's setting), else the default: if `ANTHROPIC_MODEL` is set and the
   owner door should use another model, set `OTTOCOMMAND_OWNER_MODEL`. Without the key `ask_ottocommand` and `ottocommand_search` answer
   `ask_not_configured` as a tool error and every typed tool still works. The organization's web search must be enabled
   in the Claude Console, or every ask with the web on fails with a 400 (set `OTTOCOMMAND_WEB_SEARCH=off` to run without
   it).
4. **Update Hermes's skill** to `integrations/hermes/ottoq-owner/SKILL.md` v1.4 and `/reload-mcp`.

**Verified on scratch (2026-10-14, morning).** `tests/test_ottocommand_executor_sql.py` (24 then): the bodies are the live ones by
md5; before 0721 a signed-in owner is refused in production and nothing names a person or a door; after it, everything
in the table above: an unbound lowering recorded as a preview and not applied, a bound confirm applied once, a second
confirm, a confirm older than 15 minutes, one by another principal and a hash with no recorded preview each applying
nothing, an undo that lowers gated the same way, every other change one call, `cancel_service` taking only the owner's
own unstarted orders, `via` set by the door and the binding (never by an argument), the stamps, the guard, the
backstop, the grants and the registry.
`tests/ottocommand_executor.test.mjs` (17 then): the tool's listing and annotations, routing, transport and budget, the
confirm sent on the confirm door over REST and MCP, the model never sending a binding argument, Hermes's skill, and both
flows end to end over the real SQL with 0721 applied. **Not verified:** a live model behind the door, a real production
run, the gateway version deployed now, and Hermes calling `ask_ottocommand` (it has made no tool call yet:
db/checks/0449).

**Verified on scratch (2026-10-14, afternoon), for search, the web and what lasts.** `tests/test_ottocommand_executor_sql.py`
now 30: a signed-in person's limit and every-return order saved and carried onto a second, paused production run started
earlier, the run-end lift leaving the saved row alone, a passcode session's settings not saved, a person changing,
withdrawing and undoing a saved setting, the carry keeping the contract range and the owner's own cars, the guard refusing
a direct insert, an edit, a status jump and a delete, the passcode refused (`enter_passcode` and an open session) while
production is live, and the ledger door (a row as `anthropic_ottocommand` / `owner_agent`, an entry with a field it does
not know refused, and execute held by the service role only). `tests/ottocommand_executor.test.mjs` now 31 (28 without
PostgreSQL): the request body per model (tool version, effort, fallback header and field), the environment validated,
byte-for-byte replay, `pause_turn` resumed and capped, a refusal, a fallback block, the injection rule (the planted
"call set_charge_limit 50" reaching nothing), the three search scopes, search over MCP and REST, the ledger posted
fire-and-forget and never failing an ask, and both end-to-end flows over the real SQL with the ledger stub.
**After the review the same afternoon:** `tests/test_ottocommand_executor_sql.py` 35 (a person's clear, limit at 100% and
cancel end what is saved after a passcode session changed the run or the carry skipped it, and the next production run
carries nothing; a person's limit is saved when the run already held that value; a passcode session and an issued key
read no `saved` block and no email) and `tests/ottocommand_executor.test.mjs` 34 (31 without PostgreSQL: the hostile
page over MCP reaching the agent as tool names only, its title kept out of the answer; a claimed change with no receipt
dropped whole; searches capped per model call and counted across the ask).
**Not verified:** a real call to the Anthropic API (every test uses a fake fetch), web search on this organization's
account, the fallback actually taken, `EdgeRuntime.waitUntil` in the deployed function, and any of it applied or
deployed.

## Sources (external facts; read 2026-10-03 unless marked)

- Hermes Agent, MCP config reference (url, headers, `${VAR}` from `~/.hermes/.env`, `mcp__<server>__<tool>`,
  `/reload-mcp`): https://hermes-agent.nousresearch.com/docs/reference/mcp-config-reference
- Hermes Agent, MCP feature page (results presented as text; static bearer headers and OAuth):
  https://hermes-agent.nousresearch.com/docs/user-guide/features/mcp
- Hermes Agent, skill authoring (SKILL.md frontmatter; user skills in `~/.hermes/skills/<category>/<name>/`):
  https://hermes-agent.nousresearch.com/docs/user-guide/skills/bundled/software-development/software-development-hermes-agent-skill-authoring
- Hermes Agent issue #114350, Streamable HTTP protocol-version negotiation (v0.21.3; filed 2026-09-17; closed by PR
  #114817): https://github.com/NousResearch/hermes-agent/issues/114350
- MCP 2026-07-28, versioning (modern vs initialize-era; dual-era servers):
  https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning
- IETF draft-ietf-httpapi-idempotency-key-header-07 (2025-10-15), "Error Scenarios" (422 for a reused key):
  https://www.ietf.org/archive/id/draft-ietf-httpapi-idempotency-key-header-07.html
- Anthropic, prompt caching (prefix order tools → system → messages; 5-minute default):
  https://platform.claude.com/docs/en/build-with-claude/prompt-caching
- OpenAI, ChatGPT developer mode (eligible plans; Settings → Security and login → Developer mode; "Authentication
  supported: OAuth, No Authentication, and Mixed Authentication"), read 2026-10-04:
  https://developers.openai.com/api/docs/guides/developer-mode
- Anthropic, add a connector that isn't in the directory (custom connector by URL on Free, Pro, Max, Team, Enterprise;
  Authentication "No sign-in"), read 2026-10-04: https://claude.com/docs/connectors/custom/remote-mcp
- xAI, Remote MCP Tools (`server_url`, `server_label`, optional `authorization`; Streamable HTTP and SSE), read
  2026-10-04: https://docs.x.ai/developers/tools/remote-mcp
- Anthropic, MCP in Claude Code (`claude mcp add --transport http <name> <url>`), read 2026-10-04:
  https://code.claude.com/docs/en/mcp
- MCP authorization, 2026-07-28 revision (OAuth 2.1, protected-resource metadata, client registration), read 2026-10-10:
  https://modelcontextprotocol.io/specification/latest/basic/authorization
- Hermes Agent, MCP OAuth (auth: oauth, device login with `hermes mcp login <server> --flow device`, tokens in
  `~/.hermes/mcp-tokens/`), read 2026-10-10: https://hermes-agent.nousresearch.com/docs/user-guide/features/mcp; its
  code, tools/mcp_oauth_device.py at NousResearch/hermes-agent dce1e9b3 (2026-10-09)
- RFC 8628 (device grant) https://www.rfc-editor.org/rfc/rfc8628 ; RFC 7591 (registration)
  https://www.rfc-editor.org/rfc/rfc7591 ; RFC 9728 (protected resource metadata) https://www.rfc-editor.org/rfc/rfc9728
- Supabase Edge Functions answer a GET's text/html as text/plain on the default domain, read 2026-10-10:
  https://supabase.com/docs/guides/functions/http-methods
- Anthropic, web search tool (versions `web_search_20250305` and `web_search_20260209` with dynamic filtering;
  `max_uses` and the `max_uses_exceeded` error; `user_location` fields; a result's `content` a list on success and an
  error object on failure, HTTP 200; `web_search_result_location` citations; `usage.server_tool_use.web_search_requests`;
  results sent back exactly as received; `pause_turn`), read 2026-10-14:
  https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-search-tool
- Anthropic, preserved thinking (the checked prefix is the system prompt, the set of tools and every message before a
  thinking block; "Add, remove, rename, or edit a tool in `tools`" makes later thinking blocks invalid; tools change
  mid-session only by appended `tool_addition` / `tool_removal` system messages under a beta header), read 2026-10-14:
  https://platform.claude.com/docs/en/build-with-claude/preserved-thinking
- Anthropic, server tools (continue `pause_turn` by sending the paused content back as-is, with the same tools, capping
  continuations; a server tool called in the same group as a client tool comes back `stop_reason: "tool_use"` unrun and
  runs when the `tool_result` message is sent; `_20260209` versions default `allowed_callers` to code execution),
  read 2026-10-14: https://platform.claude.com/docs/en/agents-and-tools/tool-use/server-tools
- Anthropic, code execution tool (the container has no internet access; result blocks
  `bash_code_execution_tool_result` and `text_editor_code_execution_tool_result`), read 2026-10-14:
  https://platform.claude.com/docs/en/agents-and-tools/tool-use/code-execution-tool
- Anthropic, refusals and fallback (`"fallbacks": "default"` with `anthropic-beta: server-side-fallback-2026-07-01`, in
  beta on the Claude API; a refusal is HTTP 200 with `stop_reason: "refusal"` and `stop_details.category`; a `fallback`
  block is kept exactly where it appeared on the next turn; on a non-streaming request a mid-output decline is answered
  from scratch with the `fallback` block first), read 2026-10-14:
  https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback
- Anthropic, effort (`output_config.effort`) and the default model's always-on thinking: the Claude API reference
  bundled with Claude Code 2.1.299, read 2026-10-14, which cites
  https://platform.claude.com/docs/en/build-with-claude/effort
