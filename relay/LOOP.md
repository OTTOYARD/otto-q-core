# relay/LOOP.md — the relay loop's anti-bloat contract

The relay loop is a 45-minute cron job that keeps Hermes (research) and Claude Code (build)
synchronized through files. This file is the contract that keeps it bounded. Every rule here exists
to prevent ONE failure: **the loop inventing work forever after the real work is finished.**

## The rule that matters most

**An empty queue is a terminal, silent state — not a trigger for more work.**

The loop never searches for new things to do. When there is no open work, it produces nothing:
no file, no commit, no push, no message, no tokens. It idles for free.

## Finite queue (no self-generated backlog)

Work enters the queue exactly three ways:
1. a `REQ-*.md` dropped into `relay/requests/` by the build agent,
2. a direct instruction from Chase,
3. the standing queue in `relay/QUEUE.md` — which is finite and drains to empty.

The loop NEVER adds its own items to the queue. If it sees an opportunity for new research, it
writes a PROPOSAL to `relay/for-chase/` and leaves the queue alone. Only Chase promotes a proposal
to a task.

## Silence on no-op (no idle churn)

A cycle with no open work writes nothing and pushes nothing. The monitor script's empty output
suppresses the agent run entirely — no LLM, no cost.

## One item per cycle

The loop processes at most ONE item per cycle, finish-and-file before the next. (The 6-way parallel
research is a one-time bootstrap wave, not the loop's steady-state behavior.)

## Idempotency (no re-research, no duplicate files)

Each REQ maps to exactly one RES file; a REQ is "open" only until its RES exists. Once answered, it
is never re-processed. The monitor's fingerprint is a sorted set, so duplicate work cannot be
triggered by ordering.

## Direct-to-main (scoped)

The loop commits and pushes DIRECT to `origin main` — but only files under `relay/**`. Everything
else in the repo stays on the branch+PR discipline (AGENTS.md). Push is the handoff: it is what
wakes the build agent.

## Cost ceiling

Idle = zero LLM cost (monitor guard). Active = bounded by the finite queue, one item per cycle.
No cycle may spawn more than one research item.

## Kill switch

The entire loop is ONE cron job (`relay-loop`, every 45 min). Chase stops it with one message
("pause the relay loop") and it is paused/removed. There is no other long-running component.

## The auto-pilot clarification (read this literally)

"Keep executing" means: work the agreed queue to completion without pestering Chase for the next
step. It does NOT mean: find new work when the queue is empty. **Empty = stop = silence.**
