# Real AV data feeds, and vehicle integration as simple as a pizza tracker

**Date:** 2026-11-18 CT (searches 2026-11-19 04:00–04:10 UTC, about 10:00 PM CT on the 18th). **By:** Claude Code
(build track), by direct search under CLAUDE.md rule 3: four searches, no research agents. Every external claim
carries its URL and the date it was read. **Asked by Chase, 2026-11-18 (evening CT):**
*"How do we know or test Otto-q can work with actual autonomous vehicle data feeds?"* and *"How to make vehicle
integrations 'dominos pizza tracker' simple. Fewest steps possible AND agnostic (or just partnerships/integration
agreements)."*

## The answers in short

1. **We do not know yet, and that should be said plainly: no real car has ever sent an event to OTTO-Q.** What we
   have is the door a real feed would use (`ottoq-depot-v2`, live since 2026-10-09, `contract/README.md`), its
   contract (0.1) with a conformance kit, and a twin that is halfway to talking through that door. The swap test is
   designed, not yet run. Section 1 is the ladder that turns it into a measurement, cheapest rung first.
2. **The integration is the contract, once per operator, never per car.** A pizza tracker is simple because the
   customer does one thing (orders) and then only watches. For OTTO-Q the one thing is one connection per fleet; the
   watching is each car's stages with a ready time, which `readiness.forecast` already carries. Section 2 names the
   three on-ramps that cover the market, each one adapter into the same contract, and recommends partnerships for
   robotaxi fleets and an aggregator for the long tail.

## 1. How we will know: four rungs, each a measurement

What exists today (read 2026-11-18 in this repo):

- **The contract** (`contract/`): CloudEvents 1.0.2 envelope, JSON Schema 2020-12 payloads, COVESA VSS 6.0 signal
  names, ten event types, 10 valid and 18 invalid examples, and `ottoq_contract.py` to validate, sign and verify.
