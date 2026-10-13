# The agent-architecture decision, checked against what 2026 published

**Date:** 2026-10-13 CT (searches 20:34–20:37 UTC, 3:34–3:37 PM CT). **By:** Claude Code (build track), by direct
search under CLAUDE.md rule 3. No research agents were used. Every external claim carries its URL and the date it
applies to; where only an abstract or a secondary summary was read, the line says so.
**Asked by Chase, 2026-10-13:** *"The agent artifact you produced earlier used a lot of references that were over a
year old (mid-2025). There has been so much explosive technology growth and research around agentic architecture and
functionality since then. You couldn't find any more recent info than that?"*

He was right. Of the seven outside sources on the study page, five were from mid-to-late 2025, one was a 2021
standard, and only the Lyft depot was from this month. This file is the 2026 evidence, read against
`docs/AGENT_ARCHITECTURE.md`.

## The answer in short

1. **The decision holds, and 2026 makes the case sharper, not weaker.** Three controlled 2026 studies find that
   multi-agent LLM systems mostly do not beat a single agent once compute is held equal, and that where they help, it
   is because messages between agents carry nearly everything the task needs (§1).
2. **The closest 2026 result to OTTO-Q's own problem says when the LLM earns its place, and it is the wake gate's
   rule.** On deadline-aware scheduling at the autonomous-vehicle edge, a fixed heuristic reached 0.87 of a CP-SAT bound
   and the LLM control plane added nothing under steady load. It won only in a mid-run surge (§2). OTTO-Q's wake gate
   (0705, 0711) consults the agent on exactly those onsets and runs the solver otherwise.
3. **Record-and-replay is now the standard way to make agents testable,** with 2026 tools that replay a recorded run
   bit for bit or replay only some of its calls. OTTO-Q's evidence row (0703) records the model call already. The
   solver's answer is the boundary it does not yet record (§3).
