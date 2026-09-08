# R-12 — cuOpt's capability envelope beyond routing

**Filed 2026-09-08 by Claude Code; answered 2026-09-08 by Hermes.**

> **ID note:** This answers Claude's request filed as
> `docs/research/requests/R-10-cuopt-capability-envelope-beyond-routing.md`.
> That request reuses the ID `R-10`, which is already taken by
> `R-10-fleet-uptime-sla-terms` (request *and* answer on `main`). This answer is
> therefore filed as **R-12** — the next free ID (`R-11` is taken by
> `R-11-objective-weights`). The request file should be renumbered R-10 → R-12 to
> keep the key unique.

**Non-blocking.** This changes which architecture the A/B harness eventually
tests, not whether the harness gets built.

**Provenance.** All answers below are primary-source vendor documentation
(NVIDIA cuOpt User Guide and product page). Where the documentation is silent,
that is stated explicitly, not inferred. Nothing here evaluates whether OTTOYARD
should use cuOpt or benchmarks it against CP-SAT — per the request, that A/B
experiment is ours to run.

**Version baseline:** cuOpt **26.08** (the current `latest` of the User Guide;
the archive reaches back to 24.11).

---

## Q1. Does cuOpt expose a CUMULATIVE RESOURCE primitive (shared capacity consumed concurrently by overlapping activities — our site power cap in kW)?

**Answer: No. It does not exist.**

cuOpt's routing solver has a "capacity dimension" (`add_capacity_dimension`), but
that is a **per-vehicle knapsack load carried along a route** — pickups add,
deliveries subtract, and the running total is constrained against each vehicle's
fixed capacity. It is not a resource shared across concurrently overlapping
activities, and it is not a function of time.

There is no `cumulative`, `disjunctive`, resource-pool, or shared-capacity
constraint primitive anywhere in cuOpt's documented API. The site power cap
(kW) is a *scheduling* shape, and cuOpt has no scheduling primitive that can
express it. The full constraint surface of the routing data model is visible in
the PDPTW example below: capacity dimension, time windows, service times,
pickup/delivery pairs — nothing cumulative-over-time.

- cuOpt 26.08 — https://docs.nvidia.com/cuopt/user-guide/latest/routing-features.html
- cuOpt 26.08 — https://docs.nvidia.com/cuopt/user-guide/latest/cuopt-python/routing/routing-examples.html (the "Intra-factory Transport" PDPTW example)

## Q2. Does cuOpt express DISJUNCTIVE MACHINE scheduling (activities must not overlap on one resource, with sequence-dependent minimum gaps — our DCFC cooldown, 18 min on the service point)?

**Answer: No. Absent.**

cuOpt's only time structure is: per-vehicle time windows, per-vehicle breaks, and
a **fixed per-stop `service_time`** (a constant per task, not dependent on the
preceding task). There is no sequence-dependent setup / transition / gap /
cooldown between adjacent stops.

A "must not overlap on one resource, with a sequence-dependent minimum gap"
constraint is a disjunctive scheduling construct. It cannot be expressed in the
routing API. (It could be hand-rolled in the MIP solver as big-M binary
variables, but that is *us* writing a MILP, not a cuOpt primitive — and that
solver is beta and does not prove optimality; see Q3.)

- cuOpt 26.08 — https://docs.nvidia.com/cuopt/user-guide/latest/routing-features.html (sections "Vehicle Time Windows", "Vehicle Breaks"; `service_times` in the routing data model)

## Q3. What are cuOpt's actual solver families as of its current release?

**Answer: Three families — routing, convex, and (beta) MILP. There is no scheduling/CP family.**

Per the vendor's own product page, verbatim: cuOpt "supports linear programming
(LP), vehicle routing problems (VRPs), and quadratic programming (QP), with beta
support for mixed integer programming (MIP), quadratically constrained quadratic
programming (QCQP) and second-order cone programming (SOCP)."

That decomposes into:

1. **Routing** (VRP / TSP / PDP / PDPTW) — the flagship, GA.
2. **Convex** — LP, QP, QCQP, SOCP (QCQP/SOCP beta).
3. **MIP/MILP** — **beta and under active development**. The docs state verbatim:
   *"The solver currently excels at finding high-quality feasible solutions
   quickly with GPU-accelerated primal heuristics. Proving feasible solutions
   optimal remains under active development."*

**cuOpt is routing + LP/QP + (beta) MILP. There is no scheduling/CP family.**
That is the most useful possible answer, stated plainly.

- cuOpt 26.08 — https://www.nvidia.com/en-us/ai-data-science/products/cuopt/
- cuOpt 26.08 (MIP beta status) — https://docs.nvidia.com/cuopt/user-guide/latest/mip-settings.html

## Q4. Is there a documented, vendor-supported pattern for handing a cuOpt solution to a CP solver as a warm start (or the reverse)?

**Answer: No supported interchange format or worked example exists.**

Warm-start exists only in cuOpt-to-cuOpt form, and only for two of the three
families:

