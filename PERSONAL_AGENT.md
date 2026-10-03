# PERSONAL_AGENT: your own agent sets what your cars need

*Written 2026-10-02, 7:45–9:45 PM CT (2026-10-03 00:45–02:45 UTC). Everything here is **committed, not applied, not
deployed**: migrations `0605` and `0606` are `PENDING`, `0559`/`0560` (the agent gateway they extend) are `PENDING`,
and the edge function `ottoq-agent-gateway` has never run on the platform. Section 9 says exactly what was and was not
verified. Section 7 is the go-live list, and every step on it is Chase's call.*

Chase, 2026-10-02: *"When I make an agent proposal or query from my Hermes agent to Orchestra through OTTO-Command, it
should pull or feed into OTTO-Q and if it's a query just come back with plain English on the information regarding my
Tesla, vehicle or fleet. And if it is a command or adjustment to the fleet, such as change all Tesla maximum charging
parameters to 90% instead of 100% ... that adjustment should be made into the OTTO-Q vehicle settings for those
specific vehicles only. It should then communicate back a confirmation ... this has been accepted and is visible now
within your orchestra app with a link."*

That is what this builds. Your agent can ask about your cars in plain English, and change what they **need**: how full
they charge, which services they get, and a time before which they may not leave. OTTO-Q checks every change against
your contract and its own rules, applies it at its next tick, answers with a plain-English receipt and an OrchestrAV
link, and puts everything back when the demo run ends.

```
  you, on Telegram ──> Hermes (your agent, your token)
                          │  MCP tools (recommended)  ·  POST /v1/ask (your words, as you said them)  ·  REST
                          v
                  ottoq-agent-gateway ── OTTO-Command (/v1/ask only): reads your words, calls the same tools
                          │                 with YOUR token, so it can do nothing your token could not
                          v
                  public.ottoq_agent_call ── your token → you → rate limit → capability → the tool → the ledger
                          │
                          ├─ reads:    my_fleet · my_vehicle · my_settings · my_commands
                          └─ commands: write your settings and a receipt (ottoq_owner_settings / ottoq_owner_commands)
                                          │
                  OTTO-Q's next tick ─────┘ re-targets your cars, adds or removes YOUR service orders, honours holds
                          │
                  OrchestrAV ── the receipt's link: your fleet, what you set on every car, the receipt on top
```

**Three authorities, and none crosses into another.** You (through your agent) decide **what** your cars need. OTTO-Q
decides **when and where**. The car's own driving system decides **how it moves**. Nothing your agent sends moves a
car, assigns a stall or charger, or puts one car ahead of another owner's.

---

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

- **Your cars only.** The token is bound to Tesla Robotaxi TN at the twin depot; every other car reads as not found.
  Waymo and Zoox cars cannot be named.
- **Demo runs only.** Settings apply to a live `operator_demo` run at the twin depot, and end with it (section 4).
  With no demo live, a command is refused with *no_live_demo*.
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

Every command answers with a **receipt**: `outcome` (`applied`, `previewed`, `no_change`, `refused`), a plain-English
`summary` in OTTO-Q's own words, the `link`, and an `undo`. From the scratch rehearsal (four stub cars):

> Done. All 4 Teslas charge to at most 90% instead of 100%.
> \- 1 is charging and will stop at 90%
> \- 1 already has enough charge for 90%
> \- 1 is out; it charges to 90% when it next comes in
> \- 1 is charging past 90%: its charge ends at the next tick
> This lasts until the demo run ends or you undo it.
> See it in OrchestrAV: https://ottoyard-orchestra-av.lovable.app/?source=agent&run=…&owner=…&tab=fleet&command=…