4. **Fleet-level risk is a 2026 blind spot for agent systems, and in OTTO-Q it maps to the actor registry.** Gates that
   judge one action at a time let a fleet of individually authorized agents overdraw a shared risk limit by up to 48
   times. Per-principal accounting needs to know every principal, which is 0702 (PR #241) (§4).
5. **Swarms in 2026 are real for breadth-first search, not for shared-resource planning** (§5). Code evolution for
   heuristics is promising, and a 2026 paper shows simple sampling baselines match it when the evaluation is held
   fair (§6). Both belong in the research wing, as the decision already says.

## 1. When do multi-agent LLM systems help? (2026 controlled studies)

| Claim | Date | Source | Read |
|---|---|---|---|
| With reasoning tokens held equal, single agents match or beat multi-agent systems on multi-hop reasoning across three model families (Qwen3, DeepSeek-R1-Distill-Llama, Gemini 2.5). The authors argue reported multi-agent gains are often extra test-time compute. They predict multi-agent becomes competitive when a single agent's use of its context degrades. | 2026-04-02 (v2 2026-04-11) | Tran & Kiela, [arXiv 2604.02460](https://arxiv.org/abs/2604.02460) | listing and secondary summaries ([beancount.io](https://beancount.io/bean-labs/research-logs/2026/05/31/single-agent-outperforms-multi-agent-equal-token-budget)); figures not checked against the PDF |
| Ten benchmarks, GPT-4.1, 3,302 instances per configuration per run over three runs. Only one of six multi-agent workflows (EvoAgent, 79.70%) beat the single-agent baseline (76.65%) on pooled accuracy. The other five trailed by 1.71–8.76 points. Wins on one benchmark did not carry over: LLM-Debate +9.67 on HumanEval, −1.96 pooled, at 1.39× the tokens; ChatEval +22.25 on IFEval, still behind pooled, at 4.34× the tokens. | 2026-06-04, revised 2026-10-09 | Fu et al., [arXiv 2606.05670](https://arxiv.org/abs/2606.05670) | abstract |
| Theory and 18 controlled experiments (five benchmarks, three model scales): a multi-agent system can only beat a single agent because its messages are bounded. It helps when relays are near-sufficient, mostly for weaker models. Gains shrink or reverse when relays lose information, especially for stronger models. | 2026-07-17 | Yu et al., [arXiv 2607.16133](https://arxiv.org/abs/2607.16133) | abstract |
| A controlled study of an upstream agent's wrong message overriding a downstream agent's correct answer. | 2026-09 | [arXiv 2609.36855](https://arxiv.org/abs/2609.36855) | title and search snippet only |

**For OTTO-Q:** the board is the single shared context the decision keeps (one coordinator reads all of it). Splitting
it across per-vehicle LLM agents would make every car's agent work from a relay of the depot, the situation 2607.16133
says costs a strong model most. The study's own measurement agrees: one charge order lost to the kernel on a shared
charger pool (G318), and the check cannot yet tell a better agent order from a worse one (0708: AUC 0.534).

## 2. The closest problem to ours: an LLM beside CP-SAT on vehicle-edge scheduling

| Claim | Date | Source | Read |
|---|---|---|---|
| A windowed auction ordering time-critical tasks earliest-deadline-first reaches 0.902 time-critical completion, beats 15 baselines (best 0.838; Holm-corrected p < 0.001) over 60 instances on three topologies, and reaches about 0.87 of a CP-SAT upper bound. Under stationary load the per-window LLM policy and online adaptation add nothing. In a mid-run safety-critical surge the LLM control plane significantly outperforms the static heuristic and a bandit. *"LLM orchestration therefore earns its cost only when non-stationarity opens headroom a fixed policy cannot use."* | 2026-08-20 | Zakerian, [arXiv 2608.19557](https://arxiv.org/abs/2608.19557) | abstract; the surge numbers are not in it |
| The open-source pattern for LLM plus CP-SAT: the model turns a request into a structured plan, CP-SAT solves it, and a separate deterministic checker audits the result. The model never commits a schedule. | 2026 | [jz-118/scheduling-agent](https://github.com/jz-118/scheduling-agent), [roopchandrika/jobshop-agent](https://github.com/roopchandrika/jobshop-agent) | READMEs; examples, not validated benchmarks |
| "LLM-as-Scheduler: Agentic Workflow Dynamic Scheduling," ACL 2026 long paper. | 2026 | [ACL Anthology 2026.acl-long.581](https://aclanthology.org/2026.acl-long.581/) | citation only |

**For OTTO-Q:** this is the wake gate's design, measured independently on a neighbouring problem. The kernel and CP-SAT
are the fixed policy; the agent is consulted on onsets (contention, charger faults, emergencies, contract-wait jumps,
critical scout findings) plus a heartbeat (0705, 0711). The jobshop and scheduling-agent repos follow the same split as
OTTO-Q's "agents propose, the kernel disposes," which is the 2026 consensus rather than an outlier.

## 3. Record and replay for agents

| Claim | Date | Source | Read |
|---|---|---|---|
| Chronicle records a run at its non-deterministic boundaries as immutable envelopes. Cut-point replay serves some boundaries from the recording and runs the rest live with new code, turning a recorded incident into a CI regression test. Recording costs about 23 µs per boundary; full replay is bit-stable across 20 repetitions. In a mutation study, cut-point tests caught every mutant that let the recorded unsafe action through, against none for a stub-everything baseline. | 2026-09-17 | Chawla & Koul, [arXiv 2609.20625](https://arxiv.org/abs/2609.20625) | abstract; 6 recorded failures, simulated model boundaries |
| agrepl captures external calls at the transport layer and replays them with no outbound network. Replay fidelity 1.0 over five workloads (250 replays), median per-step latency −98.3%. | 2026 (listed as submitted 2026-04-30) | Mudasiru, [arXiv 2607.16200](https://arxiv.org/abs/2607.16200) | abstract |
| An audit-replay harness for tool-using financial agents measures trajectory and decision determinism on three 50-case benchmarks. Schema-first architectures reached determinism consistent with audit replay. | 2026-01 | [arXiv 2601.15322](https://www.alphaxiv.org/abs/2601.15322) | search summary only |

**For OTTO-Q:** an agent pass has three non-deterministic boundaries: the model call, the CP-SAT service, and the
check's sampled futures. 0703 records the first (board, prompt hash, answer) and 0712 made the third a function of the
world seed. The CP-SAT answer is the one boundary not stored as evidence. Recording it would make a pass replayable
end to end, which is the input the study's item 19 (the deterministic agent-on harness) needs. Chronicle's cut-point
idea fits the existing pytest-on-live-definition pattern directly.

## 4. Fleet-level risk: per-action gates are not enough

| Claim | Date | Source | Read |
|---|---|---|---|
| Per-effect gates check one action at a time, so a fleet of individually authorized agents can collectively overdraw a principal's risk under a shared trigger, even when every gate is correct. In a controlled study, per-effect gates allowed overdraws of up to 48× the tenant's limit. An "irreversibility budget" kept per principal across agents and workflows kept every correctly charged run within it. Pricing each effect conservatively, with its dependencies, is the open problem. | 2026-08-31 (2nd AgenticOS Workshop @ SOSP) | Mohammadi & Bindschaedler, [arXiv 2609.00275](https://arxiv.org/abs/2609.00275) | abstract |
| Helpful agents evade oversight in multi-agent systems; orchestrators suppress protective behaviour. | 2026-09, 2026-05 | [arXiv 2609.39050](https://arxiv.org/abs/2609.39050), [arXiv 2605.13851](https://arxiv.org/pdf/2605.13851) | titles and search snippets only |

**For OTTO-Q:** the L1 shield, the disposer check and the dial clamps all judge one effect at a time. In production,
`production_never_self_tunes` (0629) refuses every settings write under an agent's name, which bounds the aggregate
for registered agents. But the registry knows one name, `ottoq_prime`. The OttoCommand chat seat, the self-tuning loop
and the feed agents write as if they were people (0702's check 0439, on PR #241), so no per-principal account could include them.
0702 (PR #241, Chase's call on the chat seat) is the prerequisite for any budget of this kind. Nothing new is built
here on this evidence.

## 5. Swarms in 2026

| Claim | Date | Source | Read |
|---|---|---|---|
| Kimi K2.5 Agent Swarm: up to 100 sub-agents and 1,500 coordinated tool calls. Only the orchestrator is trained by RL (sub-agents are frozen checkpoints), with staged rewards against "serial collapse." Moonshot reports 3–4.5× shorter execution on highly parallel workflows; released as a research preview. | 2026-01 | [HPCwire, 2026-01-30](https://www.hpcwire.com/aiwire/2026/01/30/moonshot-ais-kimi-k2-5-expands-what-open-weight-models-can-do/), [Phil Schmid](https://www.philschmid.de/kimi-composer-context) | secondary coverage; vendor figures; primary report not opened |
| SwarmBench scores LLMs as swarm orchestrators (decompose, delegate, aggregate) over 8 tasks and 400 samples and finds large differences between models. | 2026-08 | [arXiv 2608.30661](https://arxiv.org/html/2608.30661v1) | search snippet |

**For OTTO-Q:** the 2026 swarm results are on breadth-first tasks (search, browsing, parallel coding), where subtasks
barely interact. A depot's subtasks interact through the same chargers, bays and power cap every tick, the condition
under which the controlled studies in §1 find multi-agent workflows lose. The study's place for LLM fan-out stands: the
research wing, offline, over recorded boards.

## 6. Evolving heuristics with LLMs

| Claim | Date | Source | Read |
|---|---|---|---|
| CHECKMATE evolves algorithms against a formal specification of a correct solution; tested on industrial configuration and scheduling, the evolved algorithms "consistently outperform state-of-the-art solvers." | 2026-05-29 | Semmelrock et al., [arXiv 2605.31049](https://arxiv.org/abs/2605.31049) | abstract; no numbers in it |
| Simple baselines (independent random sampling; sequential conditioned sampling) match or beat code-evolution methods in all three domains tested. Methods are often compared with different models, prompts or budgets, and the search space an expert designs matters more than the search. | 2026-02-18 | Gideoni, Risi & Gal, [arXiv 2602.16805](https://arxiv.org/abs/2602.16805) | abstract and secondary review |
| Magellan applies AlphaEvolve to compiler heuristics in LLVM and XLA. | 2026-01 | [arXiv 2601.21096](https://arxiv.org/pdf/2601.21096) | title only |
| Amazon's DeepFleet: no 2026 update was found; its launch (2025-07-02) is still the latest primary source. | — | [Amazon Science](https://www.amazon.science/blog/amazon-builds-first-foundation-model-for-multirobot-coordination) | searched; nothing newer |

**For OTTO-Q:** the research wing's evolutionary search (study L7) should be judged against independent sampling with the
same evaluator and the same budget, and its asset is the evaluator: the deterministic pair rig and the fourteen atoms,
which give an exact, cheap verdict on a candidate heuristic. A CHECKMATE-style formal specification already exists in
the kernel's hard floor (calendar exclusion, the rule-9 departure test).

## 7. The depot market in 2026 (secondary sources; verify before quoting)

Waymo hands depot operations to partners: Uber in Austin and Atlanta (cleaning, repairs, depot operations), Moove in
Phoenix and Miami (fleet operations and charging), Element Fleet Management for San Diego ([Smart Cities
Dive](https://www.smartcitiesdive.com/news/robotaxi-waymo-motional-zoox-tesla-uber-lyft/759895/), [SF
Standard, 2026-01-07](https://sfstandard.com/2026/01/07/waymo-has-robotaxi-lead-tesla-zoox-uber-coming-streets/)).
Lyft's Flexdrive opened an AV depot in Nashville on 2026-10-02 (cited on the study page). The depot operator is a
separate party from the AV maker, and an orchestration layer sold to that operator is the slot OTTO-Q is built for.
These figures come from news and trackers, not company filings.

## What this changes

- **`docs/AGENT_ARCHITECTURE.md` and the study page** cite §1, §2 and §4 in place of the 2025 sources where the 2026
  result is stronger, and keep the 2025 ones only where nothing newer was found (Anthropic's research system,
  AlphaEvolve's Borg result, DeepFleet).
- **No migration follows from this file.** The two engineering consequences are already on the list: record the
  CP-SAT answer as evidence (study item 19's input, §3), and 0702 before any per-principal budget (§4).
