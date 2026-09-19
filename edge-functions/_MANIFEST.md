# OTTO-Q-CORE — EDGE FUNCTION MANIFEST

Supabase project `gxdrcyphqjzjsuhxuqtg` (otto-q-core).

- **Captured:** 2026-09-19, by a real Management-API pull (`supabase functions
  download --use-api`), not by hand
- **Previous snapshots:** 2026-08-03, and a 2026-09-19 metadata-only refresh
- **Live ACTIVE functions:** 28
- **In sync with this directory:** **27 of 28**, verified by SHA-256 of the source
- **Out of sync:** **1 — `ottoq-energy-mpc`, and the repo copy is the correct one.**
  See the finding below; the deployed body must never be synced into the repo.

## G67 IS CLOSED, AND THE PULL CORRECTED THE DRIFT LIST IT WAS BASED ON

The six stale copies were replaced with the deployed source, pulled through the
API and written straight to disk — no transcription, which is what the previous
version of this file refused to do by hand and was right to refuse.

**And the pull disagreed with the `updated_at` signal this file had adopted.**
Measured by content hash, five functions differed, not six:

| function | `updated_at` said | hash says | |
|---|---|---|---|
| `ottoq-cpsat-propose` | changed | **differs** | correct |
| `ottoq-orchestrator-agent` | changed | **differs** | correct |
| `otto-twin-control` | changed | **differs** | correct |
| `ottoq-orchestrate-tick` | changed | **differs** | correct |
| `ottoq-cuopt-propose` | changed | identical | **false positive** |
| `ottoq-assign-optimize` | changed | identical | **false positive** |
| `ottoq-energy-mpc` | unchanged | **differs** | **FALSE NEGATIVE** |

So both drift signals this repo has used were wrong. `version` was withdrawn
earlier today at a 77% false-positive rate. **`updated_at` is better and still
wrong: two false positives and one false negative out of 28** — and the false
negative is the one function whose drift contains a live credential, because its
`updated_at` of 2026-07-15 predates the 08-03 snapshot and so looked settled.

**A drift detector that misses the one drift with a secret in it is not a
detector.** `scripts/check-edge-drift.sh` now compares SHA-256 of the source,
refuses to report a pass when it could not compare (no token, no CLI → exit 2),
and is mutation-proven in both directions: a one-line change to a repo copy is
reported as `DRIFT` and exits 1.

## 🔴 G69 — THE DEPLOYED `ottoq-energy-mpc` STILL CARRIES THE CREDENTIALS THE REPO REMOVED TWELVE DAYS AGO

This is the finding the pull exists to have found, and it was invisible to every
signal tried before it.

On **2026-09-07** this repo removed three hardcoded fallbacks from
`ottoq-energy-mpc/index.ts` and added a fail-closed guard, with a comment saying
the shared secret "is in history and must be treated as compromised regardless of
what this file says now." **That fix was never deployed.** Deployed v4, dated
2026-07-15, still reads:

```ts
const AWS_URL      = Deno.env.get("OTTOQ_INTEL_URL")    ?? "http://<internal host>:8080";
const AWS_TOKEN    = Deno.env.get("OTTOQ_INTEL_TOKEN")  ?? "<27-char shared secret>";
const BRIDGE_TOKEN = Deno.env.get("OTTOQ_BRIDGE_TOKEN") ?? "<the same 27-char secret>";
```