The link opens OrchestrAV as your fleet, on the Fleet tab, with that receipt on top and where it stands now (in force,
undone, refused, or lifted with its run). Every car card shows what your agent set, e.g. "Max 90% · your agent". A
"Set by your agent" panel lists everything in force and every command. Screenshots: OrchestrAV
`docs/screenshots/2026-10-03-owner-agent/` (OTTOYARD/ottoyard-OTTO-Q#32).

**Times.** Receipts say "7:00 AM sim time" for the simulation's clock and "9:24 PM CT" for real time, both Nashville
time. A hold's time is on the sim clock.

## 4. The reset

You asked for demos that start clean: *"any agent adjustments that are accepted during a test run should automatically
reset when I stop the current simulation run and reset the entire twin simulation."* When a run ends, for any reason, a
trigger on `ottoq_sim_runs` **lifts every owner setting** and puts each car back to its baseline target. A new run starts
with nothing in force. What survives is the record: the commands and their receipts (`ottoq_owner_commands`, class
`evidence`), each marked as lifted with its run. Saved per-car preferences across runs are the later step (section 8).

## 5. Connecting Hermes

Three ways in, all through the same gateway, all with the same token. **Use (A) and (B) together**: MCP tools for
Hermes's own reasoning, and the skill to teach it the etiquette. (C) is the plain-English door when you want OTTO-Command,
rather than Hermes, to read your words.

```
GATEWAY  https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-agent-gateway
TOKEN    oqa_… (issued once, section 7 step 5; a secret: never in a chat, a repo, or a URL)
```

### (A) MCP: recommended

Hermes Agent connects to remote MCP servers over Streamable HTTP with a static bearer header, configured in
`config.yaml` with secrets read from `~/.hermes/.env` (Hermes MCP config reference, read 2026-10-03).

`~/.hermes/.env`:
```
OTTOQ_AGENT_TOKEN=oqa_...
```

`~/.hermes/config.yaml` (also at `integrations/hermes/mcp_servers.example.yaml`):
```yaml
mcp_servers:
  ottoq:
    url: "https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-agent-gateway/mcp"
    headers:
      Authorization: "Bearer ${OTTOQ_AGENT_TOKEN}"
    timeout: 60
    connect_timeout: 30
    tools:
      resources: false
      prompts: false
```

Then `/reload-mcp`. The tools appear to Hermes's model as `mcp__ottoq__my_fleet`, `mcp__ottoq__set_charge_limit` and so
on (Hermes prefixes server tools `mcp__<server>__<tool>`). The list is per token: your token sees the owner tools; a
token without a fleet never does.

**The skill.** Copy `integrations/hermes/ottoq-owner/` to `~/.hermes/skills/fleet/ottoq-owner/`. It tells Hermes when to
use OTTO-Q, to relay the receipt and the link rather than paraphrase them, to preview only when you ask, to say "sim
time" and CT, and what it cannot do (move a car). Hermes picks a skill by its description (Hermes skill authoring
guide, read 2026-10-03).

