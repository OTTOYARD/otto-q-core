# `db/fn_current/` — a point-in-time capture, not a live mirror

**RE-MEASURED against `gxdrcyphqjzjsuhxuqtg` 2026-09-09 14:15 UTC: 7 of 35 files
match the catalog. 28 are stale. No file captures a function the catalog lacks.**

Two things moved since the 2026-09-08 measurement below, and only one of them is
a change in the world:

* **`public.ottoq_demo_metronome` was mislabelled.** Its header read `NOT IN THE
  CATALOG as of 2026-09-08`. The function is present, and its capture matches the
  catalog **byte-for-byte** — which is near-conclusive that it was never dropped,
  because a drop-and-recreate would have to reproduce the definition exactly.
  Yesterday's lookup was wrong, not yesterday's database. *How* it was wrong is
  not established here; the fix is the measurement, not a theory about it. It is
  now `VERIFIED`, and 6-of-35 was really 7-of-35.
* **Ten migrations landed (0242–0250) and the match count did not fall.** None of
  them touched a captured function. `public.ottoq_decide_tick` was already stale
  and still is: file `1cc03538…`, live `ae98f71b…`. It is the one worth naming,
  because it is the largest function in the engine and the capture predates
  `0132` — so it **lacks the site power gate**, and anyone reading the file to
  learn whether OTTO-Q refuses on the ceiling gets the wrong answer.

**The ratio has not improved, and re-labelling is not a fix.** 28 of 35 files
still hold bodies the database does not have. This directory is useful only as
dated evidence; for current behaviour, read the catalog. Every file now says so
in its own last header line, with the exact query to run.

---

*The 2026-09-08 record, left as the point-in-time statement it was:*

**Measured against `gxdrcyphqjzjsuhxuqtg` on 2026-09-08: 6 of 35 files match the
catalog. 28 are stale and 1 captures a function the catalog no longer has.**

The directory is named `fn_current` and was 17% current. That is the finding, and it is the kind
this repo keeps tripping over: a name or a header that asserts a property nobody re-measures — the
KPI baseline that was six numbers stale in the improving direction, the priors fingerprint that
verified itself, the `.Proto()` guard that read a value out of freed memory. A stale capture is
worse than a missing one, because a missing one sends you to the catalog and a stale one answers
your question wrongly.

Nothing here is deleted. Every file now says in its own header whether it matches the catalog, so a
reader who opens one file learns the truth without finding this README first:

* `-- VERIFIED AGAINST THE LIVE CATALOG 2026-09-08: body md5 == live md5 (…)`
* `-- STALE: this body is NOT what the catalog holds.` — with both hashes
* `-- NOT IN THE CATALOG as of 2026-09-08` — for the one dropped function

## The convention

Each file is `pg_get_functiondef()` output with a leading block of `--` header lines. The
`-- md5 at capture:` line pins the md5 of the **body**: the leading `--` block stripped, the rest
rstripped with exactly one trailing newline, which is byte-for-byte what the catalog returns. A
function body may itself contain `--` comments and they are inside the hash — an earlier draft of
the guard stripped every `--` line in the file and wrongly reported two good captures as drifted.

`recall/test_recall.py::test_the_captured_evaluator_matches_the_hash_its_header_pins` recomputes
every pin offline and fails if a header and its body have drifted apart. That is all a kernel test
can prove: doctrine 7 gives it no database. The body-vs-catalog half is `db/checks/0121`.

Five captures shipped with **no pin at all**. They now carry one computed from the file itself, and
say so in the header: such a pin proves only that the file has not been edited since 2026-09-08. It
is not evidence about the catalog, and it must never be read as any.

## How to refresh

Refreshing needs a Postgres connection, which the build agent does not have (its Supabase access is
the Management API, and the kernel is forbidden a database by doctrine 7). With `psql`:

```sh
psql "$OTTOQ_CORE_URL" -At -F$'\t' -c "
  SELECT n.nspname || '.' || p.proname, md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE p.prokind = 'f' AND n.nspname IN ('public','twin')"      # the drift list

psql "$OTTOQ_CORE_URL" -At -c \
  "SELECT pg_get_functiondef('public.ottoq_decide_tick'::regproc)" \
  > /tmp/body.sql                                                 # one body, byte-exact
```

Then prepend the two header lines with the md5 of the body you just wrote, and re-run the guard.
**Refresh a file only from the catalog.** Hand-editing a body to match a hash inverts the whole
point of the pin.

## The drift, 2026-09-08

### Matches the catalog (6)

