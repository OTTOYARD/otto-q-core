# Open items declared in a check file and not yet triaged into FINDINGS.md

**What this file is for, and what it is not.** `tests/test_open_items.py` requires every
`-- OPEN-ITEM:` marker in `db/checks/*.sql` to be tracked — either as a `G`-item in `FINDINGS.md`
or as an entry here. **FINDINGS.md is the register; this is the inbox.** An entry here means
*noted, findable, and not yet judged* — never *dismissed*.

**Why it exists, measured rather than assumed.** On 2026-09-20 Chase said: *"When you identify
things I need to be addressed. Do not lose track with them or pass over them. Either address them
immediately or immediately make note and continue working where you were. We can't afford to come
across something that needs to get fixed and then lose track of it because we're going down another
rabbit hole."* Scanning the check files for open-question prose that same night found **18 files
carrying one, of which 13 were referenced nowhere in FINDINGS.md**. The leak was real and it
predates the instruction by months.

**And four of those 13 were false positives** — the file said the question was *answered* later in
its own text. That is why the marker is an explicit `-- OPEN-ITEM:` line rather than a regex over
prose: a predicate that answers a looser question than the one asked is the exact defect this repo
keeps paying for (`0289`'s `offerable`, `0392`'s `resolved_action_context`, `0294` §2's own
confound). A guard built on prose matching would have cried wolf four times in thirteen and taught
everyone to ignore it.

**The nine below are the historical backlog**, carried forward unjudged. They are listed with what
each one actually leaves open, so the next reader can triage from this page without opening nine
files. They do NOT carry `-- OPEN-ITEM:` markers yet; they are grandfathered by number so the guard
can start protecting new work immediately rather than waiting on a triage pass.

- **0019** `wash_path_certification` — 9 wash paths done against 2 credited. May be an under-credit
  in the path accounting rather than work that did not happen; the file declines to call it a pass.
- **0063** `two_faults_in_how_a_pair_is_counted` — what, at tick 12, decided a vehicle was staged.
  Well posed by the file, not answered in it.
- **0078** `round_8_six_columns_one_pair_each_all_passed` — does the `LIMIT 20` seating cap actually
  bind on these runs? The file notes ten fresh arms now make it answerable and does not answer it.
- **0081** `the_stranding_count_is_zero` — §4's question needs a horizon that contains the plan, so
  the zero is bounded by the window rather than by the world.
- **0100** `the_phantom_was_kpi_five_all_along` — the file states its open question *stayed* open
  after the phantom was explained; it is not the same question the title closes.
- **0105** `the_sixty_minute_wait_was_the_clock_and_the_cold_start` — deferring an assignment is
  recorded as an open question rather than a defect. Whether the deferral is correct is undecided.
- **0175** `prediction_2_was_falsified_before_the_round_judged_it` — the grid depot's four vehicles
  carry a wall-clock `last_state_change`. Named as a new open question and explicitly not chased.
- **0208** `the_intelligence_layer_is_switched_off_at_a_dial_not_broken` — why did Nemotron stop on
  2026-08-30 when its gate defaults on? The four 08-30 decisions were `production_live`, and
  `production_live` stopped the same day. The file says it cannot answer this.
- **0283** `the_site_charge_cap_is_respected_on_ninety_six_percent_of_snapshots` —
  `ottoq_active_charge_cap_kw` filters `status='executed'` while the MPC supersedes (395 superseded
  against 1 executed), so **the function is correct for "now" and cannot answer a historical
  question, and nothing about it says so.** Left as an open question rather than dressed as an
  answer.

**Triage rule when one of these is picked up:** measure it, then either promote it to a `G`-item in
FINDINGS.md or close it in a new check file that says why it is not a finding — and delete its line
here. A line that leaves this file must land somewhere, never nowhere.