and it has **no** `if (!BRIDGE_TOKEN || !AWS_TOKEN || !AWS_URL) return 500` guard.
(The literals are deliberately not reproduced here. They are in the deployed
bundle and in this repo's git history, which is the whole problem.)

**Why it matters, stated at its real size and no larger:**

- This function is deployed **`verify_jwt: false`**, so `x-bridge-token` *is* the
  authentication. The default makes that token a value published in git history.
- `OTTOQ_INTEL_URL` and `OTTOQ_INTEL_TOKEN` are **unset** (that is G68), so the
  fallbacks are the values actually in force — not a dormant branch.
- The same string is both the inbound credential and the outbound `Bearer`, and
  the outbound leg is **plain `http://`**, so it crosses the network unencrypted.
- The probe response and the 502 path both echo `aws_url`, disclosing the
  internal host to any caller holding that token.

**What it does NOT do, so nobody over-reacts:** it is a fixed-target proxy. It
forwards to one hardcoded path and returns the response. It writes no database
state, takes no caller-controlled destination, and cannot reach the engine. And
`energy_mpc_follow` was set once, on 2026-07-15, on a single run scope that has
long since been purged — no current run follows this bridge.

**The remedy, and the order matters:**

1. **Rotate.** The 27-character secret is burned; it is in git history. Set a new
   `OTTOQ_BRIDGE_TOKEN` and update the twin's `pg_net` caller in the same change,
   or the bridge starts refusing its own caller.
2. **Deploy this repo's version**, which fails closed. With the intel variables
   unset it returns `500 bridge not configured` instead of proxying to a
   hardcoded host — louder, and correct.

Both are founder actions: step 1 needs a secret only Chase can set, and step 2
is a production deploy whose effect is to stop a bridge nothing currently
follows. **The repo copy is left untouched on purpose** — syncing the deployed
body into this directory would re-commit the credential and undo the 09-07 fix.

## Every ACTIVE function, measured

`match` is SHA-256 of `edge-functions/<slug>/index.ts` against the deployed
source. `sha256` is of the **deployed** file, so a future pull can be checked
against this table without trusting any metadata column.

| Function | v | verify_jwt | Deployed (UTC) | match | Deployed sha256 |
|---|---:|---|---|---|---|
| otto-q-api | 26 | false | 2026-04-19 01:54 | yes | `01762cf6734e0dd506a057a3a9ac58f09aa2acd18dc4dc23868b42c1afb9eff0` |
| otto-twin-control | 24 | false | 2026-09-16 18:06 | yes | `596f551e67ad827c8fbdb422ed86a46ec3fd3e095f4193f1d60a1a0da4dc80e6` |
| ottoq-amend | 9 | true | 2026-06-18 04:24 | yes | `70f038ae2cfdb8891f2589f2e3158cc59792f0318718963cfa9c544249b1376b` |
| ottoq-approval-copilot | 4 | true | 2026-07-25 01:46 | yes | `3abc122e20aa24a1222abe7a3bd7ce8ef6e91f78cc236b5afe2f0dc7f46293c0` |
| ottoq-assign-optimize | 8 | true | 2026-09-09 03:41 | yes | `5508a9c95d4b98e736b3215fca9cc006ae6b5e4a399de174165cad69f100c34e` |
| ottoq-benchmark-run | 7 | true | 2026-07-11 15:55 | yes | `abf1ac4718537993239bf33dc2ff29ed7a03e3f7324519c13af36a8a4a238155` |
| ottoq-cleaning-cadence | 7 | true | 2026-06-18 18:21 | yes | `e829fe2709f831e04f6eac24c89f4cfee759f99a7b5ee2033f9dd2131bff5e25` |
| ottoq-cpsat-propose | 5 | false | 2026-09-17 00:26 | yes | `544694112a505ddceb3ab9e6b0253897c0449a0fed9f3e8b954819df80759310` |
| ottoq-cuopt-lp-probe | 8 | true | 2026-08-01 17:43 | yes | `bea55aa4120f0d25fde967aa1fbcab3cdeb9f79bebef9009b77ada7dffc6d580` |
| ottoq-cuopt-propose | 29 | true | 2026-09-16 00:10 | yes | `5425ba3dcf0350d87152b497cc66c7897d4013e6227bd80fa3e6e1a7bba5ddf9` |
| ottoq-depot-resources | 5 | true | 2026-06-19 02:57 | yes | `06c303ee7662f8f8f1fcb549d7e22a8e1128b5d870863a1d652afa39171084a0` |
| **ottoq-energy-mpc** | 4 | **false** | 2026-07-15 04:33 | **NO — G69** | `42eae1f61a939ce19c9f60eef4f45a5c539f71dc5f31bec4446a1d683ab0006e` |
| ottoq-energy-optimize | 8 | true | 2026-06-17 01:33 | yes | `ef4f5240822dc6064c8051c5f4cd01daf6aeef0f59622f8eca026f60019211b0` |
| ottoq-feed-agents | 6 | true | 2026-07-09 18:31 | yes | `2b9dae37769c6babbb4401a0b936d31e0a2ebf4af48cea75ace4588d827f7bb2` |
| ottoq-fleet-vehicles | 5 | true | 2026-06-19 02:56 | yes | `a68d6444315ba0a1b5caccb568c624026a22e59bc9b90d0323890a2b5c2c2ba3` |
| ottoq-ingest | 12 | true | 2026-07-23 19:00 | yes | `ef7ae8815237ea9fb2cb0de1279f0cbaeb1c3d2df24317308e5d6ec4c4910893` |
| ottoq-jobs-active | 5 | true | 2026-06-19 12:41 | yes | `620347129158bbe913a40d97ae8d0a8bc712e0ddbc5b4d8c11c76e0a58f26ae0` |
| ottoq-jobs-request | 6 | true | 2026-06-19 13:49 | yes | `d2b25506e078d7238a49939a17a6bc4faa15f0badbe26559a859b29d1be40b2f` |
| ottoq-nemotron-copilot | 12 | true | 2026-06-06 15:41 | yes | `aca81d4358b9255508d3ca7f56a3190a117a7bafd7fd89649cfb5aa8798e155a` |
| ottoq-orchestrate-tick | 12 | true | 2026-09-09 03:42 | yes | `47bc38feb463a9c103820d087c6a86f5856a3cdc049a73ab0a76387c1a73becf` |
| ottoq-orchestrator-agent | 26 | true | 2026-09-17 00:23 | yes | `ff7ed9e0d9f3222a96f859929806a5292aba930aa4fa17763058d184f9539a35` |
| ottoq-ottocommand | 8 | true | 2026-06-27 18:47 | yes | `dac7eca5d514286ddebb97c9ba096b22adff09d97f08ec485dcfc91f49e5761a` |
| ottoq-progress | 9 | true | 2026-06-18 04:05 | yes | `eaced82147a69688e977ddede528272370c8facbe60de6787e525731090db0aa` |
| ottoq-run-blackbox | 5 | false | 2026-07-18 00:23 | yes | `0f63f9cff1bb3e2c10ab7874b80648bbf2848da9a971dbc1d163ad198a18317e` |
| ottoq-sequence-optimize | 9 | true | 2026-06-18 18:19 | yes | `eadbc4e1770a0bead8bdeb34fff2fee38d00ad1bb7089aa5d87497930860cbf7` |
| ottoq-twin-ingest | 6 | true | 2026-06-27 19:03 | yes | `569e620b37ecbf22ba9e07d042b3a97337bff58965a9f50db0233e880f393cdb` |
| ottoq-wave-admit | 5 | true | 2026-06-19 13:17 | yes | `5f0c765116c29b00340b15a46387489e350f133455cde3ed71a0f78f24d4d2f2` |
| ottoq-webhook-echo | 4 | false | 2026-07-20 22:30 | yes | `437c461e2e8f9cda27085c182543918da76ade5f13064f3c91fa590277ca9f68` |

Shared modules `_shared/agent_solver_chain.ts` and `_shared/cpsat_agent_chain.ts`
were also pulled and are byte-identical to the committed copies.

## What the four synced functions gained, and why it mattered to the audit

- **`ottoq-orchestrator-agent` 26** (+78 / −37 lines). The repo's copy ended its
  solver handoff with `EdgeRuntime.waitUntil(fetch(...))` — fire-and-forget,
  failures only `console.error`'d, able to emit only `queued` / `disabled` /
  `gate_error`. The deployed one **awaits** the bridge and emits `completed` /
  `fallback` / `failed` with `engine` and `fallback_reason`. Every live agent
  decision records `{status: "fallback", engine: "cuopt", fallback_reason:
  "CP-SAT service is not configured"}` — **a shape the repo's copy could not
  produce**, so anyone auditing the loop from the repo was reading code that was
  not running. It also iterates all three NVIDIA key names instead of taking the
  first that exists.
- **`ottoq-cpsat-propose` 5** (+9 / −3). The repo returned HTTP 500 `"CP-SAT
  bridge is not configured"` when the intel variables were unset; the deployed
  one **throws inside the try**, so the catch queues the cuOpt fallback and
  returns **HTTP 200**. That is the exact mechanism behind G66/G68 — the primary
  proposer never fires and nothing upstream notices — and it is only visible in
  the deployed body. It also adds `AbortSignal.timeout(5_000)`.
- **`otto-twin-control` 24** (+3 / −2) and **`ottoq-orchestrate-tick` 12**
  (+1 / −2): small, and now recorded rather than assumed.

## How to re-check

```bash
npm i -g supabase                       # no Docker needed; --use-api unbundles server-side
SUPABASE_ACCESS_TOKEN=sbp_... scripts/check-edge-drift.sh
```

Exit 0 = in sync (acknowledged exceptions aside), 1 = drift named, **2 = could
not check, which is never reported as a pass.** The token is a Supabase personal
access token (supabase.com → Account → Access Tokens); it is never stored in this
repo.
