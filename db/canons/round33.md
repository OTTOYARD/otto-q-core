# Round 33 — the round that failed, and should have

**Six pairs, flagship depot, 2026-09-09 08:10–09:26 UTC (3:10–4:26 AM CT).**
The first round above the `07:56:05.981718` floor that `0244` and `0245` set.

## The prediction, committed before the evidence

Written into the round-33 check-in at 07:56 UTC, before any pair fired:

> six of six pass; `fp` moves again on every column; `endst` moves on every column
> (`0244` gave it a `world` key); and `h_evt` / `h_dec` / `h_bkg` / `h_nrg` / `h_rule` /
> `h_sdr` stay IDENTICAL to round 32 … **If any of those six engine atoms moved,
> `0244` or `0245` did more than intended — investigate before writing anything down.**

## Verdicts

| fired | column | status | atoms differing **between arms** |
|---|---|---|---|
| 08:10 | `busy_day/314159/12t` | **FAILED** | `endst` |
| 08:24 | `busy_day/171717/12t` | **FAILED** | `endst` |
| 08:38 | `normal_day/171717/12t` | **FAILED** | `endst` |
| 08:52 | `busy_day/424242/12t` | **FAILED** | `endst` |
| 09:06 | `busy_day/171717/24t` | **FAILED** | `endst` |
| 09:26 | `busy_day/424242/24t` | **FAILED** | `endst` |

**Six of six failed. The prediction is falsified.** Not one engine atom moved —
`h_evt`, `h_dec`, `h_bkg`, `h_nrg`, `h_rule`, `h_sdr`, `h_prop`, `h_defr`, `h_cal`,
`h_cmd`, `ticks` and `fp` all agreed between arms on every column. Only `endst`.

## Cause: a migration I wrote three hours earlier

`0244` put `ottoq.ottoq_world_fingerprint` inside `endst`. That fingerprint hashes
`vehicles.config` stripping exactly one key — sound at boot, where the reset leaves
config free of run-scoped ids, and unsound at end-of-run, where config has gained
`service_manifest_meta` and friends.

Measured on the 08:10 pair, from the two arms' own event streams:

```
distinct config.service_manifest_meta.visit_id, arm A    116
distinct config.service_manifest_meta.visit_id, arm B    116
shared between the arms                                    0
```

One per vehicle, disjoint by construction. `endst` could not agree on any column, ever.

Full write-up: `db/checks/0161`. Fix: `0246` (`20260909094627`), verified on the
0153 grid fixture — same seed, same function, one migration apart:

| | before `0246` | after `0246` |
|---|---|---|
| outcome | failed | **passed** |
| `endst.world` arm A | `3d6d645a…` | `4926be34…` |
| `endst.world` arm B | `80b55a0c…` | `4926be34…` |

## The judgement

**Round 33 is void as a certification and valuable as a test.** It certified
nothing — no canon survives it — but it caught a defect in the harness within
three hours of that defect being introduced, on the first round that could
possibly have seen it. That is the instrument working.

The mistake underneath it was mine and it was doctrinal, not technical.
`CLAUDE.md` 2.9a requires a new atom to be **MEASURED** first and **ENFORCED**
only after a flagship round shows the arms agree. `0244` added a new *component*
to `endst`, an atom already enforced, so it went straight into the equality list
with no measured round in between. The reasoning that made that feel safe — *I am
reusing a fingerprint that already exists and is already probe-justified* — is
precisely the reasoning the doctrine exists to interrupt.

Had `0244` added the `world` key as MEASURED, round 33 would have passed six of
six and reported a disagreement on one measured sub-key, and the fix would have
cost one recert instead of two.

**Three recerts in one night; two of them bought by this error.** Round 34 earns
the canons above the `09:46:27` floor, and `0193`'s bar of two consecutive
agreeing rounds still applies after that.
