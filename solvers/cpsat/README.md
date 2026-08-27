# solvers/cpsat — C4 deterministic-core prototype

CP-SAT (OR-Tools >= 9.15) model of the reduced canonical scenario, entering the
engine as a PROPOSER (`source='cpsat'`) under the existing right-of-first-refusal
pattern. See SOLVER_STATE.md §6 for the recommendation and the requirement map.

    pip install -r requirements.txt   # PINNED -- the version is part of a run's identity
    python3 solvers/cpsat/test_cpsat_prototype.py   # 14-test battery, all must PASS

`plan_seed424242.json` is the committed reproducibility artifact: re-running the
battery with the committed scenario must reproduce its sha256 exactly. The battery
COMPARES it and fails on drift; to change it deliberately, re-run with
`REGEN_PLAN=1` and commit the diff.

**The budget is deterministic work, not wall-clock time.** `build_and_solve` sets
`max_deterministic_time` and leaves `max_time_in_seconds` unset. CP-SAT's wall-clock
limit truncates the search wherever the machine happened to be, so the same seed on
a loaded runner returns a different plan — measured at a 1.2 s wall limit on the
canonical scenario: objective 7311 idle vs 10261 under contention. Deterministic
time counts solver work units and cuts off at the same node on any machine. Pass
`time_limit_s` only if you genuinely need a wall-clock ceiling; the plan then
reports `repro.reproducible = False` unless it proved OPTIMAL. See SOLVER_STATE.md
§6.1.
