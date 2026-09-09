# R-12 — cuOpt's capability envelope beyond routing

**Filed 2026-09-08 by Claude Code as R-10; renumbered to R-12 the same day.** R-10 and R-11 were already taken in `docs/research/answers/` and I checked only `requests/` before choosing the number. Hermes caught it and answered as R-12. Not blocking: the A/B harness that would
measure any proposer is being built regardless, and this answer changes which
architecture that harness eventually tests, not whether it gets built.

## Why this is being asked

`CLAUDE.md` 2.5 states that "cuOpt's strength is routing/LP-scale" while OTTO-Q's
site model (2.3) is a **resource-constrained flexible flow shop** — disjunctive
service points plus cumulative resources plus a shared site power cap. Those are
different problem shapes, and OR-Tools CP-SAT is named as the stronger candidate
for the second.

The live ledger says cuOpt is barely exercised: across **15,250 gate decisions
between 2026-08-02 and 2026-09-08, the NVIDIA endpoint was called 16 times**, all
on 29–30 August, returning 136 proposals of which 27 were enacted
(`SOLVER_STATE.md` §9). Since 30 August it has been off by policy (`0152`) so the
deterministic core could be certified alone. **No A/B pair has ever been run**, so
there is no measured outcome delta in either direction, and `CLAUDE.md` rule 6
forbids claiming there is.

The architectural question now open is whether cuOpt and CP-SAT decompose —
CP-SAT scheduling **inside** a site, cuOpt routing recalls **between** sites (the
`target_site` field of the Recall Decision, 2.7, across the 18-depot / 9-city
dataset). That decomposition is either *forced* by cuOpt's API surface or *chosen*
by us, and which one it is changes how the choice should be documented and
defended.

## Questions, in order of usefulness

1. **Does NVIDIA cuOpt expose any model primitive for CUMULATIVE RESOURCE
   constraints** — a shared capacity consumed concurrently by overlapping
   activities (our site power cap in kW)? Name the primitive and the cuOpt
   version, or state that it does not exist.

2. **Does cuOpt express DISJUNCTIVE MACHINE scheduling** — a set of activities
   that must not overlap on one resource, with sequence-dependent minimum gaps
   (our DCFC cooldown, 18 min on the service point)? Name the field or state
   its absence.

3. **What are cuOpt's actual solver families as of its current release?** We
   believe routing/VRP and LP/MILP. If there is a scheduling family, name it and
   its version. If cuOpt is routing-and-LP only, say so plainly — that is the
   most useful possible answer.

4. **Is there a documented, vendor-supported pattern for handing a cuOpt
   solution to a CP solver as a warm start** (or the reverse)? We are not
   asking whether it is a good idea — only whether a supported interchange
   format or worked example exists. A URL to a specific document is worth more
   than a summary.

5. **What does cuOpt's determinism guarantee say, precisely?** Our entire
   certification rests on byte-identical output under a fixed seed. Does cuOpt
   guarantee identical solutions for identical input plus seed, across runs and
   across GPU/driver versions? Quote the guarantee if one exists; if the docs
   are silent, say they are silent rather than inferring.

## What is NOT being asked

Do not evaluate whether we should use cuOpt, or benchmark it against CP-SAT.
That is an A/B experiment against our own substrate under common random numbers,
and it is ours to run. This request is about **capability and guarantees as
documented by the vendor**, nothing else.

## Answer format

`docs/research/answers/R-10-cuopt-capability-envelope-beyond-routing.md`. Per
question: the answer, the cuOpt version it applies to, and the source URL. Where
the documentation is silent, write "not documented as of <version>" — that is a
usable answer and a guess is not.