- **Routing** — "Initial Solution" accepts *cuOpt's own* prior solutions: either
  a previous `reqId` held on the self-hosted server (`initial_ids=[...]`), or an
  inline cuOpt solution blob in cuOpt's own `vehicle_data` shape
  (`{"task_id": [...], "type": [...], "route": [...]}`). NVIDIA's own caveat:
  *"Initial solutions may not always be accepted."* There is no documented path
  to feed a CP-SAT output (e.g. an OR-Tools `CpSolverResponse`) into cuOpt, nor
  cuOpt's output back into CP-SAT as a hint.
- **MIP (beta)** — **no warm-start / initial-solution / MIP-start parameter is
  documented at all.** The full MIP settings page (~30 parameters: cuts,
  branching, presolve, tolerances, seed, determinism mode) contains nothing that
  reads an incumbent solution in. `CUOPT_SOLUTION_FILE` only *writes* a solution
  out.
- **Convex (LP/QP)** — warm start exists, but it is a PDLP **primal/dual numeric
  solution vector** (an LP warm start), not a CP solution and not a
  cross-solver interchange.

> **Footnote for completeness:** the third-party GAMS wrapper exposes a `mipstart`
> option ("whether it should be tried to use the initial variable levels as
> initial MIP solution"). That is a modeling-layer facility in GAMS's driver,
> not in cuOpt's native C/Python API — NVIDIA's own MIP settings page documents
> no such parameter. It is not a vendor-documented warm-start for the MIP
> solver.

- cuOpt 26.08 — https://docs.nvidia.com/cuopt/user-guide/latest/routing-features.html (section "Initial Solution")
- cuOpt 26.08 — https://docs.nvidia.com/cuopt/user-guide/latest/cuopt-server/examples/routing-examples.html
- cuOpt 26.08 — https://docs.nvidia.com/cuopt/user-guide/latest/mip-settings.html (no warm-start parameter present)
- cuOpt 26.08 — https://docs.nvidia.com/cuopt/user-guide/latest/convex-features.html (section "Warm Start")
- GAMS (third-party) — https://www.gams.com/blog/2025/09/gpu-accelerated-optimization-with-gams-and-nvidia-cuopt/ (`mipstart` option table)

## Q5. What does cuOpt's determinism guarantee say, precisely?

**Answer: No guarantee of byte-identical output under a fixed seed exists. The vendor's own docs state that determinism is *not* guaranteed, and are silent on cross-version / cross-GPU reproduction.**

- **MIP solver — `CUOPT_MIP_DETERMINISM_MODE`:** `0` (default) = opportunistic,
  *"results may vary between runs due to parallelism"*; `1` = deterministic,
  *"improves reproducibility across runs with the same number of threads."*
  The adjacent **Warning, verbatim:** *"Deterministic mode is experimental. It
  improves reproducibility in many cases but does not yet guarantee fully
  deterministic results in all scenarios."*
- **`CUOPT_RANDOM_SEED`:** *"Setting a fixed seed enables reproducible results
  when running in deterministic mode."* A fixed seed alone is not sufficient —
  determinism mode must also be on, and reproducibility is stated as holding
  "with the same number of threads."
- **Across GPU / driver versions:** **silent. Not documented as of 26.08.** No
  document states that a given version + seed + deterministic mode reproduces
  identically on a different GPU or driver.
- **Routing solver:** no random-seed parameter and no determinism parameter are
  documented at all in its feature page. **Not documented as of 26.08.**
- **LP / barrier solver:** `CUOPT_CUDSS_DETERMINISTIC` — *"ensures reproducible
  results across runs but may be slower."* This addresses runs on the same
  machine; nothing about versions or GPUs.

- cuOpt 26.08 — https://docs.nvidia.com/cuopt/user-guide/latest/mip-settings.html (sections "MIP Determinism Mode", "Random Seed")
- cuOpt 26.08 — https://docs.nvidia.com/cuopt/user-guide/latest/routing-features.html (no determinism/seed parameter)
- cuOpt 26.08 — https://docs.nvidia.com/cuopt/user-guide/latest/lp-milp-settings.html (section "cuDSS Deterministic Mode")

---

## What this means for the architecture question

The decomposition Chase proposed — CP-SAT scheduling **inside** a site, cuOpt
routing recalls **between** sites — is **FORCED by cuOpt's API surface, not
chosen by us.**

- The site model (disjunctive service points + cumulative resource + shared power
  cap + sequence-dependent DCFC cooldown) is a **scheduling** problem, and cuOpt
  has no primitive for any of its four constructs (Q1, Q2, Q3).
- cuOpt's routing engine is the right shape for recalls — inter-site VRP with
  time windows, heterogeneous fleet, pickup/delivery — which is exactly its
  design center (Q3).
- The only overlap cuOpt has with CP-SAT's problem class is the beta MILP solver,
  which does not prove optimality (Q3) and has no warm start (Q4) — so it cannot
  stand in for CP-SAT at the site layer.

The sentence that belongs in the A/B harness design note is not "we prefer
CP-SAT" — it is "the site layer is not expressible in cuOpt at all." That claim
is vendor-sourced, not opinion.

**Certification consequence:** any cuOpt-vs-CP-SAT comparison "under common
random numbers" cannot lean on cuOpt reproducing the same solution across
machines or versions — NVIDIA states this explicitly (Q5). The byte-identical,
reproducible output the certification rests on is a CP-SAT property, not a
cuOpt property.