- **The door** (`ottoq-depot-v2`): every event comes back `applied`, `late`, `duplicate` or `refused` with its
  reason. A key's **data source** is one of four, and two of them exist precisely for this question:
  - `replay`: a recorded feed played on a run's sim clock; it is sent no directives.
  - `shadow`: a real operator's live feed, taken like production's (wall clock, applied to the car's state); *"it is
    sent no directives: OTTO-Q decides in shadow and commands nothing."*
- **The twin's sending side** (`docs/TWIN_SENDING_SIDE.md`): telemetry, faults and departures through the door are
  built behind flags that are off (`twin_operator_publish`, `twin_operator_departures`; 0691-0693). Coming home is not:
  contract 0.1 has no recall directive, and the twin still runs OTTO-Q's return evaluator inside its own tick.

The ladder:

| Rung | What runs | What it proves | What it costs |
|---|---|---|---|
| 1. The twin through the door | Turn on the twin's door flags at the twin depot, the receiving one (`twin_operator_door`) and the two sending ones (`twin_operator_publish`, `twin_operator_departures`), each on at depot scope and checked in one demo run (rule 12), and add `directive.recall` (contract 0.2, already drafted in `contract/proposals/`) so returns go through the door too. | The swap test made literal: the twin reaches OTTO-Q only through the door a real operator would use. Today it writes OTTO-Q's tables directly, in OTTO-Q's transaction. | Engineering only. No partner. |
| 2. Real cars, real noise, no partner | A few real EVs (company cars) on a `shadow` key, through an adapter from their maker's own data stream. Tesla's Fleet Telemetry pushes each car's data to a server, and a car buffers 5,000 messages (at least 2,500 seconds) through a dropout ([Tesla developer docs, Fleet Telemetry](https://developer.tesla.com/docs/fleet-api/fleet-telemetry), read 2026-11-19 UTC). | What the twin cannot fake: late, duplicate, bursty and stale signals from real hardware, against contract rules 2-5 (event time kept, a stale signal reads as unknown). OTTO-Q decides on real noise and commands nothing. | A small adapter. The cars are not robotaxis, so this proves the plumbing and the rules, not robotaxi behaviour. |
| 3. A recorded real feed, replayed | Rung 2's capture, played on a `replay` key on the sim clock. | Reproducibility: the same real feed, byte for byte, on every engine change; it becomes a fixture like the twin's recorded runs. | Storage and a player. |
| 4. An operator pilot in shadow | One fleet's live feed on a `shadow` key at one depot, OTTO-Q's decisions logged beside what that depot actually did. | The counterfactual on a real fleet: OTTO-Q's assignments, charge plans and ready times against the real outcomes, before it is allowed to command anything. Then a `production` key. | A partner (section 2). |

**What "works" means at each rung, in numbers the door already records:** the share of events `applied` against
`late`, `duplicate` and `refused`, by reason; the age of the freshest state-of-charge OTTO-Q decided on; directives
acked against issued; and `readiness.forecast`'s p50 and p90 against each car's actual departure. Rung 4 adds
OTTO-Q's plan against the depot's real one, car by car.

## 2. Pizza-tracker simple: one connection per fleet, three on-ramps, one contract

**The owner's steps, at most four, and none of them per car:**

1. Sign in. (`OTTOYARD-SITE` `/connect` already does this for an owner approving their own agent, otto-q-core 0700.)
2. Authorize the fleet once: one consent at the maker or aggregator, or one key for an operator.
3. The cars appear, matched by the contract's `vehicle_ref`, with their state.
4. Watch: each car's stages (arriving, charging, cleaning, ready) with a ready time. `readiness.forecast` already
   carries p50 and p90 ready times and what is still open; this is the tracker half, and it needs a screen, not data.

**Agnostic, without building a catalogue of makers ourselves.** Every on-ramp is an ADAPTER into the one contract, and
adapters translate, never decide (CLAUDE.md C10):

| On-ramp | Who | How a fleet connects | Per-car work |
|---|---|---|---|
| A. Partnership | Robotaxi operators and the companies that run their depots | Their system posts the contract's events to the door (or we write one adapter to their API). Waymo does not run its own depots: Moove runs fleet operations, facilities and charging in Phoenix and Miami ([TechCrunch, 2024-12-05](https://techcrunch.com/2024/12/05/waymo-outsources-fleet-operations-to-african-fintech-moove-in-phoenix-and-miami)), and Avis runs depot operations, charging and maintenance in Dallas ([The Register, 2025-07-29](https://www.theregister.com/2025/07/29/waymo_to_expand_dallas/)); both read 2026-11-19 UTC. | None after the first. |
| B. Aggregator | Owned and leased EV fleets, the long tail | One OAuth consent through the owner's own maker account, no hardware. Smartcar is one such API; its own pages put its coverage at 36 to 40 brands, and they disagree with each other ([smartcar.com](https://smartcar.com/), read 2026-11-19 UTC). A maker's own API (Tesla's, above) is the same shape. | None. |
| C. The charger itself | Any car that supports ISO 15118 Plug & Charge | The car proves who it is to the charger with a contract certificate, and a session starts with no app and no card; the app is needed once, to set it up. OCPP 2.0.1 carries the certificate traffic natively ([AMPECO glossary, contract certificate](https://www.ampeco.com/ev-charging-glossary/contract-certificate-plug-and-charge/), a vendor source, read 2026-11-19 UTC). | None, where the car supports it. |

**Recommendation.** Make A the product: the contract is the integration, and the partner for a robotaxi fleet is as
often its depot operator (Moove, Avis) as the AV company, which is the same buyer OTTO-Q sells to. Offer B as the
on-ramp for small fleets, through one aggregator, not one integration per maker. Treat C as identity at the charger,
not as a data feed: it tells a session which car it is, nothing about the car's day. The charge arm serves the twin's
fleet, so C changes no robot.

## What was not verified

- Every number about a vendor (Smartcar's brand count, Tesla's limits) is the vendor's own, as of the date read.
  Tesla's pages disagree about how many third-party streaming configurations a car allows (three or five); this note
  does not depend on either.
- The depot operators named for Waymo are from the two articles cited, as of their dates. Newer arrangements (Austin,
  Atlanta, London) appeared only in newsletters and are left out.
- Nothing here was tested against a real feed. That is the point of rungs 2 to 4.
