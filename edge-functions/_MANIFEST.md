# OTTO-Q-CORE — EDGE FUNCTION MANIFEST

Supabase project `gxdrcyphqjzjsuhxuqtg` (otto-q-core). Read-only snapshot.

- **Captured:** 2026-09-19
- **Previous snapshot:** 2026-08-03
- **Live ACTIVE functions:** 28
- **Changed since 2026-08-03:** **6 — and every one is on the agent/solver/twin loop**

## ⚠️ READ THIS BEFORE TRUSTING A COPY IN THIS DIRECTORY

**Six on-disk copies are STALE against what is deployed.** This was found while
tracing G66 (the rank-0 proposer never fires): the repo's
`ottoq-orchestrator-agent/index.ts` ends its solver handoff with
`EdgeRuntime.waitUntil(fetch(...))` — fire-and-forget, failures only
`console.error`'d — and can emit only `status: "queued" | "disabled" |
"gate_error"`. The **deployed** v26 `await`s the bridge and emits
`"completed" | "fallback" | "failed"` with `engine` and `fallback_reason`.
Every live agent decision on run `dde654cc` records
`{status: "fallback", engine: "cuopt", fallback_reason: "CP-SAT service is not configured"}`
— **a shape the repo's copy cannot produce.** Anyone reading the repo to
understand the agent→solver handoff reads code that is not running.

The deployed version is NEWER and better in both cases. The repo is behind.

**These six were NOT hand-synced, deliberately.** Transcribing ~400 lines of
deployed TypeScript out of an API response risks a silent one-character
divergence, and a copy that *looks* synced is more dangerous than one that is
labelled stale. They must be pulled with the Management API
(`GET /v1/projects/{ref}/functions/{slug}/body`) and verified against the
`sha256` below before being committed. Tracked as **G67**.

| Function | Deployed v | verify_jwt | Deployed (UTC) | Repo copy | Deployed sha256 |
|---|---:|---|---|---|---|
| ottoq-cpsat-propose | 5 | false | 2026-09-17 00:26 | **STALE — not in the 08-03 snapshot at all; repo returns HTTP 500 `"CP-SAT bridge is not configured"`, deployed returns 200 + cuOpt fallback** | `d46f3edc0a96524f96fa7257d7141d496a302b5fb4e139f485a3481d1b9cb11f` |
| ottoq-orchestrator-agent | 26 | true | 2026-09-17 00:23 | **STALE — repo is fire-and-forget `waitUntil`; deployed awaits and records fallback** | `1626cc71f05d05176a20c880ed27bab97c5ff1177c63cadda3467f6a9c6faf37` |
| otto-twin-control | 24 | false | 2026-09-16 18:06 | **STALE — not re-read; this is the Twin start door** | `dcf430dcc1a6ab4f4c1d738a6c1e1481eedc48a73243d99a318a0bd7a5ce0603` |
| ottoq-cuopt-propose | 29 | true | 2026-09-16 00:10 | **STALE — not re-read; this is the proposer doing 100% of live assignment work** | `71181a5d1216b7b18f5d459f6a749d8175343b4cc3678036c130698cf7756b94` |
| ottoq-orchestrate-tick | 12 | true | 2026-09-09 03:42 | **STALE — not re-read** | `645251b19f7654778691ccc533f92db17f00fc20c908add729d8fa8e53b01c20` |
| ottoq-assign-optimize | 8 | true | 2026-09-09 03:41 | **STALE — not re-read** | `4adf545e0e3170b76b7c8ecc32c5637a3ef5e41b3c413ba4ca1e21987e2e001a` |

### Unchanged since the 2026-08-03 snapshot (22)

`updated_at` predates the previous snapshot, so the committed copies stand.

| Function | Deployed v | verify_jwt | Deployed (UTC) |
|---|---:|---|---|
| ottoq-cuopt-lp-probe | 8 | true | 2026-08-01 17:43 |
| ottoq-approval-copilot | 4 | true | 2026-07-25 01:46 |
| ottoq-ingest | 12 | true | 2026-07-23 19:00 |
| ottoq-webhook-echo | 4 | false | 2026-07-20 22:30 |
| ottoq-run-blackbox | 5 | false | 2026-07-18 00:23 |
| ottoq-energy-mpc | 4 | false | 2026-07-15 04:33 |
| ottoq-benchmark-run | 7 | true | 2026-07-11 15:55 |
| ottoq-feed-agents | 6 | true | 2026-07-09 18:31 |
| ottoq-twin-ingest | 6 | true | 2026-06-27 19:03 |
| ottoq-ottocommand | 8 | true | 2026-06-27 18:47 |
| ottoq-jobs-request | 6 | true | 2026-06-19 13:49 |
| ottoq-wave-admit | 5 | true | 2026-06-19 13:17 |
| ottoq-jobs-active | 5 | true | 2026-06-19 12:41 |
| ottoq-depot-resources | 5 | true | 2026-06-19 02:57 |
| ottoq-fleet-vehicles | 5 | true | 2026-06-19 02:56 |
| ottoq-cleaning-cadence | 7 | true | 2026-06-18 18:21 |
| ottoq-sequence-optimize | 9 | true | 2026-06-18 18:19 |
| ottoq-amend | 9 | true | 2026-06-18 04:24 |
| ottoq-progress | 9 | true | 2026-06-18 04:05 |
| ottoq-energy-optimize | 8 | true | 2026-06-17 01:33 |
| ottoq-nemotron-copilot | 12 | true | 2026-06-06 15:41 |
| otto-q-api | 26 | false | 2026-04-19 01:54 |

## THE PREVIOUS SNAPSHOT'S `version` COLUMN WAS NOT COMPARABLE, AND THAT MATTERED

The 2026-08-03 table recorded `ottoq-wave-admit` at **version 2** deployed
2026-06-19. Live it reads **version 5** with the *same* `updated_at`
of 2026-06-19 13:17 — the function was not redeployed, so the two numbers are
measuring different things. Nearly every row disagrees the same way, which means
**diffing this column against a previous snapshot reports ~26 of 28 functions as
changed when 6 changed.** That is a drift detector with a 77% false-positive
rate, which is the same as no detector.

`updated_at` is the reliable signal and is what the 6-vs-22 split above uses.
`sha256` is better still and is now recorded, so the next snapshot can compare
content rather than a counter. The old note claiming "a changed version between
snapshots is proof the function was redeployed" is withdrawn.

## NOTHING DETECTS THIS AUTOMATICALLY

`scripts/check-drift.sql` covers database objects only. No test, no CI job, and
no script compares deployed edge-function source to this directory — which is why
the loop-critical copies drifted for 47 days unnoticed while the repo was the
thing being audited. See G67.

---

## Historical: the 2026-08-03 snapshot, left as the point-in-time record it is

| Function | Version | verify_jwt | Last deployed (UTC) | Status |
|---|---:|---|---|---|
| otto-q-api | 23 | false | 2026-04-19 | unchanged |
| otto-twin-control | 18 | false | 2026-07-12 | unchanged |
| ⭐ ottoq-cuopt-propose | **25** | true | 2026-08-03 | REDEPLOYED (v19→v25 since July) |
| ⭐ ottoq-cuopt-lp-probe | 5 | true | 2026-08-01 | NEW — retired 410 no-op |
| ⭐ ottoq-orchestrator-agent | 16 | true | 2026-08-01 | REDEPLOYED (Nemotron `Math.round` dial fix) |
| ⭐ ottoq-approval-copilot | 1 | true | 2026-07-25 | NEW since July snapshot |
| ⭐ ottoq-ingest | 9 | true | 2026-07-23 | REDEPLOYED |
| ⭐ ottoq-webhook-echo | 1 | false | 2026-07-20 | NEW since July snapshot |
| ⭐ ottoq-run-blackbox | 2 | false | 2026-07-18 | NEW since July snapshot |
| ⭐ ottoq-energy-mpc | 1 | false | 2026-07-15 | NEW under `supabase/functions/` (was only in `functions/`) |
| ottoq-benchmark-run | 4 | true | 2026-07-11 | unchanged |
| ottoq-feed-agents | 3 | true | 2026-07-09 | unchanged |
| ottoq-twin-ingest | 3 | true | 2026-06-27 | unchanged |
| ottoq-ottocommand | 5 | true | 2026-06-27 | unchanged |
| ottoq-orchestrate-tick | 8 | true | 2026-06-24 | unchanged |
| ottoq-jobs-request | 3 | true | 2026-06-19 | unchanged |
| ottoq-wave-admit | 2 | true | 2026-06-19 | unchanged |
| ottoq-jobs-active | 2 | true | 2026-06-19 | unchanged |
| ottoq-depot-resources | 2 | true | 2026-06-19 | unchanged |
| ottoq-fleet-vehicles | 2 | true | 2026-06-19 | unchanged |
| ottoq-cleaning-cadence | 4 | true | 2026-06-18 | unchanged |
| ottoq-sequence-optimize | 6 | true | 2026-06-18 | unchanged |
| ottoq-amend | 6 | true | 2026-06-18 | unchanged |
| ottoq-progress | 6 | true | 2026-06-18 | unchanged |
| ottoq-energy-optimize | 5 | true | 2026-06-17 | unchanged |
| ottoq-assign-optimize | 4 | true | 2026-06-17 | unchanged |
| ottoq-nemotron-copilot | 9 | true | 2026-06-06 | unchanged |

## Notes worth reading before the diff

- **`ottoq-cuopt-propose` is at v25** (July snapshot had v19–v22). v25's change is confined
  to how charger *health* is read: `station_state` is treated as a fault signal only
  (`Faulted`/`Unavailable`), not as an occupancy mirror, and a stale heartbeat now degrades
  to the usable set instead of zeroing the depot's supply. Occupancy is still read from the
  stall. It only *proposes* — enactment is still gated by `ottoq.ottoq_validate_assignment`
  and the `ottoq_stall_bookings_no_overlap_v3` EXCLUDE constraint.
- **`ottoq-cuopt-lp-probe` is a deliberate 410 no-op.** It was re-armed on 2026-08-01 to
  establish the NVIDIA hosted-LP contract, then re-retired the same day because it made
  billable NVIDIA calls and was reachable with the public anon key. It must stay inert
  unless re-armed for a bounded diagnostic window.
- **`verify_jwt: false` on 5 functions** (`otto-q-api`, `otto-twin-control`,
  `ottoq-energy-mpc`, `ottoq-run-blackbox`, `ottoq-webhook-echo`). Three of those do their
  own auth (`ottoq-energy-mpc` uses `x-bridge-token`, `ottoq-webhook-echo` uses an HMAC
  signature); `otto-twin-control` has its service-role gate deliberately DISABLED for demo
  mode, with a hardening TODO in-source.
- **No function was removed** since 2026-07-13 — every directory already in the repo maps
  to a live ACTIVE function.
- `functions/ottoq-energy-mpc/index.ts` (the old top-level path) is retained. It differs
  from the deployed source only by an extra local comment block; the deployed text now
  lives at `supabase/functions/ottoq-energy-mpc/index.ts`.
