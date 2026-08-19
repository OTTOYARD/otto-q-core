# solvers/cpsat — C4 deterministic-core prototype

CP-SAT (OR-Tools >= 9.15) model of the reduced canonical scenario, entering the
engine as a PROPOSER (`source='cpsat'`) under the existing right-of-first-refusal
pattern. See SOLVER_STATE.md §6 for the recommendation and the requirement map.

    pip install ortools
    python3 solvers/cpsat/test_cpsat_prototype.py   # 8-test battery, all must PASS

`plan_seed424242.json` is the committed reproducibility artifact: re-running the
battery with the committed scenario must reproduce its sha256 exactly.