| function | here | live |
|---|---|---|
| `public.cuopt_log_gate` | `80925793…` | `80925793…` |
| `public.ottoq_charge_plan_for_visit` | `51d7c228…` | `51d7c228…` |
| `public.ottoq_cuopt_first_refusal_arm` | `31bfaa66…` | `31bfaa66…` |
| `public.ottoq_release_expired_tethers` | `e94a3f04…` | `e94a3f04…` |
| `public.ottoq_run_governor_auto_stop` | `3725c0c2…` | `3725c0c2…` |
| `twin.ottoq_sim_stop_charge_session` | `d1c3c6e0…` | `d1c3c6e0…` |

### Stale (28)

These describe the engine as it stood at the capture date — for most, 2026-08-19, before migrations
0154 through 0209.

| function | here | live |
|---|---|---|
| `public.ottoq_benchmark_reset` | `44a2662e…` | `f2014058…` |
| `public.ottoq_comms_emit_telemetry` | `3dd58d87…` | `0039ae2c…` |
| `public.ottoq_cron_tick` | `0000aacc…` | `0562fbd6…` |
| `public.ottoq_cuopt_refresh` | `220ae5cf…` | `a6833217…` |
| `public.ottoq_decide_tick` | `1cc03538…` | `ae98f71b…` |
| `public.ottoq_evaluate_return_need` | `0c463ada…` | `53018872…` |
| `public.ottoq_fn_backup_enact_cuopt_batch` | `6c5969d0…` | `32fca214…` |
| `public.ottoq_is_overnight_holdout` | `32a50b18…` | `0c0a02dd…` |
| `public.ottoq_l2_optimize_assignments` | `c99394c4…` | `3d7fa12f…` |
| `public.ottoq_sim_decide_and_dispatch` | `72e5e6ad…` | `171edece…` |
| `public.ottoq_twin_snapshot` | `723d1b70…` | `2aa3f6b9…` |
| `twin.ottoq_arm_refuse_move` | `e41bd0bd…` | `477205d8…` |
| `twin.ottoq_sim_advance_charge_sessions` | `977001ed…` | `81856e3d…` |
| `twin.ottoq_sim_advance_deployed_telemetry` | `e91eb3a8…` | `7777fdcb…` |
| `twin.ottoq_sim_advance_grid` | `617a867d…` | `ca8df6bc…` |
| `twin.ottoq_sim_advance_service_flow` | `a972827d…` | `e18a4aec…` |
| `twin.ottoq_sim_advance_site_energy` | `ec6fc85a…` | `a7243c00…` |
| `twin.ottoq_sim_advance_weather_and_solar` | `d7246f7b…` | `31067dec…` |
| `twin.ottoq_sim_auto_charge_assign_tick` | `098bba55…` | `0519b29c…` |
| `twin.ottoq_sim_auto_dispatch_tick` | `f98acd97…` | `66e7bd98…` |
| `twin.ottoq_sim_bay_fault_handler` | `531b8f5d…` | `76b25476…` |
| `twin.ottoq_sim_bess_step` | `e1e1ae53…` | `22a341ca…` |
| `twin.ottoq_sim_confirm_commands` | `89c6f1fc…` | `68286608…` |
| `twin.ottoq_sim_dispatch_vehicle` | `1fdcb54c…` | `21cf1945…` |
| `twin.ottoq_sim_emit_arrival_webhook` | `11af2d80…` | `264d4600…` |
| `twin.ottoq_sim_start_charge_session` | `ee334e23…` | `4536b07e…` |
| `twin.ottoq_sim_start_run` | `a8454174…` | `96c44f49…` |
| `twin.ottoq_sim_vehicle_exception_handler` | `9cc34116…` | `f564ad9d…` |

### No longer in the catalog (1)

| function | here | live |
|---|---|---|
| `public.ottoq_demo_metronome` | `30fb5ae4…` | `—…` |

## One that is stale in a way worth reading

`public.ottoq_evaluate_return_need` is stale for a reason no refresh should erase. Migration 0206
copied that body out to `public.ottoq_recall_naive_threshold_v1` — the C9 rung ladder — and left a
dispatcher behind under the old name. So the body in that file is still **byte-exact for the live
ladder**: rename `ottoq_recall_naive_threshold_v1` back and it md5s to `0c463ada` exactly, and the
name occurs once in the definition, so the rename is the whole difference. It is a correct record of
the ladder filed under a name that now belongs to the wrapper. Its header says so, and
`recall/RECALL.md` carries the same warning, because `recall/recall_decision.py` called it "the live
`public.ottoq_evaluate_return_need`" for two migrations after it stopped being that.
