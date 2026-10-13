# OTTO-Q agent architecture: one conductor, deterministic scouts, a research swarm behind the glass

*Written 2026-10-13 (CT). It answers Chase's question that morning: should OTTO-Q run one agent on top that scans everything, or
swarms of agents that spin up for each run, scan the vehicles, the depot and every other variable, and feed the proposal layer?
Every number here carries its run, check file or source URL. Where a figure is one run, it says so.*

## The decision

**Production keeps one LLM coordinator.** It is consulted when something it can act on has changed, not on every beat, and
it proposes typed actions that the deterministic kernel disposes. **The production "swarm" is deterministic:** a scout per
car and per resource, running in SQL every minute. They cost zero tokens, finish in milliseconds and give the same answer
twice. **Parallel LLM workers live only in the research wing**, offline, against recorded boards and the twin, where their
output becomes a recommendation a person ships (rule 10).

Per-run LLM swarms feeding the proposal layer are **not** recommended today. That is a finding, not a preference, and the
same section says what would change it.

## Why: five measured reasons and the outside evidence

1. **One agent already adds almost nothing measurable, and more agents would add more of the same.** On run `176b2912` (busy
   day, twin depot, the first run that kept every agent pass as evidence; `db/checks/0440`):
   - **79 passes changed engine state once.** 55 (70%) proposed the kernel's own charge order back, 13 issued directives
     only, 6 got no model answer, and 4 had no effect.
   - **The 12 orders that differed from the kernel's won in hindsight 6 times.** Across 9 earlier runs, 7 of 416 orders were
     taken (the study's lane on agent value).
2. **The disposer cannot yet rank what it receives.** The check's win probability scored the agent's missed wins *below* its
   right refusals on that run (0.37 against 0.43). Across 45-70 graded decisions on 4 seeds its AUC is 0.41-0.52, and its
   Brier score is worse than the base rate on every cut (G389). Add N proposers and you add N times the candidates to a
   comparison that cannot yet tell them apart. **The shortest path to agent value is the comparator, not more agents.**
3. **Nothing agent-on can be measured deterministically yet.**
   - The paired harnesses switch the agent off.
   - Live playback ties each tick's sim length to the database's load, so the same seed draws a different world after the
     first tick (0416).
   - Until 0703, the board the agent read was never stored.

   A swarm's claims would arrive without a run ID behind them.
4. **The binding constraint is chargers, not decisions.** On `176b2912` the depot spent the day with a mean of 53 cars in
   the charge line, about 0 chargers open and 46 cars past their 30-minute contract wait. 89 cars from the run's boot draw
   were still waiting 4 hours in. No proposal can seat more cars than there are free chargers. Rule 9's answers to site
   pressure are capacity, fewer charger faults, and better ordering of who is served next.
5. **Cost and fragility compound per agent.** One consult costs about 25,800 prompt and 1,400 completion tokens and a median
   59.5 s. The primary model answered 60 of its 91 attempts: 15 returned HTTP 503 and 16 timed out (G424).

**The outside evidence says the same:**

| Claim | Source |
|---|---|
| Across 180 configurations, every multi-agent variant made sequential, shared-resource planning 39-70% worse. Independent agents amplified errors 17.2x, against 4.4x with central coordination, and coordination stops paying once a single agent scores above about 45%. | Google Research, *Towards a Science of Scaling Agent Systems*, [arXiv 2512.08296](https://arxiv.org/abs/2512.08296v2) (v2 2025-12-17); [blog](https://research.google/blog/towards-a-science-of-scaling-agent-systems-when-and-why-agent-systems-work/) (2026-01-28) |
| Multi-agent gains are real for breadth-first research: +90.2% over a single agent, at about 15x the tokens of chat. | Anthropic, [multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system) (2025-06-13) |
| Parallel agents writing to shared decisions drift apart; keep one thread of context. | Cognition, [Don't Build Multi-Agents](https://cognition.com/blog/dont-build-multi-agents) (2025-06-12) |
| "To date, no commercial or industrial deployment of robot swarms has been reported." | Kegeleirs & Birattari, [Frontiers in Robotics and AI](https://www.frontiersin.org/journals/robotics-and-ai/articles/10.3389/frobt.2025.1607978/full) (2025-06-13) |
| Amazon's fleet coordination, DeepFleet, is one foundation model predicting robot motion, not a swarm of LLM agents. The best variant was robot-centric at 97M parameters. | [Amazon Science](https://www.amazon.science/blog/amazon-builds-first-foundation-model-for-multirobot-coordination) (2025-08-11); [arXiv 2508.08574](https://arxiv.org/abs/2508.08574) |
| Where parallel LLMs pay is offline search with an evaluator. AlphaEvolve's scheduling heuristic recovers 0.7% of Google's fleet-wide compute. | [DeepMind](https://deepmind.google/discover/blog/alphaevolve-a-gemini-powered-coding-agent-for-designing-advanced-algorithms/) (2025-05-14); [GA on Google Cloud](https://blog.google/innovation-and-ai/infrastructure-and-cloud/google-cloud/alphaevolve-on-cloud/) (2026-07-09) |
| An untrusted, high-performance controller is made safe by a simple verified one that can always take over: the Simplex / runtime-assurance pattern. | Sha, *Using Simplicity to Control Complexity*, IEEE Software 18(4), 2001 ([PDF](https://engineering.purdue.edu/dcsl/reading/2007/foob-using_simplicity_to_control_complexity.pdf)); [ASTM F3269-21](https://store.astm.org/f3269-21.html) |
| LLM output varies with batch size and request order; byte-identical inference needs batch-invariant kernels. | Thinking Machines, [Defeating Nondeterminism in LLM Inference](https://thinkingmachines.ai/blog/defeating-nondeterminism-in-llm-inference/) (2025-09-10); vLLM [`VLLM_BATCH_INVARIANT`](https://docs.vllm.ai/en/stable/features/batch_invariance/) (accessed 2026-10-13) |
| The depot next door: Lyft's Flexdrive opened an 80,000 sq ft AV depot in Nashville with dozens of fast chargers for hundreds of Waymo vehicles. The post names no scheduling or orchestration software. | [Lyft](https://www.lyft.com/blog/posts/flexdrive-nashville-av-depot) (2026-10-02) |

"Agents propose, the solver disposes" *is* the Simplex pattern, and it is the right one. The deterministic kernel is the
verified controller, and the agent is the high-performance one that can only win by the disposer's leave.

## The target, from the floor up

| Layer | What | Deterministic? | Status 2026-10-13 |
|---|---|---|---|
| L0 hard floor | Calendar EXCLUDE constraint, append-only events, rule-9 departure test, service-role-only signing | yes | signing exposure drafted as 0701 (not applied; see below) |
| L1 vehicle truth | What each car still owes: services, charge to target, the owner's contract | yes | departure test live (0543); per-car scouts **built today (0704)** |
| L2 scouts and estimators | Charge clock, return/drain, fault hazard; refit nightly in production (rule 10) | yes | live (0622-0628) |
| L3 kernel | The decide path; the only thing that disposes | yes | live; 0642 fairness order |
| L4 proposers | CP-SAT; a deterministic candidate-order generator (the production swarm); **one** LLM coordinator; narrow event specialists only when unstructured inputs exist | LLM: no | coordinator **made event-driven today (0705, 0711)** |
| L5 disposer check | Paired same-futures comparison, refuse by default | yes | live, but cannot discriminate yet (G389); seed depends on the minted run id |
| L6 evidence | Every pass: the board it read and its hash, prompt hash, model, tokens, every attempt, what it changed | — | **built today (0703)** |
| L7 research wing | Deterministic agent-on/off replay, event-keyed RNG, LLM fan-out over stored boards, AlphaEvolve-style heuristic search | — | design; the evidence record (0703) is its input |

## What was built and verified today

| File | What it does | Verified by |
|---|---|---|
| `0703` | Every agent pass becomes an append-only evidence row. It stores the board exactly as sent (the database hashes it itself and refuses a mismatched client hash), the prompt hash, every model attempt, tokens, and one outcome class per pass: `changed_state` / `echo` / `advisory` / `no_effect` / `solver_only` / `fallback` / `failed`. | pytest; live: 79 evidence = 79 decisions = 79 ledger rows on `176b2912` |
| `0704` | Six deterministic scouts per car, run every minute: interval due at departure, same-trigger rebound, departed below target, contract-wait breach, stranded with open must-do work, legacy task residue. Findings go to an evidence table, and the agent's board carries a digest of them. | pytest per scout (case and near-miss); live: 222 findings on `176b2912`, 0 departures below target |
| `0705` + `0711` | The wake gate. The agent is consulted on an onset or a material change (contention, two or more charger faults or repairs, emergencies, a jump in cars past their contract wait or in stranded cars, a DR call), on any critical scout finding, and on a 30-sim-minute heartbeat. Other passes run CP-SAT on the agent's standing objective with no model call. It is shadow by default, and turning it on is a person's switch. | Replayed over 79 recorded fingerprints: 0705's rules wake 66, 0711's wake 25. Live: run `57188f55` (below) |
| `0709` | The board's return wave counted open dispatches from every run (315-501 "arriving within the hour" with 8 cars on the road). It now counts this run's. | Found by 0703's first evidence row; pytest; V2 proves nothing else in the board moved |
| `0710` | The wake gate read the evidence row, written about 0.1-5.6 s after the decision row the claim reads, so a pass claimed in that gap woke as `first_consult`. It now reads the decision row. | pytest reproduces the defect, then the fix |
| edge `v29` | Writes the evidence row, asks the wake gate, and runs the solver-only branch. | node tests; live on both runs |
| `0712` | The disposer check drew its sampled futures from the run's and the pass's randomly minted ids, so the same order on the same world got different verdicts. It now draws from `world:random_seed:tick`. | pytest reproduces the defect; live: orders after 1:19 PM CT carry `world:` seeds; stored snapshots still replay as decided |
| `0713` | Passes overlapped (58 of 79) because the claim's lease, 45 s since 0338, was shorter than a pass. The claim's own default is now 130 s. (The catalog row is documentation only, because `ottoq_policy_get` never reads it, G429. Its update, 0714, waits for a person.) | pytest on the live claim; live: 0 overlaps on `57188f55` |
| `0716` + feed agents v2 | The seven per-run feed agents, OTTO-Q's one existing LLM swarm, used to rewrite the twin's world as the active version (G431). They now propose drafts, and only a person can promote one. | pytest; the edge function was redeployed and now proposes drafts |
| `0562` | At a recall, the appointment book reserved a free charger for a car still driving back, and the re-optimizer moved returning cars onto fast chargers. Both ignored `prearrival_charge_yields_to_solver`, which every armed run sets to 1. On the two gate runs, 39 chargers were held for cars not yet at the depot, standing empty 152 and 208 charger-minutes. Both functions now read the dial (G293 part 1). | Applied; validation run `02ac27b3` |
| `0707` | Nothing watched the engine's channels (G433). A watchdog now reads six channels every minute and records each change of colour: cron beats, the run's tick, agent passes, the model, CP-SAT and pg_net. | pytest with three mutations; live: its first change named a cancelled cron run |
| `0706` (pending) | The agent order that stands is the one built from the newest board, so an outranked order never comes back (the study's DC-6). | Reviewed and ready to apply; it waits for a run with the agent's order switched on to stop |

## What the gate-on run measured

Run `57188f55`: busy_day, same seed, started 1:08 PM CT. The wake gate was on and the claim lease 120 s, both scoped to the
run. It stopped at the governor's 540-minute ceiling at 2:12 PM CT. Full figures are in `db/checks/0440` §10.

| | `176b2912` (shadow, lease 45 s) | `57188f55` (gate on, lease 120 s) |
|---|---|---|
| Agent passes | 79 | 288 |
| Passes that consulted the model | 79 | 21 (heartbeat 12, scout 5, charger 2, contract wait 2, first 1) |
| Passes that ran CP-SAT alone | 0 | 267, mean 2.1 s |
| Passes that overlapped another | 58 | 0 |
| Model tokens | 1,985,250 | 576,986 (−71%) |
| CP-SAT proposals the kernel enacted | 0 of 117 | 22 |

One consult, a heartbeat, was already in flight when the run stopped and landed 41 seconds later. It is counted above.
Read before it landed, the figures were 20 of 287 and −72%.

The 22 CP-SAT enactments against 0 have a likely mechanism. Without the gate, every pass waited about a minute on the model,
so the solver ran on minute-old boards. With the gate, it runs every pass on a board two seconds old. This is still one pair
of runs under live playback, so it is a lead and not a measured effect (G432).

The agent itself took none of its orders. The check refused all 6 of its graded differing orders, and in hindsight 5 of
those 6 would have won (G427).

## When would a second agent earn its place?

Any additional agent, whether a per-vehicle LLM, a specialist or a swarm, ships to production only when all four hold:

1. **Its outputs are recorded and replayable**: the 0703 record, per seat.
2. **The disposer discriminates**: the AUC interval of the check's win probability excludes 0.5 on graded decisions.
3. **An ablation beats the noise floor**: a deterministic paired agent-on/off comparison over at least 10 distinct (scenario,
   seed) keys, counted by distinct keys and not by rows (0339).
4. **It is registered**: an identity, the contexts it may propose into, and its hit rate by proposal id.

The first place a narrow specialist would plausibly pass is **unstructured input**: an OEM fault code in free text, an owner's
request, a technician's note. None of the twin's event types is unstructured today, so there is nothing for one to read yet.

## What a person decides

- **Turning the wake gate on** (`agent_wake_enabled`) for demos and production. It cuts consults by about two-thirds, at the cost of
  about half the agent's differing orders, whose value the check cannot yet establish.
- **The NVIDIA endpoint.** The primary model failed a third of its attempts on `176b2912`. A dedicated deployment, or a
  batch-invariant self-hosted one, is a cost decision.
- **The security items** in the study's blind spots: rotating the signing secret and closing open sign-up. Those are Chase's
  calls. Migration 0701, which revokes the grants, is drafted and reviewed separately.
- **Rule 9: cars leave with maintenance or calibration due (G430).** 0715 is written and tested but not applied. On busy_day
  the intervals are compressed about a hundredfold, so applying it makes the two service bays the depot's wall. The
  decision is whether to apply it with realistic intervals or with the compression kept.
