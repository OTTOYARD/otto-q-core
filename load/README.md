# `load/` — the load harness (task G24)

**The question this exists to answer.** Chase, 2026-09-08: *"we need this to be
fairly instantaneous… so if it's going across millions of rows and taking
hundreds of seconds that won't work for real time communication between our
orchestration engine OTTO-Q and a vehicle or interface."*

The honest answer at the time was that nobody knew, and that the numbers we
did have could not answer it. `db/checks/0133` separates the two clocks that
kept being confused:

- **The batch proof** — a certification pair, 358–537 s, a whole-depot double
  simulation. Nothing waits on it. It is not the vehicle's clock.
- **The live request** — 24–47 ms. But those were **lifetime means out of
  `pg_stat_statements` over 34–40 days at about 5.6 calls a minute**, and the
  counters did not move at all across 75 idle seconds. That is evidence a code
  path is fast when nothing else is happening, and **no evidence at all about
  behaviour under load, because the system has never been under load.**

This directory is how the second sentence stops being true.

## What it does that a naive load test does not

**1. It measures the floor, every time.** Before and after the target it runs
`SELECT 1` at the same concurrency on the same connection string, and reports
`engine_share_p50_ms` = target p50 − floor p50. A latency with no floor beside
it is a claim about a network nobody measured. If the floor is 22 ms, a "30 ms"
engine call is an 8 ms engine call.

**2. It looks for the certification pair.** A determinism pair is by far the
largest load this database ever sees, and `pg_stat_activity` is the only
authority on whether one is running — `db/canons/round25.md` records that an
in-flight pair reports `succeeded` in the cron log, because the command is two
statements and the row reflects the first. The harness probes before, between
the floor and the run, and after. A result that overlapped a pair is written
with `contaminated: true` and a reason. **It is kept, not discarded** — a
measurement taken while the database was busy is real data about a real
operating condition, and deleting it is how you end up with only flattering
numbers.

**3. It reports achieved rate against requested.** If the harness could not
keep up, the latency being read is the harness queueing, not the server
answering.

**4. It refuses to let a thin tail pass as a distribution.** Below 200
transactions the result carries
`tail_percentiles_are_not_measurements`, in the result file, where anyone
quoting the p99 will see it. p99 of 40 transactions is one transaction wearing
a percentile's clothes.

**5. Percentiles are nearest-rank.** Every number reported is a latency that
actually happened, so a reader can go and find the transaction. Interpolated
percentiles are respectable statistics and are not events.

## pgbench reports two latencies, and they differ by 29x

Measured while building this, on a local unix socket:

| | `SELECT 1` | `pg_sleep(20 ms)` |
|---|---|---|
| mean of pgbench's per-transaction log | **0.0004 ms** | 20.36 ms |
| pgbench's summary `latency average` | **0.011 ms** | 20.4 ms |
| its `statement latencies` line | 0.001 ms | — |
| tps | 344,298 | 194.9 |

Neither is a lie. The summary figure is **derived from throughput**
(`duration × clients / transactions`) whenever pgbench is unthrottled, so it
carries pgbench's own per-transaction overhead — the script loop, the log
write. The per-transaction log times do not. On a fast local path that overhead
*is* the number; at millisecond scale it is noise.

The harness reports the **log percentiles** as `latency`, because the question
is what the server takes, and puts the summary figure beside it as
`pgbench_throughput_derived_latency_ms`. When the gap is large **relative to
the measurement** it says so in `two_latencies_note`. Picking one silently is
how a floor ends up 29x wrong, and the floor is the thing everything else is
subtracted from.

## Calibration — why you should believe the instrument

`tests/test_load_harness.py` builds a throwaway Postgres, asks it for a
statement that sleeps a known 20 ms, and requires the harness to read 20 ms
back, with the floor beside it reading nearly zero. Measured:

```
floor    n=1,735,848  p50 0.000 ms  p99 0.012 ms   344,298 tps
known    n=984        p50 20.325 ms p99 21.441 ms      194.9 tps
engine_share_p50_ms = 20.325     (asked for 20)
```

An instrument that reads 20 ms for a known 20 ms is calibrated. The tests skip
rather than fail where the cluster cannot be built (no `initdb`, no `pgbench`,
or running as root, which `initdb` refuses), and each skip names what was
missing — a green tick from a test that silently did nothing is worse than a
skip.

## What it cannot measure, so nobody has to infer it

**The HTTP edge-function path is not measured.** `edge-functions/otto-q-api`
routes what a vehicle actually talks to — `/api/v1/av/telemetry`,
`/api/v1/av/arrival`, `/api/v1/tasks/queue`, `/api/v1/charger/*` — and that
round trip includes a gateway, TLS and cold starts that none of the numbers
here contain. It is deliberately **not implemented** rather than implemented
badly: this container reaches the internet through an agent proxy, so a number
taken from here would be a number about the proxy. `layer="http"` targets need
a host whose network path to Supabase is characterised.

**Nothing here has been run against production.** The harness needs
`OTTOQ_DB_URL`, a direct Postgres URL, which this container does not have; it
refuses to fall back to the Supabase management API, because that path cannot
do concurrency and any number from it would be about the API. So `load/results/`
is empty, and it should stay empty until the harness is run from a host that
can do the job. **An empty results directory is the honest state.**

## Running it

```sh
export OTTOQ_DB_URL='postgresql://…'          # never a flag, never a file
python3 load/harness.py --target charger_load_kw \
    --depot 11111111-1111-1111-1111-111111111111 \
    --clock '2026-09-01 14:00:00+00' \
    --clients 16 --duration 60
```

Targets are declared in `load/targets.py` — name, safety class, and a sentence
saying what product question the target represents. There is no `--sql` flag,
deliberately: a load number whose target is a command-line string is a number
nobody can reproduce or compare against the next one.

`--rate N` caps offered load; omit it to saturate. Write-class targets (there
are none yet; the class exists so the first one arrives with the guard already
around it) additionally require `--i-know-this-writes`.

Every run writes `load/results/<target>_<run-id-prefix>.json` carrying its own
`run_id`, both latencies, the floor, the pair probes and the contamination
verdict. **No number ships without a run ID** applies here exactly as it does
to the rest of the build.

## The first three things to measure, when there is a host to measure from

1. `charger_load_kw` at 1, 4, 16 and 64 clients. This is 0223's subject and
   G21's FIX 2 is still open — the surviving cost is a sequential scan of
   `ocpp_sessions` — so this is the *before* measurement for a fix not yet
   written.
2. `kpi_five`. A single call went 54.6 s → 50.9 ms in `0181`–`0190`. Whether
   that holds at concurrency has never been asked.
3. The same three, deliberately **during** a certification pair, so the
   `contaminated` result exists on purpose and the product has a number for
   "what a vehicle sees while the proof harness is running." That number is
   also the argument for G26 (separating production from the proof harness),
   and it should be measured before it is argued.
