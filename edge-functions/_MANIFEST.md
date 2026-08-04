# OTTO-Q-CORE — EDGE FUNCTION MANIFEST

Supabase project `gxdrcyphqjzjsuhxuqtg` (otto-q-core). Read-only snapshot.

- **Captured:** 2026-08-03
- **Previous snapshot:** 2026-07-13
- **Live ACTIVE functions:** 27
- **New since 2026-07-13:** 5 (`ottoq-energy-mpc` moved under `supabase/functions/`, plus 4 that were never in the repo)
- **Redeployed since 2026-07-13:** 8 (marked ⭐ below)

`version` is the platform's deploy counter — it increments on every deploy, so a changed
version between snapshots is proof the function was redeployed. `verify_jwt` is the
gateway auth setting: `true` requires a Supabase JWT (the publishable anon key satisfies
it); `false` means the function is open at the gateway and must do its own auth.

Functions whose `updated_at` predates 2026-07-13 were re-pulled or verified against the
committed copy and are byte-identical — `otto-q-api` was re-pulled in full and produced
no diff, confirming the on-disk copies are current.

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
