# The magenta-layer audit: master list

87 findings from a twelve-dimension sweep of the agentic layer (`intent/`, `policies/`,
`proposer/`, `solvers/cpsat/`, and `ottoq-intelligence/app/forecasters/`), run 2026-09-07.

**These findings are UNVERIFIED.** The adversarial verification stage was cancelled on cost
grounds after the finders returned, so each item is one agent's claim with its own evidence
attached and nothing independent standing behind it. Every item is re-reproduced here before
it is fixed, and an item that does not reproduce is marked REFUTED with what was actually
found. Two were reproduced and fixed before this list existed (L-01, L-02).

Counts: 14 critical, 50 major, 23 minor.

## Findings already resolved, and the ones that did not survive contact

| id | outcome |
|---|---|
| L-01 empty charge chain takes the site INFEASIBLE | **FIXED**, reproduced first; pinned by T14 |
| L-02 rejection penalty does not dominate | **FIXED**, reproduced first; pinned by T15 |
| S-01/S-02 shared secret committed, bridge fails open | **CODE FIXED** (fails closed, no literals). Rotation is the founder's |
| S-03 intelligence service auth fails open | **FIXED**; pinned by tests/test_auth_fails_closed.py |
| G contamination guard: non-recursive, blacklist, shallow identifier scan | **FIXED**; six evasions run, all caught |
| G priors fingerprint test is tautological | **FIXED**; now tampers a copy and asserts the loader refuses |
| G `intent/` outside the separation guard | **FIXED**; `intent` added to KERNEL_PACKAGES, mutation-proved |
| G advisory guard never sees the proposer's rows | **FIXED**; both emitters generated, mutation-proved |
| D "the suite was 267, was 201 before" | **REFUTED on the count.** The suite is 267 on current main. An earlier measurement of 256 was taken before PR #176 merged; #176 added `proposer/test_orchestrate.py`. The "201 before" half is still unverified. |
| G `test_intent_tamper_is_refused` never calls the loader | **FIXED**; now loads a tampered copy and asserts the refusal. Deleting the loader's check turns it red |
| G the signal-regime precedence is unpinned | **FIXED, and it found something.** Safety-over-cost is DECLARATION ORDER, not structure: reversing the regime list makes a tariff signal outrank a grounding risk. The pack format is not redesigned here; the shipped order is now asserted against the doctrine, so a tidy-up turns CI red |
| G learn's malformed-input test passed two well-formed records | **FIXED**; passes a None code and a duck-typed record. Deleting the `isinstance(rc, str)` guard turns it red |
| G `assert r["planned"] > 0` cannot fail (`planned` counts declined rows) | **FIXED**; counts served rows. Marking every row declined turns it red |
| G T3 stays green with the site power cap deleted | **FIXED** via T3b, a cap set BELOW the free peak with the soft target raised out of the way. First attempt still passed with the cap deleted because the soft cumulative held the peak; corrected. Deleting the hard cap now reports 550 kW against a 330 kW cap |
| G the min_flow pass's peak ceiling has no test | **FIXED**; a property test measures tardiness, flow and peak FROM THE SHIPPED PLAN on both three-pass orders. Deleting the threading reports "min_peak said 150, plan measures 460" |
| G the CP-SAT battery contributes zero pytest tests | **FIXED**; a `test_cpsat_battery()` wrapper. The artifact comparison stays under `__main__` |
| L-01 learned block_points names every entity that touched the code | **FIXED**, reproduced first: one stuck point plus 58 one-off refusals blocked 59 points while the flag named 1. The constraint is now populated from the same predicate that flagged it. Deleting the threshold check turns two tests red |
| L-02 `demand_surge` structurally unreachable | **FIXED on both sides**, and the arithmetic is now pinned. Measured ceiling against a flat daily mean: shape peak 1.5956 x max dow 1.1980 = **1.9115**, under the 2.0 threshold, scale-invariant. (The audit said 1.900 from hours 17-19; the busiest 3-hour run is 16-18.) The baseline is now the window's own climatology, supplied by the forecast and refused if absent; `ottoq-intelligence` emits `baseline_arrivals` beside `expected_arrivals` |
| L-03 `complete: true` on a FEASIBLE pass | **FIXED**, reproduced first: `scenario_24h` returns `['OPTIMAL','OPTIMAL','FEASIBLE']` and reported complete at every budget from 0.05 s to 30 s. `complete` now requires every pass to have RUN and PROVED; each pass carries `proven`. Reverting the expression turns two tests red |
| L-04 per-vehicle inlet power collapsed by `setdefault` | **FIXED**, and it was worse than reported: `{'v-derated': 100, 'v-full': 100}` with the healthy unit first, `{'v-derated': 25, 'v-full': 25}` with the derated one first — wrong in both directions AND dependent on frame row order. The class is now keyed on the per-unit facts |
| L-05 empty charge chain takes the site INFEASIBLE | **FIXED** (listed above as L-01 in the pre-list resolutions); pinned by T14 |
| L-06 rejection penalty does not dominate | **FIXED** (listed above as L-02 in the pre-list resolutions); pinned by T15 |
| L-07 contamination blacklist | **FIXED**; six evasions run, all caught |
| L-08 serviceable-state vocabulary | **FIXED**, enum-verified: `awaiting_stall`, `in_queue` and `charge_scheduled` are not labels of the production `vehicle_state` type; `staged_awaiting_service` is, and was omitted. It carried 3,386 transitions across 113 of 116 flagship vehicles in 24 h, and 16 vehicles held it at the busiest sampled minute against 19 the old set could see. The enum is committed at `db/contracts/vehicle_state_enum.json` and a test asserts membership |
| L-09 no default solve budget; too slow for the one-tick seat | **FIXED, and the audit's proposed fix was not sufficient.** A default budget alone does not make the seat real: measured, a 44-vehicle/16-stall frame costs **97.9 s** at the default budget because the cost is model construction, not search. `propose()` is now always bounded (`DEFAULT_DET_BUDGET_S = 2.0`) AND takes `max_assets`, which solves the most urgent N and gives every deferred vehicle an abstention row — 44 vehicles at `max_assets=8` runs in **7.6 s** against the engine's 30-second tick. `proposer/README.md`'s seat claim is corrected with the table |
| D-01 header claims an unknown reason_code raises; it does not | **FIXED**, confirmed: `reconcile_refusals` contains no raise. All three statements (module header, REFUSAL_CODES comment, the `_diagnose` contrast) now say what the code does — an unknown code is NAMED in `unknown_codes` and makes the report dirty — and say why: one unrecognized code must not discard ninety-nine recognized ones |
| D-02 the committed 24h KPI baseline is stale and the gate hides it | **FIXED**, and the drift was six of eight guarded numbers, all in the improving direction so the gate could never trip: cpsat p95 wait 160→107, peak 307→251, makespan 1280→1228, tardy 121→112; otto_q_asis tardy 229→0, makespan 1235→1225. Rebaselined deliberately (`--rebaseline`, new sha256 `71c21bb8…`); the gate's own PASS line went back from "within thresholds" to **"byte-identical to baseline"**, and `--demo-regression` still exits 1 |
| D-03 `policies/README.md` headline table matches nothing | **FIXED**, confirmed cell-by-cell: published 621/0/340/9/636, 0/22/402/9/227, 395/74/392/9/551, 118/84/436/9/458 against an artifact holding 237/0/370/9/501, 0/13/440/9/218, 157/55/372/9/386, 0/90/550/9/270. Not one cell agreed, and cpsat's real `total_tardy_min` is 0, so "deliberately trades tardiness minutes" was false. The table is regenerated from the artifact AND is now **checked**: new gate P6 parses it out of the README and compares cell-by-cell. Restoring one stale cell turns it red |
| D-04 the CP-SAT battery size is published three ways, none right | **FIXED**; the battery counts itself (`ALL TESTS PASS — 20 checks, T1..T15`) and the hand-maintained counts are deleted from `solvers/cpsat/README.md` and the CI step name. It is 20 now, not the audit's 19, because T3b/T14/T15 landed first — which is the point |
| D-05 the module's second law says every row "expires"; none does | **FIXED**; the law now states what it is — an obligation on the caller, which `proposer/README.md` already had right — rather than a property of output this module does not give it |
| D-06 "plan_seed424242.json sha256" is the schedule digest, not the file's | **FIXED**; the battery prints `plan_sha256 2b7f40fb…, file sha256 6ea7d2af…` so `sha256sum` no longer reads as drift. The underlying comparison was always stronger than either digest: full file text, byte for byte |
| L non-serviceable vehicle gets no row | **REFUTED.** Deliberate and pinned by `test_plannable_vehicles_get_assignments_and_the_rest_abstain`; the proposer emits nothing for states it does not service, by design. |


