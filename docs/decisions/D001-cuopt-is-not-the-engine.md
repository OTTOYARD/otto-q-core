# D001 — cuOpt is not the engine. Retire it from the decide path.

**Decided 2026-09-03 CT. Four queries against the live ledger, no interpretation needed.**

## The numbers

| proposer | proposals | enacted | where it runs | latency |
|---|---|---|---|---|
| `greedy_constrained` | 12,187 | **3,983 (32.7%)** | in-process | none |
| `cuopt` (NVIDIA) | 136 | **27 (19.9%)** | network | 858–8,482 ms, avg 3,401 |
| `ottoq_service_priority` | 1,346 | **0** | in-process | none |

cuOpt has produced **27 enacted decisions in the system's entire history**. The local greedy
proposer produced 3,983 — 147× more — at zero network cost. Of 12,478 cuOpt log rows, **16**
ever got an HTTP 200.

## Why it goes, and it isn't about usage

1. **Wrong problem shape.** cuOpt is a routing/LP solver. A depot is a resource-constrained
   flexible flow shop — disjunctive machines, cumulative resources, precedence, a shared power
   cap. That is CP-SAT's home turf, and CLAUDE.md 2.5 already says so.

2. **It is in direct conflict with our credibility claim.** We spent thirteen rounds proving
   same-seed-same-output. Every one of those rounds ran with cuOpt **switched off** —
   `policy_disabled` appears 2,391 times in the log because I had to quiesce it to certify.
   An external service with 858–8,482 ms variable latency cannot be inside a deterministic
   core. We cannot certify determinism and run cuOpt in the loop. Pick one.

3. **It cannot meet a real-time tick.** A production depot issuing directives cannot wait
   8.5 seconds on a network round trip.

## The decision

- **Retire cuOpt from the decide path.** Not deleted: it stays behind the existing proposal
  interface, disabled, available for a genuinely routing-shaped problem later (multi-depot
  rebalancing across a city is routing; a single depot's flow shop is not).
- **Nothing needs to replace it.** The local decide path plus `greedy_constrained` already do
  the work — that is what the 3,983 enactments are.
- **The real upgrade is CP-SAT as a proposer** under the same deferral pattern: in-process,
  deterministic under fixed seed, correct problem shape, no network. CLAUDE.md C4 already
  scopes it.

## The claim we may make

> cuOpt was integrated as an optional external proposer and measured. Across the ledger it
> returned 136 proposals, of which 27 were enacted, at 0.9–8.5 s per call. The in-process
> proposer enacted 3,983 in the same period at no network cost, so cuOpt was retired from the
> decide path: it is the wrong solver shape for a flow shop and cannot sit inside a
> deterministic real-time loop.

That is a stronger story than the one it replaces. It says we tested a vendor claim and made
an engineering call on evidence.

**Forbidden:** "12,478 cuOpt invocations against the NVIDIA endpoint" (16 reached NVIDIA);
"cuOpt powers our optimization" (27 enacted decisions); and equally "cuOpt never worked"
(it did — it was measured and found unsuitable).

## The finding that matters more

`ottoq_ab_runs` holds 68 runs under **one policy** (`otto_q`). There is no baseline.

We cannot presently demonstrate that OTTO-Q beats anything, because nothing has been run
against it. The KPIs are trustworthy as of tonight and the core is deterministic — the missing
piece is the comparison. CLAUDE.md C5 specifies it exactly: FIFO, greedy, otto_q and CP-SAT
over common random numbers, same seed, same scenario.

**That is the next build.** "Outperform everyone on industry KPIs" is a claim about a
difference, and we currently have nothing to difference against.