**Two Hermes notes.** Hermes hands a tool result to its model as text (Hermes MCP feature page, read 2026-10-03), so
every owner tool's result carries its plain-English `summary`, and every command's its `link`, inside that text. And an older Hermes (v0.21.3) failed
against MCP servers that answer `initialize` with an older protocol version than it asked for; that was fixed (issue
#114350, closed by PR #114817). This gateway serves the stateless 2026-07-28 revision and the 2025 initialize revisions
on one endpoint. If Hermes reports "Unsupported MCP-Protocol-Version", update Hermes. The issue's `transport: sse`
workaround does not apply here (the gateway has no SSE transport), so use (C) or REST in the meantime.

### (B) Plain English: `POST /v1/ask`

Hermes forwards your words; OTTO-Command (inside the gateway) reads them, calls the owner tools with **your** token, and
answers in plain English with OTTO-Q's receipts and the link. One call, no tool mapping on Hermes's side.

```bash
H="Authorization: Bearer $OTTOQ_AGENT_TOKEN"
curl -sS -X POST "$GATEWAY/v1/ask" -H "$H" -H "Content-Type: application/json" \
  -d '{"text":"change all Tesla maximum charging parameters to 90% instead of 100%", "idempotency_key":"tg-58213"}'
# → {"data":{"answer":"Done. All 36 of your Teslas …\nSee it in OrchestrAV: https://…","link":"https://…",
#            "actions":[{"tool":"set_charge_limit","outcome":"applied","summary":"…","command_id":"…","undo":{…}}],
#            "dry_run":false,"incomplete":false}, "meta":{…}}
```

- `dry_run: true` runs every change as a preview, **enforced in code**, and returns each plan's `confirm`. To apply
  exactly what was shown, send `{"confirm":[<those objects>]}`: no model is involved in a confirm.
- `history: [{role, text}]` (up to 12 turns) carries the conversation; it is text only, so nothing can be passed off as
  a tool result.
- `idempotency_key`: resend the same ask after a timeout and each command it made replays instead of acting twice
  (Telegram's message id is a good key).
- `answer` is held to the receipts in code: it cannot say "Done" when nothing applied, and an applied change always
  carries its link. `actions` is the authoritative record.
- It answers `503 ask_not_configured` until the gateway has a model (section 7 step 4); everything else still works.

### (C) REST, and OpenAPI for anything else

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

- **Your token is the whole key**: `oqa_` + 64 hex characters, bound at issue to one fleet, one depot, three
  capabilities (`read`, `note`, `owner_settings`), a rate limit. Only its SHA-256 is stored; a lost token is revoked and
  re-issued, never recovered. Its scope cannot be edited.
- **OTTO-Command's plain-English door cannot exceed the token.** It reaches OTTO-Q only through the gateway's own call,
  bound to the token hash; dry run, the tool set, argument checks and the step limit are code, not prompt.
- **Found while building this, and not mine to change without you (FINDINGS S-03):** the existing cockpit OTTO-Command
  (`ottoq-ottocommand`) accepts the public anon key, takes the caller's role from the request, and performs its write
  tools (energy dial, re-optimize, amend schedule, escalate, self-improve) with the service-role key. Since the cockpits
  opened their demo without sign-in, anyone who opens one can drive those. Your owner settings are **not** reachable
  that way. The fix (role from the JWT, read-only tools for anon, text-only history) is small; you set security aside
  for the demo, so it waits for your word.

## 7. Going live (each step is Chase's call; times CT; never 11 PM–6 AM CT, the sweep window)

1. **Merge** the otto-q-core PR, OrchestrAV #32 and PULSE #27 (the cockpits show "built but not switched on" until
   step 3, so they are safe first).
2. **Apply `0559`**, then (optional) **`0560`** for OrchestrAV's agent-requests panel, per `scripts/APPLYING.md` and
   AGENT_GATEWAY.md §8. `forces_recert` FALSE.
3. **Apply `0605`, then `0606`.** 0605 changes three tick-path bodies, so it is classified `forces_recert` TRUE /
   `forces_dial_restart` TRUE: **one recertification round** follows. Its V2 check proves, on the live catalog inside
   the apply, that every twin car's charge target and departure verdict is unchanged. It refuses while a pair, the recert
   runner, a dial pair or a sweep arm is running (retry a few minutes later). 0606 is the cockpit's read (FALSE/FALSE).
4. **Deploy the gateway** with JWT verification off:
   `supabase functions deploy ottoq-agent-gateway --project-ref gxdrcyphqjzjsuhxuqtg --no-verify-jwt`
   (files: `ottoq-agent-gateway/index.ts`, `_shared/agent_gateway.ts`, `_shared/agent_dial_discipline.ts`,
   `_shared/ottocommand_owner.ts`). For `/v1/ask`, set the function secret `OTTOCOMMAND_OWNER_MODEL` to the model the
   door should use (it falls back to `ANTHROPIC_MODEL`); `ANTHROPIC_API_KEY` is the key OTTO-Command already uses.
5. **Issue your token** (SQL editor; shown once; copy it into `~/.hermes/.env`):
   ```sql
   SELECT ottoq_agent_issue_token(
     'chase-hermes', 'personal', ARRAY['read','note','owner_settings'],
     '33333333-3333-3333-3333-333333333333',      -- Tesla Robotaxi TN
     '11111111-1111-1111-1111-111111111111',      -- the twin depot
     'Chase''s Hermes', 60, 20);                  -- 60 calls a minute, 20 open requests
   ```
6. **Smoke test:** `GATEWAY_URL=… AGENT_TOKEN=oqa_… node scripts/agent-gateway-smoke.mjs --ask` (the owner steps
   change nothing: a preview, not an apply).
7. **Start a demo in OTTO-TWIN**, then from Telegram: "how are my Teslas doing?", then "change all Tesla maximum
   charging to 90%". Tap the link.

## 8. What I need from you, and what is not built yet

**Questions:**
1. **Go-live:** OK to run section 7, and when (CT)? 0605 costs one recert round.
2. **Confirm before acting?** Today a clear command acts at once (preview on request, undo always). Want a confirm step
   for some changes, e.g. any limit under 90% or anything touching more than N cars? It is one rule in the door.
3. **Hermes:** which version, and does it reach `*.supabase.co` from where it runs? Tell me if it cannot use MCP and I
   will make (B) the primary path in the skill.
4. **"My Teslas":** all 36 Tesla Robotaxi TN cars at the twin depot, and the contract's 80% floor: keep both?
5. **S-03:** fix OTTO-Command's public write tools now, or leave them for the demo?
6. **Push** ("tell me when Tesla 45 is ready"): needs a Hermes webhook URL and a signing secret; designed, not built.

**Not built, on purpose:** settings that persist across runs (you asked for the reset); ready-by deadlines or priority
over other owners (a contract entitlement across tenants, not an owner setting); charger-type preference (needs a
decide-path hook); push notifications; OrchestrAV making changes itself (it is read-only until it signs owners in).

**The next steps, in order:** saved per-car preferences set from OrchestrAV with verification (your "eventually ... a
per vehicle or per asset setting ... toggled from a UI"); signed push for ready / refused / lifted; OAuth 2.1 for the MCP
connection instead of a static token (Hermes supports `auth: oauth`); OTTO-PULSE showing the crew an owner's hold and
orders on each car; a signed receipt a third party can verify.

## 9. Verified, and not verified

**Verified (2026-10-02, evening CT, on a scratch PostgreSQL 16):**
- `tests/test_owner_agent_sql.py`: 50 passed, over a stub engine whose twelve copied engine bodies match the live
  catalog by md5. Every command, the tick step, the visit trigger, the departure test, the run's end, the grants, and
  inertness without owner rows.
- `tests/owner_agent.test.mjs`: 31 passed, including the HTTP gateway over the real 0559 + 0605 + 0606 SQL end to end
  (REST, MCP, a previewed hold confirmed after the clock moved, the plain-English door with a scripted model, key reuse,
  the run's end). `tests/agent_gateway.test.mjs`: 39 passed. The full repository suite: 1,882 passed, 5 skipped.
- The gateway as a real HTTP server over that database: `scripts/agent-gateway-smoke.mjs --ask`, 11 of 11 steps, and
  your three example commands by curl (section 3's receipt is from that run).
- OrchestrAV: 207 tests, on real `ottoq_owner_board` output captured from the same scratch database.

**Not verified:** anything on the platform (deploy, real latency); a real Hermes; a live model behind `/v1/ask` (the
door was driven by a scripted model, and the Anthropic request was checked against the documented shape, not sent);
0605 against the live tick (its copies are md5-pinned, and V2 measures inertness live at apply time).

## Sources (external facts, each read 2026-10-03)

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