| batch | what it is | items |
|---|---|---|
| **S** | SECURITY (code side is mine; rotation is Chase's) | 3 |
| **G** | GUARDS THAT CANNOT FAIL | 20 |
| **L** | LOGIC DEFECTS | 57 |
| **D** | CLAIMS AND DOCS | 7 |


## S — SECURITY (code side is mine; rotation is Chase's)

### S-01 · CRITICAL · `core/edge-functions/ottoq-energy-mpc/index.ts:8`
**A live shared secret is committed in the repo — the same string is both the bridge token and the intelligence-service bearer token**

`ottoq-frontier-a7f3c9d1e5b8` is hardcoded as the fallback for BOTH `OTTOQ_INTEL_TOKEN` (the
Authorization: Bearer value sent to the AWS intelligence service) and `OTTOQ_BRIDGE_TOKEN` (the
x-bridge-token that authorizes callers of the edge function). The same value is also baked into
the committed production DB dump as a DEFAULT PARAMETER of `public.ottoq_energy_mpc_replan(...
p_bridge_token text DEFAULT 'ottoq-frontier-a7f3c9d1e5b8')`, which is a dump of the live
function — i.e. this is the deployed value, not a placeholder. The AWS URL
`http://100.53.130.57:8080` is committed alongside it, over plain HTTP. CLAUDE.md/OTTO-Defense
doctrine: 'no secrets in code, ever'; ottoq-intelligence/AGEN

*Fix:* Rotate the token now (it must be assumed compromised), then: (1) delete both `?? "ottoq-
frontier-..."` fallbacks in index.ts and fail closed — `if (!BRIDGE_TOKEN) return
j({error:'server_misconfigured'}, 500)`; (2) migrate `ottoq_energy_mpc_replan` so
`p_bridge_token` has NO default and callers pass it from a Supabase secret / vault read; (3) add
the literal to a secret-scanning CI check (the same

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### S-02 · CRITICAL · `core/edge-functions/ottoq-energy-mpc/index.ts:8`
**Shared secrets hardcoded in the one live bridge to the intelligence service, which is deployed with verify_jwt=false over plaintext HTTP to a hardcoded IP**

Lines 7-9 read: `const AWS_URL = Deno.env.get("OTTOQ_INTEL_URL") ?? "http://100.53.130.57:8080";
const AWS_TOKEN = Deno.env.get("OTTOQ_INTEL_TOKEN") ?? "ottoq-frontier-a7f3c9d1e5b8"; const
BRIDGE_TOKEN = Deno.env.get("OTTOQ_BRIDGE_TOKEN") ?? "ottoq-frontier-a7f3c9d1e5b8";`. The same
literal is the fallback for BOTH the inbound bridge token (the only auth on the function, since
it is deployed with verify_jwt=false) and the outbound bearer to the EC2 service (which is
`_API_TOKEN` in ottoq-intelligence/app/main.py). CLAUDE.md and OTTO-Defense/CLAUDE.md both state
"no secrets in code, ever." This is not a theoretical path: this function is the ONLY live
wiring between otto-q-core and the intell

*Fix:* Delete both `??` fallbacks and fail closed when the env var is missing (return 500 with 'bridge
not configured'). Rotate `ottoq-frontier-a7f3c9d1e5b8` on the EC2 service and in Supabase
secrets, since it is in git history. Put the EC2 service behind HTTPS (or an ALB) and drop the
plaintext http:// default. Add a CI grep that fails the build on a string literal used as a
token default in edge-funct

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### S-03 · MAJOR · `intel/app/main.py:36`
**Intelligence-service bearer auth fails OPEN when OTTOQ_API_TOKEN is unset, on a service the deploy playbook exposes to 0.0.0.0/0**

`require_token` is `if _API_TOKEN and authorization != f"Bearer {_API_TOKEN}": raise 401`. The
guard is conditional on the secret existing, so a missing, empty or misspelled `OTTOQ_API_TOKEN`
in the container env silently disables authentication on every protected endpoint
(`/optimize/energy`, `/forecast`) rather than refusing to serve. `_API_TOKEN` is read once at
module import, so the failure is invisible at runtime — the service starts and answers normally.
deploy/DEPLOY_EC2.md:15 simultaneously instructs opening 'Custom TCP 8080 from Anywhere
(0.0.0.0/0)' and asserts '(it's protected by a bearer token below)' — a claim that is false in
exactly the misconfiguration this code chooses to to

*Fix:* Fail closed: at import, `_API_TOKEN = os.environ.get('OTTOQ_API_TOKEN')` and if it is falsy
either refuse to start (`raise RuntimeError`) or make `require_token` always 503, unless an
explicit `OTTOQ_ALLOW_OPEN=1` dev flag is set. Also compare with `hmac.compare_digest` rather
than `!=` to remove the timing side channel, and change the DEPLOY_EC2.md security-group note
from 'Anywhere' to the twin'

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix


## G — GUARDS THAT CANNOT FAIL

### G-01 · CRITICAL · `core/tests/test_separation.py:40`
**The `intent/` package is outside the separation guard: a network client and the production project ref can land there with all 267 tests green**

`KERNEL_PACKAGES = ("policies", "solvers", "sites", "wear", "onboarding", "conformance",
"recall", "adapters", "metrics", "proposer")` — `intent` is missing, so `intent/intent.py`,
`intent/signals.py`, `intent/solve.py` and `intent/learn.py` are checked by neither
`test_kernel_imports_no_database_and_no_twin` (doctrine 7: zero network, zero DB) nor
`test_kernel_names_no_production_identifiers` (doctrine 8 / the prod-ref ban) nor
`test_every_kernel_file_read_is_on_the_justified_allowlist`. The guard's own comment at line
37-39 says "absence from this list is the only way to dodge the guard, and reviews should treat
an unlisted kernel package as a finding" — and intent/README.md:182 cites "SEP

*Fix:* Add `"intent"` to KERNEL_PACKAGES, then add `("intent/intent.py", "world")` to ALLOWED_READS for
the intent_v1.json load. `stamp()`'s `p.write_text(...)` should move to a `scripts/` authoring
tool or be explicitly allowlisted, since a kernel module that writes a file is exactly what the
guard exists to surface.

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### G-02 · CRITICAL · `intel/tests/test_forecast_statistical.py:62`
**The AST contamination guard is non-recursive — a subpackage under app/forecasters/ imports psycopg2, hardcodes a DSN, queries ottoq_decisions, and scales the forecast, with all 10 tests green**

Both guard tests iterate `PKG.glob("*.py")` (non-recursive, top-level only). Any module in a
subdirectory of app/forecasters/ is never parsed, so it may import a DB driver, carry a
connection string, name a forbidden table, and feed a decision-derived number straight into the
forecast. statistical.py can import it with an absolute `from app.forecasters.sub import
decisions` — which the ImportFrom check waves through because the first path segment is `app`,
not a blacklisted driver name. The doctrine claim under audit ("structurally incapable of
learning from OTTO-Q decision history") is therefore not enforced by this guard; only convention
keeps files flat.

*Fix:* Use `PKG.rglob("*.py")` instead of `PKG.glob("*.py")` in both guard tests, and add a third guard
that walks the module graph: import app.forecasters, then assert every entry in sys.modules
whose __file__ is under the repo (transitively reachable from the package) is either inside
app/forecasters or on an explicit allowlist (stdlib math/json/hashlib/pathlib/dataclasses). A
reachability check over s

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### G-03 · CRITICAL · `pr176/proposer/test_orchestrate.py:132`
**The propose/dispose advisory guard never sees the rows the proposer actually emits — a proposal can grow `enact`/`execute`/`command_type` with the whole suite green**

Doctrine 1 ("agents propose, solver disposes — nothing in this layer may enact anything") is
enforced in exactly one place: `tests/test_separation.py:170` `_COMMAND_KEYS = ("command","comma
nd_type","enact","enacted","execute","actuate","setpoint","issue_at","dispatch")`, checked by
`test_every_emitted_row_is_advisory_not_an_instruction`. But that test builds its rows from
`model.build_and_solve(...)["proposals"]` (tests/test_separation.py:184-199) — the CP-SAT
model's own rows. It never touches the rows `proposer/forward_proposer.plan_to_proposals`
builds, which are the rows `propose()` and PR #176's `orchestrate()` return and the ones a
caller would insert into `ottoq_external_proposals`. T

*Fix:* Import `_COMMAND_KEYS` (or move it to a shared module) and run the same offender loop over
`propose(...)["proposals"]` and `orchestrate(...)["proposals"]` — both the served and the
declined/abstained rows, on the oversubscribed frame that already exists as `_oversubscribed()`.
Replace `assert "dispatch" not in row["proposal"]` in test_orchestrate.py with `for k in
_COMMAND_KEYS: assert k not in ro

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### G-04 · MAJOR · `core/intent/test_intent.py:35`
**`test_intent_tamper_is_refused` never calls `load_intent` on tampered content — deleting the intent fingerprint check leaves all 267 tests green**

The test mutates a *local copy* of the artifact dict, re-hashes it by hand, and asserts only
`fingerprint(canon) != raw["manifest"]["fingerprint_md5"]`. That exercises `fingerprint()`, not
the refusal. Nothing anywhere writes a tampered artifact and asserts `load_intent()` raises. The
verification block it claims to pin — intent/intent.py:92-97, `if manifest["fingerprint_md5"] !=
actual: raise ValueError(... refusing to optimize on an unverified intent)` — is therefore
unpinned.

*Fix:* Write the tampered artifact to a tmp_path copy and assert the refusal:      def
test_intent_tamper_is_refused(tmp_path):         raw = json.loads(ARTIFACT.read_text())
raw["objectives"]["readiness"]["direction"] = "maximize"         p = tmp_path /
"intent_v1.json"; p.write_text(json.dumps(raw))         with pytest.raises(ValueError,
match="fingerprint mismatch"):             load_intent(p)

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### G-05 · MAJOR · `core/intent/test_intent.py:157`
**The two-pass "signals override the clock" resolver is unpinned, and the comment that claims to pin it is factually wrong about the shipped artifact**

The test's comment states "The bug this pins: dispatch_rush is declared before the signal
regimes, so a naive first-match resolver would return dispatch_rush at 07:00". In the committed
intent_v1.json the signal regimes are declared FIRST (index 0 weather_event, 1 grid_peak, 2
demand_surge, 3 dispatch_rush, 4 overnight, 5 steady_state), so a naive first-match resolver
already returns the right answer. The two-pass structure at intent/intent.py:196-203 — and the
guarantee intent.py:180 and intent/README.md:59-65 make in prose, "it does not rely on
declaration-order luck" — is therefore not pinned by any test.

*Fix:* Test the mechanism, not the coincidence. Build an in-memory Intent whose regimes are reordered
so `dispatch_rush` comes first, and assert `resolve_intent(reordered, hour_of_day=7,
signals=frozenset({"grid_peak_imminent"})).regime_key == "grid_peak"`. `Intent` is a frozen
dataclass, so `dataclasses.replace(it, regimes=tuple(reversed(it.regimes)))` is enough — no
artifact edit and no re-stamp. Also

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### G-06 · MAJOR · `core/intent/test_learn.py:114`
**test_a_missing_reason_code_is_skipped_as_malformed_input contains no malformed record — deleting the guard it names leaves all 18 tests green**

The test is named for the malformed-input skip in _normalize, but its body constructs two
perfectly valid Refusal('superseded') records and asserts counts == {'superseded': 2}. It never
builds a record with a missing, None, or non-string reason_code, so the branch it is named after
is never entered. This is the only test in the file that claims to cover that seam, and it
covers nothing — the silent-drop defect above ships behind a green suite. Proven by mutation:
removing the `if isinstance(rc, str)` guard entirely (the exact behaviour the test names) does
not fail a single test.

*Fix:* Make the test actually pass a malformed record and assert the observable consequence, e.g.     r
= reconcile_refusals([Refusal("superseded"), Refusal(None), Refusal(123)])     assert r.counts
== {"superseded": 1}     assert r.malformed == 2 and not r.is_clean() after adding the malformed
counter from the companion finding. As written it must either be fixed or deleted; a test that
cannot fail is w

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### G-07 · MAJOR · `core/policies/forward.py:143`
**The min_flow pass's peak-ceiling threading has zero test coverage: deleting it passes all 109 tests while the shipped plan's peak triples**

`lexicographic_solve_traced` threads `max_peak_total` into the min_flow pass
(forward.py:143-145). This is the exact mirror of the bug the author already found and fixed in
the min_peak branch (the `max_flow_total` omission documented at forward.py:127-131). The
min_peak-side fix IS covered — mutating it away makes
`policies/test_regime.py::test_rush_and_grid_peak_produce_different_schedules` fail. The
min_flow side is covered by nothing. I copied the repo, deleted the `max_peak_total` threading,
and the ENTIRE suite (policies/ + solvers/cpsat/ + intent/, 109 tests) passed green while the
overnight/steady_state chain — the default regime for 2 of the 6 regimes — discarded the peak
optimum it

*Fix:* Add a property test that is symmetric in the two 3-pass orders and measures the FINAL plan
rather than the reported optima: for each of ('min_tardy','min_peak','min_flow') and
('min_tardy','min_flow','min_peak'), recompute tardy/peak/flow from `plan['assets']` (peak from
the charge segments' kW step function) and assert each is <= the corresponding value in
`optima`. That one test kills both mutan

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### G-08 · MAJOR · `core/proposer/test_forward_proposer.py:202`
**`assert r["planned"] > 0, "a partial plan should still serve someone"` cannot fail — `planned` counts declined rows too**

`propose()` returns `"planned": len(rows)` (forward_proposer.py:358) where `rows` is everything
`plan_to_proposals` emits — served assignments AND the abstention rows built for solver-rejected
vehicles (lines 195-204). So `planned` is the count of serviceable vehicles, not the count
served, and `planned > 0` is true whenever any vehicle was serviceable at all. The assertion's
stated claim ("should still serve someone") is therefore untestable by this expression. The same
conflation makes the field itself wrong: the docstring promises "'never invoked' distinguishable
from 'invoked and abstained'" (line 242-243), and `planned` erases exactly that distinction.

*Fix:* Assert on served rows, not the row count: `served = [p for p in r["proposals"] if not
p["proposal"]["abstain"]]; assert len(served) > 0`. Separately, split the return field so the
record is honest — keep `"rows": len(rows)` and add `"served": sum(1 for p in rows if not
p["proposal"]["abstain"])` — and update the callers/tests that read `planned`
(test_forward_proposer.py:117, test_orchestrate.py:1

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### G-09 · MAJOR · `intel/tests/test_forecast_statistical.py:180`
**T5 "SNAPSHOT INTEGRITY: fingerprint verifies" is a tautology — it passes with the loader's verification deleted AND the snapshot corrupted**

test_snapshot_fingerprint_verifies asserts `raw["manifest"]["fingerprint_md5"] ==
PRIORS.fingerprint`. But priors.py:140 sets `fingerprint=manifest["fingerprint_md5"]` — both
sides of the comparison are the same field read from the same file. The assertion is x == x and
verifies nothing. It does not pin the fingerprint to any committed literal, and it does not
exercise the loader's mismatch path. This is the only test in the suite named after snapshot
integrity, and per the doctrine ("a check that cannot fail is not a check") it is a defect.

*Fix:* Replace the tautology with two real checks: (1) `assert PRIORS.fingerprint ==
"e50ecc8848a7a56d478775eafa1bca7a"` — a committed literal, so any change to a prior number is a
deliberate, reviewed test edit; (2) a negative test that writes a mutated copy of the snapshot
to tmp_path with the manifest hash untouched and asserts `pytest.raises(ValueError)` from
load_priors, so the refusal path is exerc

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### G-10 · MAJOR · `intel/tests/test_forecast_statistical.py:183`
**test_snapshot_fingerprint_verifies is a tautology: it compares the manifest field to itself and passes on a tampered snapshot**

T5 asserts `raw["manifest"]["fingerprint_md5"] == PRIORS.fingerprint`. But `Priors.fingerprint`
is assigned verbatim from that same manifest field (priors.py:140,
`fingerprint=manifest["fingerprint_md5"]`) -- it is never the recomputed hash. The assertion is
therefore `manifest[x] == manifest[x]`, true for any file whatsoever. The real integrity guard
(priors.py:145-153, recompute and refuse on mismatch) exists and works, but no test exercises
it, so it can be deleted or inverted and the suite stays green. This is the only test guarding
the artifact that the whole contamination-boundary argument rests on. The intent layer's
equivalent gets this right: intent/test_intent.py:35-43 (`test_inten

*Fix:* Replace the tautology with the two directions that can actually fail: (a) recompute -- `assert
fingerprint(canonical(raw)) == raw["manifest"]["fingerprint_md5"]` using the module's own
`fingerprint()` on the canonical content; and (b) tamper -- write a copy with one prior value
mutated and `pytest.raises(ValueError)` on `load_priors(copy)`. Mirror
intent/test_intent.py:35-43, which already has exa

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### G-11 · MAJOR · `intel/tests/test_forecast_statistical.py:180`
**`test_snapshot_fingerprint_verifies` is tautological — deleting the priors verification leaves the forecast suite green**

`assert raw["manifest"]["fingerprint_md5"] == PRIORS.fingerprint` cannot fail: `load_priors`
assigns `fingerprint=manifest["fingerprint_md5"]` (app/forecasters/priors.py:139) before it
verifies anything, so the test compares a field to itself. The block it purports to cover —
priors.py:149-154, `actual = fingerprint(content); if actual != priors.fingerprint: raise
ValueError(... refusing to forecast on an unverified prior set)` — has no test. There is no
tampered-snapshot test anywhere in the file.

*Fix:* Add a tamper test that writes a mutated snapshot to tmp_path and asserts
`pytest.raises(ValueError)` from `load_priors(p)` — `load_priors` already accepts a path. Then
make the existing assertion non-tautological by recomputing: `assert fingerprint({k: raw[k] for
k in ("datasets","profiles","distributions")}) == PRIORS.fingerprint`.

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### G-12 · MAJOR · `intel/tests/test_forecast_statistical.py:147`
**The forecast's entire p10/p50/p90 uncertainty band is unpinned — the monotonicity test passes when all three quantiles collapse to the same number**

`test_quantile_ordering_is_monotonic` asserts `h["p10"] <= h["p50"] <= h["p90"]` (and the same
for load). A `<=` chain is satisfied by equality, so a band of zero width passes. No test
anywhere asserts a band has non-zero width, or pins a single quantile to a value. That leaves
three separate pieces of the forecast's uncertainty machinery unprotected: `_poisson_quantile`
(statistical.py:69), the 1.28-sigma load band (statistical.py:227-228), and `_grid_quantile`
(statistical.py:55) which drives every soc_return quantile. This matters downstream:
`intent/signals.py:249-259` raises `grid_peak_imminent` from `max(total_kw_p90)` — the
"conservative tail" — so a collapsed p90 silently makes the g

*Fix:* Pin band width, not just ordering. For arrivals: `assert any(h["p90"] > h["p50"] > h["p10"] for
h in a.hours)` on an hour with lambda well above 1, plus one golden value regenerated from the
committed snapshot seed (`_poisson_quantile(2.5, 0.90) == 5`). For load: `assert
h["total_kw_p90"] - h["total_kw_p50"] == pytest.approx(1.28 * ev_std)` for one hour. For
soc_return: assert `return_soc["p10"] <

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### G-13 · MAJOR · `otto-q-core/intent/test_intent.py:35`
**test_intent_tamper_is_refused never calls the loader — the entire fingerprint verification can be deleted and all 17 intent tests still pass**

The module docstring (intent.py:11) and README both ship the claim "a tampered or truncated
intent is refused, never silently used." The only test named for that claim never invokes
`load_intent()` on a tampered artifact. It mutates an in-memory dict, re-implements
`_canonical()` inline with its own hardcoded key tuple (test_intent.py:40-41), and asserts only
that md5 of different bytes differs — a property of hashlib, not of this code. The refusal
branch at intent.py:92-97 has zero test coverage, and because the test re-hardcodes the
canonical key list it would also go on passing if CANONICAL_KEYS were narrowed to exclude
`objectives` entirely.

*Fix:* Replace the in-memory hash comparison with an end-to-end refusal test: write the tampered
artifact to tmp_path and assert `pytest.raises(ValueError, match="fingerprint mismatch")` on
`load_intent(tmp_path/...)`. Add a truncation case (a file with `regimes` removed) and a case
that mutates a field in each of the four CANONICAL_KEYS, so narrowing the covered key set also
fails. Import `_canonical` r

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### G-14 · MAJOR · `pr176/tests/test_separation.py:42`
**The zero-network/zero-DB separation guard does not cover intent/, which orchestrate() calls on every request — proven by adding `import requests` and watching CI pass**

`KERNEL_PACKAGES = ("policies", "solvers", "sites", "wear", "onboarding", "conformance",
"recall", "adapters", "metrics", "proposer")` omits `intent`. That is the package holding
`signals.py` (the forecast bridge orchestrate.py:42 imports and calls on every request),
`solve.py` (the pass sequencer), and `intent.py` (which does a `read_text` and a `write_text`).
The file's own comment at line 39-41 says "absence from this list is the only way to dodge the
guard, and reviews should treat an unlisted kernel package as a finding" — this is that finding.
`intent/` is squarely kernel: it turns the forecast into the pass order the solver runs. The new
PR routes the conductor's entire input path thr

*Fix:* Add `"intent"` to KERNEL_PACKAGES (tests/test_separation.py:42). That will also correctly flag
`intent/intent.py`'s `read_text`/`json.load` against ALLOWED_READS, which should then gain an
explicit `("intent/intent.py", "world")` entry with its reason (loading the declared,
fingerprint-verified doctrine artifact) — which is the review moment the allowlist exists to
create.

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### G-15 · MINOR · `core/intent/intent_v1.json:284`
**"11 objectives across 3 tiers" — the 11 objectives span 2 tiers; tier 3 contains no objectives by the artifact's own statement**

intent_v1.json carries exactly 11 objectives (CONFIRMED), but every one of them is tier 1 (4:
energy_cost, readiness, service_completion, throughput) or tier 2 (7: bess_peak_shave, deadhead,
degradation, dwell, risk_hedge, staff, staging). The file's own `tier3_constraints` block at
line 284 states: "Tier 3 is NOT weighted and does NOT live in this artifact. It is the 52-rule
deterministic shield plus the legal parameters... This artifact points at it and never
duplicates it." So "11 objectives across 3 tiers" describes a distribution that does not exist —
no objective is tier 3, and tier 3 is deliberately out of the artifact.

*Fix:* Say "11 weighted objectives across tiers 1-2, with tier 3 held as non-negotiable constraints
outside the artifact (the 52-rule shield)". That is both true and the doctrinally important
statement.

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### G-16 · MINOR · `core/intent/test_learn.py:89`
**The live_world flag threshold boundary is unpinned — the documented "beyond threshold 2" rule is never tested at 2**

`test_live_world_flags_only_on_entity_repetition` tests one occurrence (clean) and three
occurrences (flagged). `reconcile_refusals` uses `k > entity_repeat_threshold` with
`entity_repeat_threshold: int = 2` (learn.py:173, 218, 238), so the boundary case — the same
(reason_code, entity_id) pair appearing exactly twice — is the one that distinguishes `>` from
`>=`, and no test covers it.

*Fix:* Add the boundary case to the existing test: `twice =
reconcile_refusals([Refusal("target_occupied", entity_id="s-1")] * 2); assert twice.is_clean()`
— and, since the parameter is public, one call with `entity_repeat_threshold=1` asserting that
two occurrences then DO flag.

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### G-17 · MINOR · `core/intent/test_signals.py:95`
**The determinism test compares two calls in one process and would not catch cross-process nondeterminism; no golden output is committed**

test_bridge_is_deterministic calls forecast_signals twice on the same dict in the same
interpreter and asserts the two results are equal. Within one process PYTHONHASHSEED is fixed,
frozenset/dict iteration order is stable, and the wall clock rarely crosses an hour boundary —
so the test passes under exactly the hazards the doctrine names (hash-order dependence, hour-
granularity clock reads) and only fails on the crudest case (an unseeded RNG). Nothing in the
suite pins a byte-level expected output, so the doctrine's "same inputs + same seed => byte-
identical output" is asserted for this module but not actually demonstrated. Related coverage
gap, and the reason the unreachable-surge defect s

*Fix:* Commit a golden JSON of assessment.to_dict() for one fixed fixture and assert byte equality
against json.dumps(..., sort_keys=True); run the same fixture in a subprocess under two
different PYTHONHASHSEED values and assert identical bytes. Separately, add one test that
imports app.forecasters.statistical.forecast with the committed priors and asserts each of
demand_surge and grid_peak_imminent is

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### G-18 · MINOR · `core/policies/forward.py:110`
**The readiness-floor guard on the lexicographic chain is unpinned — removing it leaves the policy suite green**

`if not pass_modes or pass_modes[0] != "min_tardy": raise ValueError("lexicographic chain must
begin with min_tardy -- the readiness floor is structural and precedes every soft objective")`
is the solver-side enforcement of the structural readiness floor. Every call site in the repo
(`policies/regime.py:60`, `policies/forward.py:65`, `proposer/forward_proposer.py:332`, and all
five call sites in policies/test_regime.py) passes a sequence that already starts with
min_tardy, so the raise is never exercised and no test asserts it fires.

*Fix:* One assertion in policies/test_regime.py:      with pytest.raises(ValueError, match="must begin
with min_tardy"):         lexicographic_solve(load_scenario(SC), ("min_peak", "min_tardy"))
with pytest.raises(ValueError):         lexicographic_solve(load_scenario(SC), ())

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### G-19 · MINOR · `core/solvers/cpsat/test_cpsat_prototype.py:271`
**T3 'SITE POWER CAP' stays green with the hard site power cap deleted from the model, and T2 skips parallel ops when checking point exclusivity**

T3's two assertions are `true_peak <= power_cap_kw_hard` (550 <= 1000) and `true_peak <=
soft_target + peak_excess_kw` (550 <= 700 + 0) on the canonical scenario, whose peak is nowhere
near either limit. Neither can fail, and neither pins peak_excess_kw to anything. Mutation-
tested: replacing the hard-cap capacity with 10**9 leaves the canonical plan byte-identical
(same plan_sha256) and T1-T8 all pass, T3 included, printing the identical numbers. The only
thing that catches the deletion is the pinned objective literal in T9 (105129), on an unrelated
squeezed variant -- and T9's pinned numbers have already been recalibrated twice per its own
comments, so the site power cap's only real covera

*Fix:* Assert T3 on a variant where the cap actually binds -- e.g. `_variant(charge_points=6,
horizon_min=1200)` with power_cap_kw_hard squeezed to 300 -- and assert both that the true peak
is <= the cap AND that a cap one step lower changes the plan. Include parallel ops in T2's per-
point grouping (the point is occupied to stay_end, so the exclusivity check should use each
asset's on-point span, not jus

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### G-20 · MINOR · `core/solvers/cpsat/test_cpsat_prototype.py:125`
**`solvers/cpsat/test_cpsat_prototype.py` contributes zero tests to `pytest` despite its name — the 19-check CP-SAT battery is invisible to the suite that reports "267 passed"**

The file contains no `test_*` function; all 19 checks (T1, T1b, T1c, T1d, T2-T15, including the
byte-identical determinism certification T1 and the rejection-price dominance T15) live inside a
single `main()` behind `if __name__ == "__main__"`. `pytest` collects zero items from it, so the
headline suite number excludes the entire CP-SAT battery. Because it is one linear `main()`, a
failure at T1 also aborts T2-T15, so a single early regression hides ~50 downstream assertions.
`policies/test_policies.py` has the same shape for P1-P5 (pytest collects only the 8 module-
level cost tests from that file).

*Fix:* Either rename the file to `cpsat_battery.py` so its name stops implying pytest coverage, or
split `main()` into module-level `def test_t1_determinism():` … `def
test_t15_rejection_price():` functions (keeping a `main()` that calls them in order for the CI
script step). Splitting is worth the churn: it also removes the first-failure-aborts-the-rest
behaviour, so one regression no longer masks eight

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix


## L — LOGIC DEFECTS

### L-01 · CRITICAL · `core/intent/learn.py:243`
**learned block_points names every entity that ever carried the code, not the entities that crossed the repeat threshold — 58 spurious blocks vs 21 real on the live ledger**

reconcile_refusals decides WHETHER to emit a constraint from the repeat threshold (`flagged`,
lines 235-241), but then populates it by iterating every (reason_code, entity) pair for that
code with no threshold test at all:      for (rc, eid) in pairs:         if rc == code:
learned[lc].add(eid)  So one genuinely stuck point crossing the threshold drags every point that
produced a single one-off refusal of the same code into the learned constraint. For
`resource_faulted -> block_points` that means healthy service points are removed from the next
solve's capacity. The report is internally inconsistent: the flag message correctly names only
the repeating entity, while `learned_const

*Fix:* Populate the constraint from the same predicate that flagged it. For live_world codes add only
entities whose pair count exceeds entity_repeat_threshold; for solver_gap codes (which flag on
any occurrence) keep the current behaviour. Concretely, replace the unconditional inner loop
with:      for (rc, eid), k in pairs.items():         if rc == code and (cls.kind ==
'solver_gap' or k > entity_repea

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-02 · CRITICAL · `core/intent/signals.py:219`
**demand_surge is structurally unreachable on the real forecast: a flat daily-mean baseline vs. a diurnally-shaped arrivals forecast whose own peak is only 1.9x that mean**

The surge baseline is `(mean_daily_arrivals / 24) * window` — a FLAT hourly rate — while the
arrivals forecast this bridge consumes is `mean_hourly * hourly_shape[hod] * dow_mult`
(intel/app/forecasters/statistical.py:145), a strongly diurnal NYC-TLC shape normalized to mean
1.0. The shipped prior's shape peaks at 1.6962 (hour 18) and its busiest 3-hour run (17,18,19)
sums to 4.7577 vs. a flat 3.0 — ratio 1.586. The largest dow multiplier is 1.198. 1.586 x 1.198
= 1.900 < the surge_multiplier default of 2.0. Therefore, with the committed priors and default
thresholds, `demand_surge` can NEVER fire, for any site, any hour, any day of week. The ratio is
scale-invariant (fleet_size and turns_pe

*Fix:* The comparison is dimensionally right but climatologically wrong: it asks "is this window above
the daily flat average?" when the forecast's own diurnal shape already guarantees the answer for
every hour. Compare the window against its OWN climatological expectation instead — i.e.
baseline = sum over the window of (mean_hourly * hourly_shape[hod] * dow_mult), which is exactly
the forecast's unpert

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-03 · CRITICAL · `core/proposer/forward_proposer.py:346`
**The regime fire record reports complete:true when a pass returned FEASIBLE (never proved its optimum) — a truncated plan published as a whole one**

`"complete": all(optima.get(m) is not None for m in modes)` treats "the pass returned a number"
as "the pass held an optimum". The retained-pass case (INFEASIBLE/UNKNOWN) is handled —
forward.py:170 sets optima[mode]=None — but the FEASIBLE case is not. When CP-SAT exhausts the
deterministic budget with an incumbent but no optimality proof, model.py:805 stamps
solver_status="FEASIBLE", lexicographic_solve_traced records the incumbent value as the held
optimum, and `complete` stays True. The docstring three lines above
(forward_proposer.py:343-345) claims the opposite verbatim: "complete == every pass in the
regime held an optimum ... never silently claimed." Worse, the non-optimal T* then be

*Fix:* `complete` must require proven optimality on every pass, not merely a recorded value:
`"complete": (len(passes) == len(modes) and all(p["status"] == "OPTIMAL" for p in passes) and
all(optima.get(m) is not None for m in modes))`. Correspondingly, in policies/forward.py:120-158
the per-pass optimum should be recorded as `None` (or carried with a `proven: False` flag) when
`plan["solver_status"] != "

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-04 · CRITICAL · `core/proposer/forward_proposer.py:132`
**Per-vehicle inlet power limit is collapsed into one per-class value taken from whichever vehicle happens to be first in the frame — wrong requested_kw, and the plan changes when the frame rows are reordered**

`classes.setdefault(cname, {...})` keys the asset class on `platform` alone, but the value it
stores is computed from the CURRENT vehicle's per-unit fields: `max_charge_kw =
min(cls["max_charge_kw"], v["inlet_max_kw"])` (line 134-135) and `"inlet": v.get("inlet_type",
"CCS")` (line 136). `setdefault` means only the first vehicle of each platform is consulted;
every later vehicle of that platform silently inherits its inlet limit and connector type.
`inlet_max_kw` and `inlet_type` are declared per-vehicle in the frame contract (docstring line
17-18) precisely because they vary per unit — a derated or damaged inlet is a per-vehicle fact.
Two consequences: (a) proposals carry a physically wrong

*Fix:* Key the synthesized class on the per-unit facts that actually enter the model, not on platform
alone — e.g. `cname = f"{platform}|{int(eff_kw)}|{inlet}"` where `eff_kw =
min(cls['max_charge_kw'], v.get('inlet_max_kw') or cls['max_charge_kw'])` — so a derated unit
materializes its own asset class. Add a test with two vehicles of one platform at different
inlet_max_kw asserting each proposal's reque

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-05 · CRITICAL · `core/solvers/cpsat/model.py:464`
**An asset arriving at or above its target SoC makes the ENTIRE site model INFEASIBLE (AddExactlyOne over an empty list); reachable in production by rounding**

charge_segments() returns [] when asset.soc >= asset.target_soc (line 230, `hi <= lo:
continue`). build_and_solve then skips every candidate for that asset (`if not segs: continue`,
line 382-383), so `lits` stays empty and line 464 emits `m.AddExactlyOne([])` -- an
unsatisfiable constraint. The result is not 'that one asset is unschedulable': the WHOLE model
is INFEASIBLE, every other vehicle loses its plan, and build_and_solve raises RuntimeError('no
schedule and no previous plan: INFEASIBLE'). The production bridge's serviceable() filter
(proposer/forward_proposer.py:102-105) tests the RAW float soc against target, but
frame_to_scenario then writes `int(round(soc))` (line 144). A vehicle a

*Fix:* An asset with nothing to charge is a legal input, not an infeasible site. In the per-asset
block, detect `not lits` (or equivalently `charge_segments` empty for every candidate) and take
a no-charge path: bind charge_start = charge_end = arrival_min, skip the exactly-one entirely,
still schedule wash/inspect and emit a proposal with abstain=True and reason 'already at target
SoC; no charge schedul

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-06 · CRITICAL · `core/solvers/cpsat/model.py:66`
**The 100k rejection penalty does not dominate the weighted objective: the solver proves OPTIMAL by dropping a vehicle it could have served**

DEFAULT_REJECTION_PENALTY is justified in its own comment as 'an order of magnitude above the
worst single-asset tardiness this horizon can produce'. That is the wrong bound. The quantity
rejection has to beat is the AGGREGATE objective relief a rejection buys -- the rejected asset's
own tardiness plus every downstream asset it stops delaying -- and nothing in the model bounds
that. Worse, tardiness_per_min is scenario DATA: the committed scenarios all use 10, so
rejection becomes strictly profitable for any single asset whenever `W['tardiness_per_min'] *
horizon_min > 100_000` (H > 10,000 min at weight 10, or H > 1,000 min at weight 100). There is
no validation anywhere that checks the decl

*Fix:* Derive the penalty from the instance instead of hardcoding it. At build time compute an upper
bound on the total objective any single asset can contribute or relieve -- e.g. `n_assets *
W['tardiness_per_min'] * H + max_onpeak_term + W['peak_excess_per_kw'] * power_cap_kw_hard +
W['per_move'] * max_moves` -- and use `max(DEFAULT_REJECTION_PENALTY, that_bound + 1)` unless
the scenario explicitly set

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-07 · CRITICAL · `intel/tests/test_forecast_statistical.py:38`
**FORBIDDEN_IMPORTS is a 11-name blacklist: __import__, importlib, urllib.request, socket, http.client, subprocess, sqlite3 and os.environ all reach the network or a database unchallenged**

test_contamination_guard_no_db_or_network_import only inspects ast.Import / ast.ImportFrom nodes
and compares the first dotted segment against a fixed list of 11 third-party names. Every other
route to a socket or a database is invisible: `__import__('psycopg2')` and
`importlib.import_module('psycopg2')` are ast.Call nodes, not imports; `urllib.request`,
`socket`, `http.client`, `ftplib` are stdlib network clients not on the list; `sqlite3` is a
stdlib database; `subprocess` runs psql; and `os.environ.get('DATABASE_URL')` plus `open()` of a
DB export path need no import at all. The claim in priors.py:12-14 ("There is no code path
anywhere in this package to ottoq_decisions ... or any other s

*Fix:* Invert the polarity: replace the blacklist with an ALLOWLIST of importable modules for this
package (`math`, `json`, `hashlib`, `pathlib`, `dataclasses`, `typing`, `__future__`,
`app.forecasters.*`) and fail on anything else. Separately assert the package contains no
ast.Call to `__import__`, `eval`, `exec`, `compile`, `open`, `importlib.import_module`, and no
`os.environ` access — those are calls

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-08 · CRITICAL · `pr176/proposer/forward_proposer.py:73`
**The proposer's default serviceable-state vocabulary does not match production: 3 of its 6 states cannot exist, and it omits staged_awaiting_service, silently dropping 13 real vehicles**

DEFAULT_SERVICEABLE_STATES = {"arrived_at_gate","awaiting_stall","in_queue","charging_dcfc","cha
rging_l2","charge_scheduled"}. The production `vehicle_state` type is a Postgres ENUM with
exactly 17 labels; `awaiting_stall`, `in_queue` and `charge_scheduled` are not among them and
can never appear in a decision frame. Worse, the enum's actual "on site, awaiting service" label
— `staged_awaiting_service` — is NOT in the set, so those vehicles are filtered out before
frame_to_scenario ever sees them. They therefore get neither a proposal row nor an abstention
row, which is exactly the silent drop the module's own plan_to_proposals docstring ("NEVER
SILENTLY DROPS ONE") declares must not happen.

*Fix:* Derive the set from the live enum rather than from memory. Add `staged_awaiting_service` (and
consider `charge_complete_holding` for non-charge service), and delete `awaiting_stall`,
`in_queue`, `charge_scheduled`. Add a test that asserts every member of
DEFAULT_SERVICEABLE_STATES is a label of the committed `vehicle_state` enum (the enum labels are
already in db/baseline, so the test needs no dat

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-09 · CRITICAL · `pr176/proposer/forward_proposer.py:227`
**propose() has no default solve budget and is orders of magnitude too slow for the one-tick right-of-first-refusal it claims to occupy: 10 vehicles takes 88.7s on the conductor path against cuOpt's 90s TTL, and the real frame's 44 serviceable vehicles do not finish in 5 minutes**

propose() defaults to `det_budget_s=None, time_limit_s=None` — no budget of any kind — and
orchestrate() never passes one either (it forwards only **propose_kwargs, and no caller exists
to supply them). The README asserts the module occupies "exactly cuOpt's seat" under the
deferral pattern, where a proposal has one tick of right-of-first-refusal. Measured on a real
production decision frame, the solve time explodes well before production scale, so the seat
cannot actually be occupied. Every test in proposer/ uses 3-5 synthetic vehicles and 3-4 stalls,
which is why this never surfaced.

*Fix:* Make a deterministic budget mandatory: give det_budget_s a real default (and have orchestrate()
pass one), so a proposal is always bounded and always reproducible. Then either batch the frame
(solve the N most-urgent vehicles per tick and abstain on the rest with reason "outside this
tick's batch") or warm-start from the previous tick's plan. Add a benchmark test that runs
propose() on a committed

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-10 · MAJOR · `core/intent/learn.py:229`
**learned constraints have no cap, no TTL and no unlearn path, and a large blocked set makes the next solve raise RuntimeError with no fallback**

`learned_constraints` is emitted as a bare kind -> entity-list map. There is no bound on how
many points `block_points` may name, no expiry/decay/re-verification stamp on any entry, no
confidence or count carried through, and no inverse operation anywhere in the module or repo
that ever removes a learned block. Nothing in learn.py or intent/README.md declares this as
deferred — the README states flatly that "the resulting constraints become the next propose's
blocked_points / capacity." Downstream, solvers/cpsat/model.py raises a hard RuntimeError when a
blocked set makes the model infeasible and there is no previous plan, so an over-large learned
block set takes the site from "degraded sche

*Fix:* Make each learned entry carry its provenance and its lifetime: emit (entity, kind,
observed_count, window/run_id, expires_after_n_solves) rather than a bare id, cap block_points
at a configurable fraction of the capable points of a kind (refusing to learn beyond it and
flagging instead), and require re-observation to renew a block. Declare the entity TYPE per
constraint kind (block_points = servic

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-11 · MAJOR · `core/intent/learn.py:93`
**tighten_capacity is unreachable from the declared input source: 77,435 no_capacity escalations live in ottoq_events, 0 in the reason_code column learn.py reads**

REFUSAL_TAXONOMY classifies 'no_capacity' as the solver_gap whose learned constraint is
'tighten_capacity' — "the solver over-estimated the site's ability; its capacity model is looser
than the world's." That is the single most consequential calibration signal in the taxonomy. But
the production engine never writes 'no_capacity' into ottoq_vehicle_commands.reason_code, which
learn.py's Refusal docstring (line 121) and intent/README.md:160 both name as THE production
source. db/baseline/functions_ottoq.sql:2373-2380 emits it only as an ottoq_events payload field
on event_type 'ottoq.refusal_escalated'. The result: the branch is dead against its declared
feed, and the loop is structurally blin

*Fix:* Either widen the declared feed — document (and, when the offline job lands, implement) that the
batch is the UNION of ottoq_vehicle_commands.reason_code and ottoq_events payload reason_code
for event_type='ottoq.refusal_escalated' — or annotate each RefusalClass with the channel it
actually arrives on so a reader can see which branches are live. In both cases give no_capacity
a rate/threshold rule

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-12 · MAJOR · `core/intent/learn.py:168`
**A batch whose reason_codes are all missing is silently dropped and is byte-identical to an empty clean batch**

_normalize's guard `if isinstance(rc, str)` drops any record whose reason_code is None or non-
string. Such a record is not counted, not surfaced in unknown_codes, and leaves no trace
anywhere in the report. The resulting ReconciliationReport is indistinguishable from the report
for an empty list, and is_clean() returns True. Migration 0086 explicitly left 14 historical
refused rows with reason_code NULL as evidence (the refusal_has_code constraint is NOT VALID),
so NULL-coded refusals are a real shape in this ledger; and if a future engine path writes a
refusal with a NULL or non-text code, the loop's answer is "everything is clean" rather than "I
could not read these".

*Fix:* Count what was dropped. Add a `malformed: int` (or `unreadable: tuple[...]`) field to
ReconciliationReport, increment it in _normalize for every record whose reason_code is not a
str, and include it in is_clean(). A batch that contained records but produced no readable codes
must not report clean.

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-13 · MAJOR · `core/intent/signals.py:219`
**The surge baseline ignores the day-of-week multiplier that scales every forecast hour, drifting the trigger point +-20% by weekday**

`mean_daily_arrivals` is the operator's declared scale, `fleet_size * turns_per_day`
(intel/app/forecasters/statistical.py:130), and is NOT multiplied by the dow multiplier. Every
hourly `expected_arrivals` IS (statistical.py:144: `lam = mean_hourly * hourly.data[hod] * dw`).
The bridge therefore compares a dow-scaled numerator against a dow-blind denominator. The same
physical arrival pattern is judged against a threshold that is effectively 20% too lax on
Saturday and 16% too strict on Monday. This is a hidden day-of-week bias in a signal that is
supposed to mean "abnormally hot window".

*Fix:* Derive the baseline from the forecast's own hours rather than from the declared daily scalar:
`baseline = (sum(expected_arrivals over all 24 hour_of_day entries) / 24) * surge_w`. That is
dow-consistent by construction, needs no new contract field, and requires no trust in
`mean_daily_arrivals` at all (which would also remove the `mean_daily_arrivals <= 0` contract
dependency at signals.py:203-207

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-14 · MAJOR · `core/intent/signals.py:217`
**NaN in any consumed forecast field silently suppresses the signal — the exact failure the module documents itself as preventing**

The TOTAL seam validates PRESENCE of `expected_arrivals` / `total_kw_p90` /
`mean_daily_arrivals` but never their VALUE DOMAIN. `float(h[...])` accepts NaN, and every
downstream comparison with NaN evaluates False, so the signal is silently not-raised.
signals.py:213-216 and 240-242 carry comments explicitly saying the bridge "refuses to treat a
missing count as zero (that would hide a surge)" — but NaN hides the surge just as completely,
and worse, without an exception. README.md:86 publishes this as "TOTAL: a malformed forecast
raises ForecastContractError". A NaN forecast is malformed and does not raise. Same hole for
`total_kw_p90` (hides a grid peak) and for `mean_daily_arrivals` (thres

*Fix:* Add a single coercion helper used at signals.py:203, 217 and 243: `v = float(x); if not
math.isfinite(v): raise ForecastContractError(f"{field} is not finite ({x!r}) — the bridge
refuses to compare against a non-finite forecast value")`. Add three tests (NaN arrivals, NaN
p90, inf p90) asserting ForecastContractError, mirroring the existing
test_a_missing_value_field_raises_instead_of_treating_it_

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-15 · MAJOR · `core/intent/signals.py:245`
**site_power_target_kw is never validated: a target of 0 or a negative target makes grid_peak_imminent fire unconditionally**

`site_power_target_kw` is the one caller-supplied physical quantity in the signature and it
receives no validation at all — no type check, no positivity check, unlike `now_hour` (bounds-
checked at signals.py:186) and unlike `thresholds` (name-checked at signals.py:191-193).
`peak_hit = peak >= peak_f * site_power_target_kw` with a target of 0 gives `peak >= 0.0`, which
is true for any non-negative load, so the signal latches on permanently. A negative target is
worse (threshold -90.0). NaN gives permanent silence. The reasoning dict then reports
`"threshold": 0.0` and `"site_power_target_kw": 0` to the operator as if that were a real
demand-charge ceiling.

*Fix:* Validate alongside now_hour at signals.py:186: `if not isinstance(site_power_target_kw, (int,
float)) or isinstance(site_power_target_kw, bool) or not math.isfinite(site_power_target_kw) or
site_power_target_kw <= 0: raise ValueError(...)`. Add a test parameterized over (0, -100, None,
'700', nan) asserting ValueError — the same shape as the existing
test_now_hour_is_bounds_checked.

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-16 · MAJOR · `core/intent/signals.py:194`
**Threshold overrides bypass all range validation: a zero/negative window or a non-positive multiplier makes demand_surge fire unconditionally**

The override path checks the threshold NAME (signals.py:191-193) but applies `eff[k] = float(v)`
with no domain check. surge_window_hours=0 makes `_window` return an empty list, so expected=0.0
and baseline=0.0 and `0.0 >= 2.0*0.0` is True — a zero-length lookahead reports a demand surge.
Negative windows behave the same (range(-2) is empty). surge_multiplier of 0 or negative makes
the threshold <= 0, always hit. peak_fraction=0 does the same for grid_peak. A float window like
3.9 is silently truncated by `int()` at signals.py:208/235. Note the asymmetry, which shows this
is unintended rather than a documented convention: peak_window_hours=0 yields peak=0.0 via the
`if _p90 else 0.0` guard a

*Fix:* Give Threshold a domain and enforce it in the override loop: window thresholds must be integers
in 1..24 (reject a non-integral float rather than truncating), ratio thresholds must be finite
and > 0. Independently, guard the comparison itself so an empty window can never register:
`surge_hit = bool(_vals) and baseline > 0 and expected >= surge_m * baseline`, matching the
existing `if _p90 else` gu

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-17 · MAJOR · `core/intent/signals.py:229`
**A caller-supplied threshold is published with the house's own evidence label and source, presenting an operator's number as a house inference**

The reasoning dict always reads provenance from the module-level SIGNAL_THRESHOLDS constants
(signals.py:229-230 and 254-255), never from what was actually used. When `thresholds=`
overrides a value, the `threshold` field reports the OVERRIDDEN number while `evidence_label`
and `source` still report the DEFAULT's provenance. The module's entire stated purpose
(docstring lines 31-39: "the founder's rule: no invented numbers", and the README's "honest
threshold discipline") is that every raised signal walks to its number and that number walks to
its grounding. After an override the walk lands on the wrong grounding: an arbitrary operator-
chosen coefficient is stamped "must-measure-on-twin: no

*Fix:* Track overrides explicitly: build `eff` as a dict of (value, evidence_label, source) triples,
and when the caller overrides a name set evidence_label='operator-override' and source='caller-
supplied; not the SIGNAL_THRESHOLDS default (was <default>)'. Emit that triple into reasoning
instead of the constant. Add 'operator-override' to EVIDENCE_LABELS and a test asserting the
label changes when and o

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-18 · MAJOR · `core/policies/forward.py:155`
**A failed pass publishes the PREVIOUS pass's objective under its own mode in the trace — the exact number the retained-pass guard was written to suppress**

The comment at forward.py:160-169 says the guard exists because an earlier version "reported a
'peak' of 1685 that was really the min_flow objective (a retained plan's leftover)". The guard
sets `optima[mode] = None` — but `passes.append(...)` runs FIRST (forward.py:154-158) and
unconditionally records `plan.get('objective')`, `plan['repro']['deterministic_time']` and
`plan['repro']['reproducible']` from the retained plan, i.e. from the pass BEFORE. So the
leftover number is still emitted, just in a different field. `passes` is published verbatim into
the fire record (forward_proposer.py:339 `"passes": passes`). The retained pass also claims
`reproducible: true` for a pass that produced no s

*Fix:* Move the `retained_previous` check above `passes.append`, and for a retained pass append
`{"mode": mode, "status": plan["solver_status"], "objective": None, "deterministic_time": None,
"reproducible": False, "retained": True}`. A pass that produced nothing should report nothing,
in every field, not just in `optima`.

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-19 · MAJOR · `core/policies/forward.py:136`
**The chain prices churn BETWEEN lexicographic passes, so at the documented production weight pass 2 reports OPTIMAL for a peak 11 kW above the true constrained optimum**

Passes 2 and 3 are called with `previous_plan=plan`, where `plan` is the PREVIOUS PASS's
schedule (forward.py:135-136 and 146-147). In model.py the churn term is built whenever
`previous_plan` is set and `churn_per_change > 0` (model.py:347, 470-494), and it rides in
`side`, which is added to EVERY objective mode (model.py:664, 680, 688). So with churn priced,
pass 2 minimizes `peak + 500 * (assets moved off their pass-1 point)` rather than `peak`. Churn
is meant to price a vehicle moving between rolling RE-SOLVES — a real trip in the yard. The
pass-1 plan is not a tick that ever happened; it is an arbitrary tie-broken min-tardy schedule.
Penalizing deviation from it makes the reported P* no

*Fix:* Separate the two uses of `previous_plan`. Give `build_and_solve` an explicit `price_churn: bool
= True` (or a `hint_plan=` parameter distinct from `previous_plan=`), and have
`lexicographic_solve_traced` pass the prior PASS's plan for hints/retention only, with churn
pricing off. Churn should be priced exactly once per chain, against the previous TICK's enacted
plan, in pass 1 — never between pass

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-20 · MAJOR · `core/policies/forward.py:148`
**With allow_rejection on, the chain does not hold the served SET across passes: the vehicle the site abandons changes at every pass**

The ceilings are aggregates over whoever a pass happens to serve: `max_tardy = sum(tardy_min for
served)` (forward.py:123-124) and `max_flow = sum(finish for served)` (forward.py:148-149),
enforced against `sum(charged_tardy)` and `sum(all_finish)`, both of which are gated to 0 for a
rejected asset (model.py:606-608, 620-627). Nothing constrains WHICH assets are served, and
nothing constrains HOW MANY — the served count is held only incidentally, by the 100,000
rejection penalty being larger than any peak the site can reach (forward_proposer.py:297-301
states exactly this argument, and it is made only about the peak pass; there is no equivalent
argument for min_flow, whose objective scales a

*Fix:* Make the served set part of the lexicographic prefix. After pass 1, record `served_set = {aid
for served}` and thread it into every later pass as a hard constraint (`served[aid] == 1` for
each aid in served_set), or at minimum thread `min_served_count`. Report it in `optima` as
`served` so a later pass that could serve MORE is still allowed to, but none can silently swap
who is stranded.

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-21 · MAJOR · `core/policies/regime.py:89`
**ForwardOrchestratorPolicy.decide and RegimeOrchestratorPolicy.decide crash with KeyError on any rejected asset, though allow_rejection is an explicitly supported budget key**

Both `decide` methods build `starts` only from assets that have a charge op and then index it
for every arrival (`starts[a.aid]` in the sort key at regime.py:89 and forward.py:72). A
rejected asset leaves the plan with `ops: []` (model.py:762-764), so it is absent from `starts`.
`RegimeOrchestratorPolicy.__init__` takes a `budget` dict which is threaded straight into
`lexicographic_solve`, and `lexicographic_solve_traced`'s own docstring (forward.py:100-103)
advertises `allow_rejection` as a supported budget key. So a supported configuration crashes
rather than abstaining — which also destroys the abstain-vs-crash distinction the rejection
feature exists to preserve.

*Fix:* In both `decide` methods, filter arrivals to those present in `starts` and return no Assignment
for the rest (the plan's own `proposals` list already carries them as `abstain: true`), e.g.
`for asset in sorted([a for a in arrivals if a.aid in starts], key=...)`. Add a test that runs
RegimeOrchestratorPolicy with allow_rejection on the narrowed scenario and asserts
len(assignments) == served count.

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-22 · MAJOR · `core/proposer/forward_proposer.py:341`
**The chain re-reports each pass's optimum as the shipped plan's KPI instead of measuring the plan, so a broken ceiling publishes a number the plan does not have**

The regime fire record sets `total_tardy_min = optima['min_tardy']`, `site_peak_kw =
optima['min_peak']`, `total_flow_min = optima['min_flow']` (forward_proposer.py:340-342). Those
are the values the 1st/2nd/3rd passes REACHED, not values measured from `final_plan`, which is
produced by a later pass. Nothing anywhere re-derives the three KPIs from the plan that actually
ships. The whole correctness of the published number therefore rests on the ceiling threading in
forward.py being right — the one thing finding #1 shows is untested. Doctrine 5 says no number
ships without a run ID; here the number ships without ever being measured against the artifact
it describes. Even in correct code it is

*Fix:* Compute the three KPIs from `final_plan` (tardy = sum of tardy_min, flow = sum of finish, peak =
max of the charge-segment kW step function) and report those, with the per-pass optima kept
alongside as `optima_reached`. Assert `measured <= optimum` for every earlier pass before
returning; a violation is a chain bug and should raise, not ship.

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-23 · MAJOR · `core/proposer/forward_proposer.py:308`
**The default (cheap) path's fire record has no `complete` field and never surfaces `retained_previous`, so a truncated two-pass plan is indistinguishable from a whole one to any uniform consumer**

The regime branch emits `complete` (line 346); the default branch's solver_record (lines
308-322) does not emit it at all, and neither branch records `retained_previous`. When pass 2
fails within budget, model.py:713 returns pass 1's plan with `retained_previous=True` and pass
1's `repro` dict attached — so `final_plan = pass2` is really pass 1's schedule, yet the record
reports `reproducible: true` (both repro dicts are the same object's contents) and no
completeness signal. A caller reading `solver.get("complete")` — the field the regime path
taught it to read — gets `None` on every default-path invocation and cannot distinguish 'field
absent because this is the two-pass path' from 'plan i

*Fix:* Emit `complete` on BOTH branches with the same meaning: for the default path, `"complete": not
pass2.get("retained_previous") and pass1["solver_status"] == "OPTIMAL" and
pass2["solver_status"] == "OPTIMAL"`. Also add `"retained_previous":
bool(pass2.get("retained_previous"))` and gate `reproducible` on it the way the regime path does
(line 348). For deterministic_time, read pass 2's own solver tim

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-24 · MAJOR · `core/proposer/forward_proposer.py:101`
**One vehicle row with a NULL target_soc (or NULL soc) destroys the entire batch with a raw RuntimeError instead of producing an ABSTAIN row**

The default serviceability predicate compares SoC against `float(v.get("target_soc") or 100)`
(line 101) while the scenario builder writes `int(v.get("target_soc") or 90)` (line 145). The
two defaults disagree. A vehicle with a NULL target_soc and SoC between 90 and 100 therefore
passes the serviceability test (95 < 100) and is then admitted to the model with target_soc=90 —
a target BELOW its current charge, which the model cannot satisfy. build_and_solve raises
`RuntimeError: no schedule and no previous plan: INFEASIBLE` (model.py:716) on pass 1, which has
no previous_plan, and the exception propagates through propose() and orchestrate() — so every
healthy vehicle in the frame loses its pr

*Fix:* Use one default for target_soc in both places (compute it once per vehicle and reuse). Then, in
the frame_to_scenario loop, add a guard alongside the existing abstention checks: if `soc` is
missing/None, or if the resolved `target_soc <= soc`, append `_abstain(v, ...)` with the reason
rather than admitting the row. Add tests for a NULL-soc row and a target-below-soc row asserting
`planned == 0, ab

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-25 · MAJOR · `core/proposer/forward_proposer.py:215`
**The advisory row discards the charging taper: requested_kw is only the first segment's kW while planned_start/planned_end span all segments**

`"requested_kw": charge["segments"][0]["kw"]` publishes one power figure, but the model
deliberately produces multi-segment charge ops to honour the piecewise energy curve above ~70%
SoC (CLAUDE.md 2.5 names this a modelling requirement that bites). The rationale on the same row
carries `planned_start_min` and `planned_end_min` spanning the WHOLE op (lines 218-219), so the
row invites — and the SDR/settlement substrate downstream will perform — the computation kW x
duration. Nothing on the row says a taper was dropped. Since CLAUDE.md 2.6 makes every completed
operation terminate in a ServiceDetailRecord built from this substrate, the discarded taper
propagates into settlement and into any p

*Fix:* Carry the full profile on the rationale — `"segments": charge["segments"]` — and add
`"planned_kwh"` computed from all segments, keeping `requested_kw` as the peak segment for the
gate router's existing single-valued contract. That preserves the existing consumer while making
the taper recoverable and the energy figure honest.

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-26 · MAJOR · `core/proposer/forward_proposer.py:346`
**The proposer's `complete` and `reproducible` honesty flags can be hard-coded True with all 267 tests green**

`"complete": all(optima.get(m) is not None for m in modes)` (line 346) and `"reproducible":
bool(not final_plan.get("retained_previous") and all(p.get("reproducible") for p in passes))`
(lines 347-349) are the two fields the module's own docstring calls the fire record's honesty:
"solver[\"reproducible\"] then reports whether the clock was what stopped the search, so
'truncated by the clock' stays distinguishable" (line 255-257), and "complete == every pass in
the regime held an optimum … never silently claimed" (line 344-345). Every test that reads them
reads them on the happy path and asserts True (`test_regime_path_runs_the_regimes_pass_order`
asserts `s["complete"] is True`; nothing asse

*Fix:* policies/test_regime.py already knows how to force a retained pass
(`test_chain_reports_an_unreachable_ceiling_as_none` uses `budget={"det_budget_s": 0.4}` with a
flow-first chain). Push the same case through `propose(..., hour_of_day=7, det_budget_s=0.4)`
and assert `s["complete"] is False`, `s["site_peak_kw"] is None`, and `s["reproducible"] is
False`. Add the symmetric case with `time_limit_s`

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-27 · MAJOR · `core/solvers/cpsat/model.py:759`
**Every rejection ships the same hardcoded reason -- 'no feasible point within the site's capacity' -- which is false for economic, budget-truncated, and zero-demand rejections**

_extract writes one literal reason string on every abstain proposal, regardless of why the
solver declined. The distinctions it erases are exactly the ones the doctrine says must stay
visible ('never invoked' vs 'invoked and abstained'): (a) the site genuinely could not fit the
asset; (b) the site COULD fit it and the objective preferred not to (finding above); (c) the
search ran out of deterministic budget and dropped assets as a feasibility escape hatch; (d) the
asset needed no charge at all. Cases (b), (c) and (d) all ship a factual claim about site
capacity that is untrue, into ottoq_external_proposals rows that a human or the dispose path
will read as evidence the site was full.

*Fix:* Compute the reason per asset from facts already in hand: no candidate chain built -> 'no
capable/unblocked point on site'; chains built but empty segments -> 'already at target SoC';
chains built and status != OPTIMAL -> 'declined within the solver budget (status FEASIBLE); not
a capacity finding'; chains built and status == OPTIMAL -> 'declined on objective cost, not
capacity'. Carry the solver s

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-28 · MAJOR · `core/solvers/cpsat/model.py:564`
**blocked_points is ignored for service-bay (inspect) assignment: the plan schedules work on an out-of-service bay**

The rolling re-solve contract is that a point in `blocked_points` takes no NEW work. That filter
is applied to charge candidates (line 376) and to wash candidates (line 535) but the inspect
loop at line 564 iterates `svc_points` with no blocked check at all. A service bay taken out of
service is still handed inspections. SOLVER_STATE.md and T6 both state the blocked-point
property generally ('no new work on the blocked point'), and T6 only ever blocks a DCFC, so
nothing catches it.

*Fix:* Apply the same guard the other two paths use, inside the `for p in svc_points` loop:     if
p['id'] in blocked and (asset.aid, 'inspect') not in pinned:         continue and extend T6 to
block a service bay (and a wash bay) in addition to a DCFC, so the property is asserted for
every point kind rather than one.

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-29 · MAJOR · `core/solvers/cpsat/model.py:546`
**A rejected asset's inter-point move intervals are non-optional and still consume the shared path resource, causing spurious INFEASIBLE**

The wash move (lines 543-546) and the inspect move (lines 570-573) are built with
`m.NewIntervalVar(...)` -- unconditional -- and appended straight to `path_intervals`, which
feeds `AddCumulative(path_intervals, [1]*n, site['path_capacity'])`. Every other resource an
unserved asset would touch is correctly gated: its charge occupancy is optional on the point
literal, and _exactly_one_if_served zeroes its wash/inspect bay literals. The moves are the one
leak. So an asset the solver declines still books yard-path capacity for a trip nobody makes.
This is the same class of bug the file's own comment at line 589 calls out ('rejection has
exactly one price') -- except here rejection is not overpr

*Fix:* Make both move intervals optional on the same literal that gates the rest of the asset's work:
`mv = m.NewOptionalIntervalVar(ms, site['move_duration_min'], me, served if served is not None
else m.NewConstant(1), ...)` -- or, cleaner, gate on the corresponding wash/inspect point
literal so the move exists exactly when the operation it precedes exists. Add a test on the
probe7 shape: same site, sam

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-30 · MAJOR · `core/solvers/cpsat/model.py:433`
**min_gap_min is honored only on charge points; a wash bay or service bay declaring it is silently ignored, and the conformance harness disagrees**

`min_gap_min` is a generic per-service-point field in PACK_SPEC.md:45 ('exclusive',
'min_gap_min') and MULTIMODAL.md describes it as a pad clearance / swap-dock reload -- a
property of a POINT, matching CLAUDE.md 2.5 ('minimum-gap constraint on the SERVICE POINT').
model.py reads it in exactly one place, inside the charge-candidate loop, and adds it to the
charge occupancy interval. Wash intervals (line 538) and inspect intervals (line 566) are plain
fixed-duration intervals with no gap extension, so a pack that declares min_gap_min on a wash
bay, a decontamination bay, a calibration bay, or any non-charge point gets a plan that silently
violates its own declared constraint. conformance/harn

*Fix:* Extend the point-side occupancy of wash and inspect by that point's min_gap_min, exactly as the
charge occupancy does: build the bay interval with a variable end `op_end +
int(p.get('min_gap_min', 0))` for the copy that goes into per_point_intervals, while the asset-
side interval keeps the true duration. Add a test that a non-charge point declaring min_gap_min
actually produces that gap between co

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-31 · MAJOR · `core/tests/test_separation.py:40`
**intent/ is imported by two declared-kernel packages but is excluded from every separation guard, so the network/DB/file-read bans do not apply to it**

`KERNEL_PACKAGES` lists policies, solvers, sites, wear, onboarding, conformance, recall,
adapters, metrics, proposer — but NOT `intent`. Yet `policies/regime.py:33-34` and
`proposer/forward_proposer.py:64` (and `proposer/orchestrate.py:42` on PR #176) import
`intent.*`, so two guarded kernel packages depend on an unguarded package. Three separate
guarantees leak through the hole: (a) FORBIDDEN_IMPORTS
(supabase/psycopg/requests/httpx/urllib.request/twin) is not applied to intent/; (b)
FORBIDDEN_LITERALS (the production project refs) is not applied to intent/; (c) the
ALLOWED_READS allowlist test only inspects a file's own source text for `read_text|json.load`,
so `policies/regime.py:39` — `I

*Fix:* Add "intent" to KERNEL_PACKAGES (tests/test_separation.py:40-42) and add `("intent/intent.py",
"world")` to ALLOWED_READS with its reason (loading the declared doctrine artifact). Add
`policies/regime.py` to the `strict` list, and make that test transitive-aware — or move the
`load_intent()` call out of module scope into an explicit argument/lazy accessor so regime.py
genuinely takes its world as

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-32 · MAJOR · `core/tests/test_separation.py:174`
**The advisory-boundary guard never inspects the forward_lex rows, though it declares it covers 'both emitters' — command keys pass CI undetected**

`_emitted_proposal_rows()` is documented as 'Every row both emitters produce' and
`_ADVISORY_SOURCES = ("cpsat", "forward_lex")`, but the helper only calls
`model.build_and_solve(...)['proposals']`, which emits `source: "cpsat"`
(solvers/cpsat/model.py:844,866). The rows that `proposer/forward_proposer.plan_to_proposals()`
emits — `source: "forward_lex"`, the ones the README says an edge function inserts into
`ottoq_external_proposals` — are never passed through
`test_every_emitted_row_is_advisory_not_an_instruction`. The only other check on those rows,
`proposer/test_forward_proposer.py:92-100`, asserts the top-level key set exactly but the
payload only with `<=` (subset), so it cannot see

*Fix:* Extend `_emitted_proposal_rows()` to also build a small frame + class_table and call
`proposer.forward_proposer.propose(...)`, concatenating its `result['proposals']` (planned AND
abstain rows) before the assertions; assert the union of observed sources equals
`_ADVISORY_SOURCES` so a missing emitter fails the test instead of silently narrowing it.
Mutation-check the new coverage by injecting a co

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-33 · MAJOR · `intel/app/forecasters/priors.py:140`
**The priors fingerprint is self-certifying: it lives inside the file it protects and is pinned nowhere, so re-hashing after an edit ships contaminated priors under intact provenance labels**

load_priors reads the expected hash out of the same JSON blob it is hashing
(`fingerprint=manifest["fingerprint_md5"]`, priors.py:140, compared at 149-154). That detects
truncation and accidental corruption — nothing more. Any edit that also recomputes
`fingerprint()` (11 lines of code, exported from the same module) is accepted silently, the
`datasets` block still declares ACN/TLC/EIA/NREL, and every /forecast response still stamps
`provenance.source_name` and `priors_fingerprint` as if the number came from the public dataset.
No committed constant anywhere in the repo pins the expected value (see the T5 finding).
`load_priors` additionally takes an arbitrary `path`, so a caller can point i

*Fix:* Move the authority out of the artifact: (1) pin the expected md5 as a literal in a committed
test (see previous finding) so a prior change is a reviewed diff, not a silent one; (2) record
in the manifest, per dataset, the engine-side `ottoq_calibration_fingerprint()` value and the
source `date_range_start/end` and `record_count` at pull time, and assert the snapshot's per-
dataset content hash agai

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-34 · MAJOR · `intel/app/forecasters/priors.py:147`
**The priors fingerprint hashes DB fit timestamps, so a re-snapshot of numerically identical priors changes every forecast's identity**

`load_priors` builds the verified content as `{"datasets", "profiles", "distributions"}` and
md5s it whole. The `distributions` blobs each carry a `fitted_at` wall-clock timestamp copied
from the engine DB (`app/forecasters/priors_snapshot.json`: acn_data 2026-05-22
03:27:39.729512+00, eia_grid 2026-09-06 04:05:29.97135+00, nrel_fleet 2026-05-28
03:48:37.257882+00). The docstring of `fingerprint()` at priors.py:87-88 explicitly claims the
opposite -- "a refit that lands the same numbers is not a change to the world, so generated_at /
fitted_at are excluded from the hash where they are metadata rather than content" -- and nothing
excludes them. This fingerprint is not inert: `statistical._pro

*Fix:* Strip the metadata before hashing, the way intent.py's `_canonical` does. Add a
`_canonical_priors(raw)` that deep-copies and drops `fitted_at` from every distribution (and any
other provenance-only field) before `fingerprint()`, use it in both `load_priors` and whatever
stamps the snapshot, and re-stamp `manifest.fingerprint_md5` once. Then add a test that mutates
only `fitted_at` and asserts the

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-35 · MAJOR · `intel/app/forecasters/priors_snapshot.json:646`
**acn_data.hourly_charge_arrival_rate is indexed in UTC while consumed as site-local, and is combined at the same hour index with an explicitly America/Chicago EIA profile — the EV load forecast peaks 8 hours late**

The committed ACN profile puts its peak at hour 15 (multiplier 4.698, ~783 of 4000 sessions) and
its trough at hours 07-10 (0.096/0.066/0.036/0.024, i.e. 16/11/6/4 sessions), while describing
itself as workplace charging at "Caltech + JPL sites". Shifting it by -8h (UTC -> US/Pacific,
where both sites are) recovers the canonical workplace shape exactly: peak at 07:00, monotone
decay through the day, trough at 02:00, near-zero 23:00-04:00. The profile is UTC-bucketed.
forecast_load then evaluates it at the same `hod` as eia_grid.hourly_grid_demand_shape, which
the ingest builds explicitly in America/Chicago (core/edge-functions/ottoq-twin-
ingest/index.ts:32-36, `centralHour`), and as nyc_tlc.

*Fix:* Carry an explicit `tz` / `clock_basis` field on every hourly_24 profile in the snapshot (e.g.
"UTC", "America/Los_Angeles", "America/Chicago", "America/New_York"), refit the ACN profile in
America/Los_Angeles the way the EIA ingest already does with centralHour, and have
forecast_arrivals/forecast_load convert each profile from its declared basis to the site's
timezone before indexing. Add a test

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-36 · MAJOR · `intel/app/forecasters/statistical.py:308`
**fleet_energy_need_kwh p10/p90 are per-vehicle quantiles multiplied by fleet_size, not fleet quantiles — the published band is 3.7x too wide and its p90 has probability ~0**

forecast_soc_return computes `fleet_energy_need_kwh = {p: _need(e_p) * fleet_size}`. That is
"every vehicle simultaneously at its own 90th percentile", not the 90th percentile of the fleet
total. For n independent vehicles the aggregate band narrows as sqrt(n); at n=118 the reported
band is ~3.7x too wide in both directions. The p50 is also wrong, because `_need` is `max(0, e -
9)` — clamped and therefore nonlinear — so the sum of medians is not the median of the sum. This
is the number the module docstring calls "the 'how tight is tonight' number, and it is demand-
side only", i.e. the headline output of the whole forecast. The committed test at
tests/test_forecast_statistical.py:164 asserts

*Fix:* Compute the fleet aggregate as a convolution rather than a scaling. Cheapest correct form given
the committed 101-point grid: derive mu = E[need] and sigma^2 = Var[need] numerically over the
grid (both are one pass), then report fleet p10/p50/p90 as n*mu -/+ z*sigma*sqrt(n) with
z=1.2816 — for n>=30 this matches the Monte-Carlo above to under 1%. Keep
`energy_need_per_vehicle_kwh` as the per-vehic

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-37 · MAJOR · `intel/tests/test_forecast_statistical.py:75`
**The forbidden-identifier scan only matches bare ast.Name and whole string Constants — attribute access, kwargs, def names, bytes literals and split-string SQL all pass**

test_contamination_guard_no_sim_identifiers_in_code checks two node kinds: ast.Name (`node.id
not in FORBIDDEN_IDENTS`) and ast.Constant-of-str (substring match). Every other syntactic
position that can carry a forbidden table name is unchecked — ast.Attribute
(`db.ottoq_decisions`), keyword arg names (`f(ottoq_decisions=1)`), FunctionDef/ClassDef names
(`def ottoq_decisions()`), bytes literals (`b'... ottoq_decisions'`, because
`isinstance(node.value, str)` is False), and any string built by concatenation (`'ottoq_' +
'decisions'` is two Constants, neither containing the word). So the test that is supposed to
prove no sim/decision object is touched in code cannot see the most natural ways t

*Fix:* Add ast.Attribute (`node.attr`), ast.keyword (`node.arg`), FunctionDef/AsyncFunctionDef/ClassDef
(`node.name`), arg (`node.arg`) and alias (`node.asname`) to the identifier check, and match
ast.Constant bytes by decoding. For strings, also run a case-insensitive regex over the source
with docstring spans excised, rather than per-Constant substring matching, so concatenation
cannot split a token.

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-38 · MAJOR · `otto-q-core/intent/intent.py:134`
**An unknown or misspelled signal is silently discarded — resolve_intent drops the safety regime and returns a different solver pass order with no error**

`_matches` (intent.py:134-136) only tests `need.issubset(signals)`; nothing anywhere validates
the caller's signal names against the vocabulary the artifact declares. `resolve_intent`'s pass
1 (intent.py:197-199) therefore finds no signal regime and falls through to the clock pass,
returning a regime as if no signal had been raised. `intent_orchestrate` /
`RegimeOrchestratorPolicy` (policies/regime.py:47,74) take `signals: frozenset` straight from
the caller with no filtering. This is the exact hazard signals.py explicitly guards against on
the other side of the seam — the README states the bridge is TOTAL and "a missing field is never
silently treated as zero, which would hide a real surge

*Fix:* Derive the declared signal vocabulary at load time — `Intent.known_signals = frozenset(s for r
in regimes for s in r.match.get("signals", []))` — and have `resolve_intent` raise on `signals -
intent.known_signals` (e.g. `ValueError("unknown signal(s) {...}; declared: {...}")`), matching
signals.py's ForecastContractError discipline. Add a test asserting a one-character typo raises
rather than reso

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-39 · MAJOR · `pr176/policies/regime.py:39`
**A failed intent-artifact fingerprint makes `import forward_proposer` fail, taking down the cheap default path that never consults the intent**

`INTENT = load_intent()` runs at module import. forward_proposer.py:65 imports `resolve_active`
from that module unconditionally, so importing the proposer at all reads and fingerprint-
verifies intent_v1.json. Failing closed on a tampered artifact is correct policy for the regime
path; the problem is blast radius. The default two-pass path (hour_of_day=None) is documented at
forward_proposer.py:287-291 as 'byte-for-byte what propose() did before the intent layer' and
consults no doctrine whatsoever, yet it cannot be reached at all when the artifact is bad. The
failure also surfaces as a bare ValueError raised during module load rather than as a named
refusal at a call site, so an edge-functi

*Fix:* Make the intent import lazy inside the `else:` regime branch of propose()
(forward_proposer.py:330), or wrap the module-level load so `INTENT` is a lazily-resolved
accessor. Then a bad artifact raises a named error only on the regime path — the path that
actually depends on it — and the cheap default path keeps running, which is what 'the site is
never without a schedule' means.

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-40 · MAJOR · `pr176/proposer/README.md:6`
**The right-of-first-refusal deferral is hardcoded to cuOpt: a forward_lex proposal gets no deferral window and is outranked by cuOpt in the consumer's ORDER BY, contradicting the README**

proposer/README.md and forward_proposer.py's module docstring both state that whoever inserts
these rows gets "the deferral pattern gives an in-flight proposal its one-tick right-of-first-
refusal" and that "the deferral table and gate router need nothing new." The live mechanism is
source-specific in three places: (1) `ottoq_cuopt_first_refusal_arm` only arms a vehicle when no
pending proposal exists with `p.source IN ('cuopt','cuopt_fallback')` and writes to
`ottoq_cuopt_deferrals`; (2) the arming cap is the policy key `cuopt_first_refusal_max_defers`;
(3) `ottoq_l2_external_proposal` selects the winning proposal with `ORDER BY (p.source =
'cuopt') DESC, (p.source = 'cuopt_fallback') DESC,

*Fix:* Either (a) generalize the mechanism — parameterize `ottoq_cuopt_first_refusal_arm` and the
deferral table by proposer source, and replace the hardcoded ORDER BY with a policy-driven
precedence list — or (b) correct proposer/README.md and the forward_proposer docstring to say
plainly that the deferral pattern is cuOpt-only today and that forward_lex rows currently race
the decide path with no prote

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-41 · MAJOR · `pr176/proposer/forward_proposer.py:121`
**class_table has no production producer: the decision frame does not emit the join key, and ottoq_vehicle_classes uses different column names — passing its rows verbatim raises KeyError**

forward_proposer indexes class_table by the frame's `platform` value ('waymo'/'tesla'/'zoox')
and reads `cls["battery_kwh"]`, `cls["max_charge_kw"]`, `cls.get("charge_kinds")`,
`cls.get("energy_curve")`. The README says "in production that join is ottoq_vehicle_classes."
It is not joinable as written: (1) `ottoq_vehicle_classes` has no `platform` column — it is
keyed by `vehicle_class_code`; (2) `ottoq_build_decision_frame` emits `platform`, `make`,
`model` but NOT `vehicle_class_code`, even though 220 of 221 autonomous vehicle rows carry that
column, so the join key is absent from the declared input; (3) the columns are named
`battery_capacity_kwh` and `max_charge_rate_kw`, not `battery_kwh

*Fix:* Add `'vehicle_class_code', v.vehicle_class_code` to ottoq_build_decision_frame's vehicle object
(one migration, backward-compatible), re-key class_table on vehicle_class_code, and write the
explicit projection ottoq_vehicle_classes -> {battery_kwh: battery_capacity_kwh, max_charge_kw:
max_charge_rate_kw, charge_kinds: derived, energy_curve: energy_curve} as a committed function
with a test that ro

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-42 · MAJOR · `pr176/proposer/forward_proposer.py:126`
**charge_kinds silently defaults to (dcfc, l2) — the field that decides which stall type a vehicle may be sent to — and produced a physically impossible assignment for a PAD-inlet AMR**

Line 126 reads `ck = tuple(cls.get("charge_kinds", ("dcfc", "l2")))`. The README states the
opposite discipline for exactly this kind of field: "There is NO default — a made-up battery
size is a silently wrong plan for every vehicle." But battery_kwh is required (KeyError) while
charge_kinds — which alone determines the set of service points a vehicle is allowed onto —
silently defaults to both charging types. Since ottoq_vehicle_classes has no charge_kinds column
at all (finding 4), every production-derived class_table will hit this default. The consumer
function ottoq_l2_external_proposal validates stall occupancy, reservation, charger
station_state and heartbeat, but NOT inlet compatibili

*Fix:* Make charge_kinds required in class_table (raise FrameError naming the class, like battery_kwh
does), and additionally filter candidate points by inlet compatibility using the frame's
`inlet_type` and the stall's `connector_type`, both of which the frame already carries and
neither of which frame_to_scenario currently reads. Add a test asserting that a PAD-inlet asset
never receives a dcfc or l2 p

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-43 · MAJOR · `pr176/proposer/orchestrate.py:86`
**The audit trail drops the two identifiers reproduction actually requires: the OR-Tools version and the intent artifact's fingerprint/version**

The handoff claims the trail walks 'forecast number -> signal -> regime -> pass order ->
optima'. Each of those links is a real recorded value (the same `assessment` object is both
passed to propose() as `signals=` and serialized to the result, and
`pass_modes`/`passes`/`optima` are the solver's own returns — I confirmed no re-derivation). But
two keys required to reproduce the run are discarded. (1) model.py:719-726 states in its own
comment that reproducing a run REQUIRES the OR-Tools version, and records it as
`plan["repro"]["ortools_version"]` — forward_proposer's solver_record (lines 308-322 and
334-353) and forward.py's per-pass trace (lines 154-158) both drop it, so the fire record ca

*Fix:* Add `"ortools_version": pass1["repro"]["ortools_version"]` (and `det_budget_s`/`wall_limit_s`)
to solver_record on both branches, and in orchestrate() add `result["intent"] = {"version":
regime.INTENT.version, "fingerprint": regime.INTENT.fingerprint}` so the pass order is
attributable to a specific doctrine artifact.

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-44 · MAJOR · `pr176/proposer/orchestrate.py:80`
**orchestrate()'s audit trail drops the forecast's own identity, so a fire record built from its return value cannot satisfy "no number ships without a run ID"**

The module docstring promises "THE AUDIT TRAIL ... so an auditor can walk 'why did the engine
schedule throughput-first at 07:00?' back to the forecast number that triggered it." The result
carries the measured value and the threshold, but not WHICH forecast produced that value. The
/forecast output dict carries `forecast_generated_at` and `priors_fingerprint` (the priors are
versioned and hashed precisely so a forecast is identifiable), and the intent artifact carries a
verified fingerprint (intent/test_intent.py::test_intent_fingerprint_verifies) — none of the
three appears anywhere in the returned dict. There is also no sim_run_id, scenario seed, or
config_hash. Combined with the fact tha

*Fix:* In orchestrate(), copy `forecast.get('forecast_generated_at')` and
`forecast.get('priors_fingerprint')` plus the resolved intent artifact's fingerprint into a
`provenance` block on the result, and require the caller to pass a run identifier that is echoed
back. Then define the fire-record table (extending ottoq_run_archives per CLAUDE.md C6 rather
than a parallel table) so the block has somewhere

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-45 · MINOR · `core/intent/learn.py:125`
**Refusal.rule_code is accepted and then never read — the 52-rule shield's own 2,967 failures cannot influence any classification**

The Refusal dataclass declares `rule_code: str | None = None`, and the module header calls what
it reconciles "the shield's refusals" — the shield being the 52-rule deterministic layer. But
_normalize (line 163-171) extracts only reason_code and entity_id; rule_code appears nowhere
else in the file. It is accepted, carried, and discarded. Meanwhile the actual rule shield
records its refusals in public.ottoq_rule_evaluations (passed=false, rule_code, free-text
reason) — 2,967 failures across 4 rule codes — on a channel with no coded vocabulary and no path
into this module at all. So the field advertises a capability the module does not have, and the
layer named in the doctrine as the clean al

*Fix:* Either use it — carry rule_code into the flag messages and key live_world repetition on
(reason_code, rule_code, entity_id) so a stuck rule is distinguishable from a stuck resource —
or drop the field and say plainly in the header that this module reconciles the command-
preflight refusal vocabulary (ottoq_vehicle_commands.reason_code), not ottoq_rule_evaluations,
with the rule-shield channel named

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-46 · MINOR · `core/intent/signals.py:217`
**Negative forecast values and string-typed numbers pass the TOTAL seam silently**

Beyond NaN, the seam accepts values that are physically impossible for the quantities involved.
expected_arrivals=-500 is consumed as -498.0 total arrivals; total_kw_p90=-9e9 is consumed as a
site load. A string that happens to parse ('900', '24') is coerced without complaint, so a JSON
contract drift from number to string is invisible; a string that does not parse ('lots') escapes
as a bare ValueError rather than the module's ForecastContractError, and expected_arrivals=None
escapes as a bare TypeError — both breaking the documented "a malformed forecast raises
ForecastContractError" contract that callers would catch on.

*Fix:* In the same coercion helper proposed for the NaN finding: require `isinstance(x, (int, float))
and not isinstance(x, bool)` (reject strings outright rather than coercing), require finite, and
require >= 0 for both arrivals counts and kW. Wrap the whole coercion so every rejection
surfaces as ForecastContractError naming the field and the offending value.

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-47 · MINOR · `core/intent/signals.py:186`
**now_hour accepts True/False as hours 1/0 — bool slips through the isinstance(int) bounds check**

`isinstance(now_hour, int)` is true for bool in Python, so now_hour=True is silently treated as
hour 1 and now_hour=False as hour 0. The check at signals.py:186 is otherwise the module's
strictest input guard, and test_now_hour_is_bounds_checked (test_signals.py:174-178) covers -1,
24 and '7' but not the bool case, so the gap is untested.

*Fix:* `if isinstance(now_hour, bool) or not isinstance(now_hour, int) or not (0 <= now_hour <= 23):
raise ValueError(...)`. Add True and False to the `for bad in (...)` tuple at
test_signals.py:175.

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-48 · MINOR · `core/intent/signals.py:131`
**_hour_map's `key` argument is dead; the contract error it raises cannot name which forecast section failed**

_hour_map(section, key) never reads `key`. The error message at signals.py:137 instead does
`section.get('kind', '?')`, i.e. it trusts the malformed input to identify itself. Both call
sites (signals.py:199-200) pass the correct literal name and it is discarded. When the section
is malformed in the way that drops or never had a 'kind' field, the operator gets an error that
names no section at all.

*Fix:* Use the parameter that is already being passed: `f"forecast[{key!r}] has no 'hours' list —
nothing to derive a signal from"`. Same fix for the 'a forecast hour entry is malformed' message
at signals.py:142-143, which also names no section.

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-49 · MINOR · `core/intent/test_learn.py:114`
**`test_a_missing_reason_code_is_skipped_as_malformed_input` passes two well-formed refusals and never exercises a missing reason_code**

The test body is `reconcile_refusals([Refusal("superseded"), Refusal("superseded")])` — both
records carry a valid string reason_code. No record with a missing or None reason_code is ever
constructed, so the guard it names (`intent/learn.py:170`, `if isinstance(rc, str):` inside
`_normalize`) is never reached on the failing branch. The test is indistinguishable from a plain
counting test.

*Fix:* Actually pass a malformed record:      class Row:         reason_code = None         entity_id =
None     r = reconcile_refusals([Refusal("superseded"), Row(), Refusal("superseded")])
assert r.counts == {"superseded": 2}     assert r.unknown_codes == ()

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-50 · MINOR · `core/policies/forward.py:140`
**Dead-but-armed fallback turns a tardiness or flow objective into a kW ceiling if the early return is ever removed**

`max_peak = int(plan.get("site_peak_kw", plan["objective"]))` (forward.py:140). `site_peak_kw`
is emitted only when a min_peak pass actually solved (model.py:812-813), so the fallback fires
exactly when the pass FAILED and a retained plan came back — and the retained plan's `objective`
is the previous pass's, i.e. total tardy-minutes or total flow-minutes, or with rejection on, a
value inflated by 100,000 per rejected asset. `optima['min_peak']` is then overwritten with None
three lines later (forward.py:170-172) and the function returns, so today the value is
discarded. The only thing standing between a flow-minute count and a kW ceiling is the ordering
of two statements, in the one functio

*Fix:* Drop the fallback: read `max_peak = plan["site_peak_kw"]` and let a KeyError be the loud
failure, or check `retained_previous` BEFORE computing any optimum (which also fixes finding
#3's trace leak in the same move).

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-51 · MINOR · `core/proposer/forward_proposer.py:132`
**The R-11 chemistry cap is dropped on the production path: frame_to_scenario never copies max_daily_soc_pct, so _clamp_target is a no-op on every live proposal**

_clamp_target (model.py:144-154) and T13 assert that an NMC class caps daily target SoC at 80%,
and R-11 records that as the grounding for the objective. The clamp only fires when the
scenario's asset_classes entry carries max_daily_soc_pct. frame_to_scenario builds each class
dict from an explicit five-key literal -- battery_kwh, max_charge_kw, inlet, charge_kinds,
energy_curve -- so even when the class table declares max_daily_soc_pct=80 the field never
reaches the model and the vehicle's raw target_soc (default 90) is used unclamped. The two
committed canonical scenarios are the only place the cap is live; scenario_deck.json and
scenario_vertiport.json do not declare it either.

*Fix:* Pass the field through in classes.setdefault: `**({'max_daily_soc_pct':
cls['max_daily_soc_pct']} if 'max_daily_soc_pct' in cls else {})`, and add a bridge test that a
class table declaring the cap produces a clamped target_soc in the materialized scenario.
Otherwise scope the claim honestly to the two scenario files that carry it.

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-52 · MINOR · `core/proposer/forward_proposer.py:330`
**The commander's intent is a single process-global artifact on both production entry points — no per-pack or per-tenant intent can be supplied**

`policies/regime.py:39` binds `INTENT = load_intent()` — the default `intent/intent_v1.json` —
at import scope. `resolve_active()` and `intent_orchestrate()` accept an `intent=` override, but
the two callers that matter drop it: `forward_proposer.propose()` calls
`resolve_active(hour_of_day, signals)` with no intent (line 330), and
`RegimeOrchestratorPolicy.__init__` (regime.py:74) exposes hour_of_day/signals/budget but no
intent. The artifact itself is robotaxi-flavoured in places the kernel then reads
unconditionally (service_completion's metric is 'wash/tire/brake/software/inspection/calibration
completed before must-by window'; staff's solver_wiring says 'a packing objective in the robot

*Fix:* Thread the override that already exists: add `intent=None` to `propose()` and to
`RegimeOrchestratorPolicy.__init__`, pass it down to `resolve_active`, and make
`load_intent(path)` the pack's responsibility (`packs/<pack_id>/intent_v1.json`, falling back to
the kernel default). Add an `intent` (or `objectives`/`regimes`) section to PACK_SPEC.md so a
pack can declare its own priority orderings decl

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-53 · MINOR · `core/sites/site_alpha/harness_alpha.py:375`
**site_alpha's CP-SAT solve binds a wall-clock limit and records no reproducibility flag when it fires**

SCOPE NOTE: sites/ was not in my enumerated file list, but this is the exact defect class the
dimension asked me to look hardest for, and it is the only place in the repo that still does it.
`cpsat_alpha` sets `solver.parameters.max_time_in_seconds = 600.0` alongside the deterministic
budget. solvers/cpsat/model.py:782-790 documents at length why this is forbidden -- "THE BINDING
LIMIT IS DETERMINISTIC WORK, NOT WALL-CLOCK TIME... under CPU contention the same seed yields a
different plan (measured -- see test T1b). It is set ONLY if a caller explicitly asks for a
wall-clock bound, and doing so is recorded in the plan" -- and model.py accordingly emits
`repro.reproducible = False` whenever a

*Fix:* Drop line 375, or -- if a hang backstop is genuinely wanted -- keep it and carry model.py's
bookkeeping: record `wall_limit_s` on the cell and set a `reproducible: False` field whenever
the status is not OPTIMAL and a wall limit was set, so run_matrix's artifacts can never cite a
clock-truncated plan as seed-reproducible.

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-54 · MINOR · `intel/app/forecasters/priors.py:128`
**Distribution.mean_value / stddev_value / hard_min / hard_max are declared float|None but load as str, and hard_min/hard_max are never enforced anywhere**

load_priors coerces sample_count with int() and quantile_grid with float(), but assigns
mean_value, stddev_value, hard_min and hard_max straight through with `d.get(...)`. Every one of
those fields is a JSON string in the committed snapshot, so a Distribution frozen dataclass
annotated `mean_value: float | None` actually holds `'9.0182'`. statistical.py only survives
because forecast_load wraps both in float() at lines 203-204. hard_min/hard_max are loaded and
never read by any code path, so the declared bounds on all five distributions are decorative —
the forecast never clamps to them.

*Fix:* In load_priors, coerce with a small helper: `_f = lambda v: None if v is None else float(v)`
applied to mean_value, stddev_value, hard_min and hard_max. Then add a load-time validation that
every quantile_grid is monotone non-decreasing and lies within [hard_min, hard_max], raising the
same way the fingerprint mismatch does — that turns the declared bounds into an enforced
invariant instead of doc

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-55 · MINOR · `otto-q-core/intent/intent.py:28`
**The fingerprint covers only four hardcoded top-level keys — the manifest (including the declared version and kind) and any injected top-level key are unauthenticated and accepted**

`CANONICAL_KEYS` (intent.py:28) is a fixed allowlist of four keys, and `_canonical`
(intent.py:83) projects onto exactly those. Everything else in the document is outside the hash:
the whole `manifest` block and any key a future editor adds at the top level. The docstring
justifies excluding `fingerprint_md5` and `generated_at` (correct — they are the hash and its
timestamp), but the exclusion is applied to the entire manifest, so `version`, `kind`, and
`description` ride along unauthenticated. `Intent.version` (intent.py:117) is then constructed
from `manifest["version"]`, i.e. the loader returns a verified-looking object whose version
field the verification never covered. Blast radius is b

*Fix:* Hash everything except the two self-referential manifest fields rather than allowlisting four
keys: build the canonical dict as a deep copy of `raw` with `manifest.fingerprint_md5` and
`manifest.generated_at` removed. That authenticates `version`/`kind` and makes any future top-
level key covered by default instead of covered only if someone remembers to extend
CANONICAL_KEYS. Add an assertion that

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-56 · MINOR · `otto-q-core/intent/intent.py:146`
**"Floors are structural" is enforced from a hardcoded Python tuple, not from the artifact's own kind field — a new objective declared kind:"floor" is dropped by every regime that does not list it**

There are two independent definitions of "floor". `CANONICAL_FLOORS` (intent.py:146) is a Python
constant of two literal names, and `_build_active` (intent.py:161) prepends only those. But
`ActiveIntent.floors` (intent.py:165-166) is computed from the artifact's declarative `kind ==
"floor"` field. For any objective the artifact declares as a floor but that is not one of the
two hardcoded names, the prepend does not fire — which is precisely the failure the
resolve_intent docstring says the mechanism prevents ("A regime that omits a floor must not be
allowed to drop it"). The prepend does work correctly for a newly added *regime* (verified
below), so the invariant holds along the axis the de

*Fix:* Derive the floor set from the artifact instead of hardcoding it: in `_build_active`, `canonical
= tuple(k for k in CANONICAL_FLOOR_ORDER if k in intent.objectives) + tuple(k for k, o in
sorted(intent.objectives.items()) if o.kind == "floor" and k not in CANONICAL_FLOOR_ORDER)` —
keeping the two named floors' canonical order while making any artifact-declared floor
structurally un-droppable. Then c

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### L-57 · MINOR · `pr176/proposer/orchestrate.py:50`
**orchestrate() has no cheap mode: now_hour is mandatory, hour_of_day is always forwarded, and a caller cannot override it — the 10-20x regime path stops being opt-in at the conductor**

propose() correctly defaults to the cheap two-pass solve (hour_of_day=None, line 236) and its
docstring at 287-291 justifies the opt-in on cost: the third lever 'does not prove OPTIMAL and
costs ~10-20x the two-pass solve -- fine for offline planning, too slow for the live tick'.
orchestrate() makes `now_hour` a required keyword (line 50) and hard-wires
`hour_of_day=now_hour` into the propose call (line 83), so every conductor invocation takes the
expensive path. There is no `regime=False` escape, and passing `hour_of_day=None` through
`**propose_kwargs` is a TypeError, not an override. orchestrate's own docstring carries no cost
warning at all, while positioning the module as the runtime re

*Fix:* Add an explicit `regime: bool = True` parameter to orchestrate() and pass `hour_of_day=now_hour
if regime else None`, so a live-tick caller can get the signal assessment and the cheap two-pass
solve together. Guard `**propose_kwargs` against the keys orchestrate already binds (`site`,
`hour_of_day`, `signals`) and raise OrchestrateError naming the conflict instead of a bare
TypeError. State the co

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix


## D — CLAIMS AND DOCS

### D-01 · MAJOR · `core/intent/learn.py:36`
**The module header states three times that an unknown reason_code raises; it does not, and a caller who believes the header never checks unknown_codes**

Three statements in the file assert raising behaviour that the code does not have:   line 36-37:
"Every seam is TOTAL: an unknown code raises rather than silently passing (the AGENTS.md total-
function rule)."   line 112:  "so a test can pin that the taxonomy is TOTAL over it and an
unknown code raises."   line 299:  "(Contrast with refusal reason_codes, which ARE a constrained
vocabulary and therefore raise.)" reconcile_refusals contains no raise statement at all; it
returns unknown codes in ReconciliationReport.unknown_codes, which its own docstring (line
178-180) correctly describes. The file therefore contradicts itself, and the half a reader meets
first — the module header — is the false

*Fix:* Delete or correct all three statements to match the implemented contract: "an unknown
reason_code is surfaced in unknown_codes and makes the report not-clean; it never raises, so one
bad record cannot take down the batch — callers MUST check report.unknown_codes." Line 299's
parenthetical should be removed outright, since it asserts the opposite of the code in the same
file.

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### D-02 · MAJOR · `core/metrics/baseline_24h_seed424242.json:2`
**The committed 24h KPI baseline is stale — every guarded number in it is unreproducible from the committed seed, and the gate hides it**

`metrics/baseline_24h_seed424242.json` was last written at commit 4e69269.
`solvers/cpsat/model.py` has been changed three times since (918ff0f, a1829b2, 453ca50 "Two
criticals in the CP-SAT model"), and the baseline was never re-based. Regenerating the 24h
comparison from the same seed (424242) and the same pinned ortools 9.15.6755 now produces
different numbers for every guarded metric. `metrics/kpi_gate.py` only fails on `delta > allow`
(positive = regression), so a baseline that has drifted in the *improving* direction can never
trip the gate — the drift is silent, and the gate's own PASS line degrades from "byte-identical
to baseline" to "within thresholds" without failing anything. Eve

*Fix:* Run `python3 metrics/kpi_gate.py --rebaseline` and commit the diff as a deliberate, reviewed act
(the same discipline `REGEN_PLAN=1` enforces for plan_seed424242.json). Then make drift non-
silent: have kpi_gate.py fail, or at minimum exit non-zero in CI, when `comparison_sha256 !=
baseline.comparison_sha256` without an explicit `--allow-improvement` acknowledgement —
otherwise an improving-directi

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### D-03 · MAJOR · `core/policies/README.md:31`
**policies/README.md publishes a headline comparison table that no longer matches the committed seed-424242 artifact — every number is wrong**

The README's 'Headline (seed 424242, reduced canonical scenario)' table states fifo
621/0/340/9/636, greedy 0/22/402/9/227, otto_q_asis 395/74/392/9/551, cpsat 118/84/436/9/458.
The committed artifact `policies/comparison_seed424242.json` — which `policies/test_policies.py`
asserts byte-for-byte and which `run_comparison.py` regenerates to a MATCHING sha256 — holds
fifo 237/0/370/9/501, greedy 0/13/440/9/218, otto_q_asis 157/55/372/9/386, cpsat 0/90/550/9/270.
Not one cell agrees. The prose below the table is stale in the same way: it says cpsat
'deliberately trades tardiness minutes', while cpsat's actual total_tardy_min is 0.
SOLVER_STATE.md:407 already records that 'the 118 tardy minutes

*Fix:* Regenerate the table from `policies/comparison_seed424242.json` (and rewrite the 'Read honestly'
paragraph, which no longer describes the cpsat result), then make the drift impossible: add a
test that parses the README's markdown table and asserts each cell equals the committed artifact
— the same discipline OTTO-Defense already runs as `tools/narrative-check.mjs`. A doc number
that no test regene

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### D-04 · MINOR · `core/.github/workflows/verify.yml:20`
**The CP-SAT battery size is claimed three different ways (T1-T13 / 14-test / T1-T8) and none of them is right**

The handoff says "T1-T13". solvers/cpsat/README.md:11 says "14-test battery". The CI step name
in verify.yml:20 says "T1-T8". The battery actually runs T1 through T15 plus sub-tests T1b, T1c,
T1d and T9b — 19 PASS lines. Every one of the three published counts is stale, and they are
stale in different directions, so no reader can tell which one to trust or notice if a test
silently stops running.

*Fix:* Have the battery print its own count on the last line (`ALL TESTS PASS — 19 checks, T1..T15`)
and delete the hard-coded counts from README.md:11 and verify.yml:20, replacing them with "the
CP-SAT battery". A number that must be hand-maintained in three files is a number that will be
wrong in three files.

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### D-05 · MINOR · `core/proposer/forward_proposer.py:13`
**forward_proposer's stated second law says every proposal row 'expires'; no emitted row carries an expiry**

The module docstring states THE TWO LAWS, the second being 'No proposal is ever a command. Every
row is advisory, carries abstain semantics, and expires.' The rows built by `plan_to_proposals`
carry exactly `action_context, entity_type, entity_id, source, proposal{verb, abstain, stall_id,
stall_type, vehicle_id, requested_kw, rationale, resolved_action_context}` — there is no
`expires_at` or TTL anywhere in the module (grep for 'expire' matches only the docstring
itself). proposer/README.md is the accurate one: it puts `expires_at` on the caller ('inserts
the rows with sim_run_id/depot_id/expires_at'). So a law the module states about its own output
is in fact an unenforced obligation on an

*Fix:* Either emit the expiry — add a required `ttl_min`/`expires_at_min` to the row and assert it in
test_forward_proposer's exact key-set check — or reword law 2 to match the README: 'every row is
advisory and carries abstain semantics; the caller stamps expires_at on insert.'

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### D-06 · MINOR · `core/solvers/cpsat/plan_seed424242.json:571`
**Claimed "plan_seed424242.json sha256" is the schedule digest, not the file's sha256 — sha256sum does not match**

The handoff states "The frozen plan_seed424242.json sha256 is 2b7f40fb...". `2b7f40fb...` is the
value of the `plan_sha256` field *inside* the file — a sha256 over the canonicalized schedule
computed in solvers/cpsat/model.py:916 — not the sha256 of the file. `sha256sum` on the file
returns `6ea7d2af33c8...`. A reviewer told to verify the claim with the obvious command gets a
mismatch and concludes the artifact drifted, when it did not.

*Fix:* State it as "plan digest (plan_sha256) 2b7f40fb…; file sha256 6ea7d2af…" wherever it is quoted,
and change the battery's final print from `sha256 <plan_sha256>` to `plan_sha256 <...>` so the
tool stops teaching the mislabel. The underlying claim is CONFIRMED — the battery does compare
the full file text byte-for-byte and it reproduces.

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix

### D-07 · MINOR · `core/tests:1`
**"Was 201 at start of the magenta build" is wrong — the pre-magenta suite was 178 tests**

The first magenta commit is db60f42 ("Intent artifact", PR #171). Its parent cf80b05 — the true
pre-magenta tree — collects 178 tests, not 201. 201 is the count at 5cc49cd, which is the
*second* magenta commit, already inside PR #171's branch. The claim uses a mid-build number as
the starting baseline, understating the magenta layer's test contribution as 66 tests when it is
actually 89.

*Fix:* State the baseline as 178 at cf80b05 (the commit immediately preceding db60f42) and the delta as
+89, or name the exact commit the 201 was measured at so the number carries its own run ID.

- [ ] reproduced   - [ ] fixed   - [ ] pinned by a test that fails without the fix
