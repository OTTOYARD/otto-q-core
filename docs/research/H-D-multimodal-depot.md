Package H-D · 2026-08-22 · Status: final · Sources verified as of 2026-08-22

## FINDINGS

This is the package that tests whether our differentiator — one node serving **different kinds** of unmanned asset at once — is genuinely unoccupied. The honest answer: **yes, it is unoccupied, and the absence is the finding.**

Nobody, military or commercial, has published on a depot that *schedules and services air and ground unmanned systems through one arbitration layer*. What exists in abundance is (a) single-domain orchestration (drone docks, ground resupply robotics, container terminals) and (b) **doctrine about dispersing sustainment nodes**, not about arbitrating a mixed fleet at one node. The DoD's multi-domain work (USAF Agile Combat Employment, USMC Expeditionary Advanced Base Operations) is about *where the nodes go and how they displace*, not *which asset goes to which node and when*. That precise layer — the OTTO-Q layer — is unclaimed in the published record we can reach.

The cross-domain handoff work that *does* exist is real but young: ground-vehicle-as-drone-carrier ("mothership") concepts have been demonstrated (US Army), but they are launch platforms, not servicing arbiters. The timing data we would need to schedule a mothership's launch-and-recover cycle is not published in primary form.

On **mixed-fleet throughput**, the mechanism is well-understood in the commercial literature even though the unmanned-military case is absent. Container-terminal **berth allocation** and airport **gate assignment** are the exact analogues: throughput degrades under mix because heterogeneous jobs have different duration distributions and different resource footprints, which turns a clean first-come-first-served queue into a combinatorial assignment problem. The canonical result is that **mixing asset classes makes the berth/gate assignment NP-hard in the general case** and forces explicit scheduling rather than FIFO. That is a published, citable mechanism we can stand on — the unmanned version is ours to write.

## FOR CLAUDE CODE

### 1. Exists vs concept — the honest map

| Area | Status | What is real | Source (label) |
|---|---|---|---|
| Air+ground mixed-fleet depot servicing | **NOBODY HAS DONE THIS (published)** | no primary source found | absence (d) |
| Single-domain drone dock orchestration | REAL | DJI Dock, Percepto, Airobotics, Hextronics, Dronehub — all vendor-captive, single asset class | vendor docs (c) |
| Ground resupply robotics | REAL | Army S-MET program | .mil (a) |
| Multi-domain *basing* doctrine | REAL — but about node placement, not asset arbitration | USAF ACE (AFDN 1-21), USMC EABO (Tentative Manual, 2nd Ed, May 2023) | doctrine (a) |
| Cross-domain handoff (mothership) | CONCEPT → early demo | US Army mothership concept demonstrated; drone motherships emerging | trade press (c) |
| Common servicing interfaces | PARTIAL — flight-control commonality exists, charging/data commonality does not | STANAG 4586 (flight control), MOSA (modular open systems), Army UAS interoperability program | standards/DoD (a/b) |

### 2. Cross-domain handoff — what is real vs concept, timings

- **Ground vehicle as drone carrier/launcher:** demonstrated (US Army "mothership" concept). **Timings NOT FOUND in primary form** — launch/recover cycle times for a mothership are not published. Treat as concept-stage; do not put a number in the kernel without a primary source. (c)/(d)
- **Autonomous resupply of forward drone teams:** real trend, no published servicing-arbitration timings. (c)
- **MQ-25 Stingray (unmanned aerial refueling):** real, fielded-adjacent, but it is *aerial refueling*, not depot servicing — a useful boundary case for "one system services another in the air," not a ground-depot analogue. (a/c)

### 3. Distributed basing — the doctrine, and what it does NOT answer

- **USAF ACE (AFDN 1-21, 23 Aug 2022):** doctrine for dispersing and displacing operations. It specifies *how sustainment scales to match dispersed ops* but does **not** publish a decision rule for "which node supports which asset." That arbitration is left to planners. (a)
- **USMC EABO (Tentative Manual, 2nd Edition, May 2023):** low-signature, mobile, expeditionary nodes. Chapter 6 logistics is explicit that the distributed logistics problem is *unresolved in doctrine* — it describes the challenge (contracting, disbursing, base camp planning under dispersion) without prescribing the node-assignment algorithm. (a)
- **Node displacement speed:** doctrine is qualitative ("mobile, low-signature, short-notice"); no quantitative displacement-time standard found. (d) inference.
- **The gap:** both doctrine families describe *what the sustainment system must do* and *where nodes live*, but neither publishes the *which-asset-to-which-node-when* scheduler. That is precisely OTTO-Q's layer. Cite this as the differentiator's doctrinal white space.

### 4. Commonality — the vendor-neutral push (our thesis, and who else is pushing)

- **STANAG 4586:** NATO interoperability for UAS *flight control* (command/control/data links). It does **not** cover charging connectors or ground servicing. (b)
- **MOSA (Modular Open Systems Approach):** DoD-wide push for modular open interfaces — the closest doctrinal statement of our vendor-neutral infrastructure thesis, but aimed at *systems architecture*, not service-point arbitration. (a)
- **Army UAS interoperability program:** real push toward common UAS control; servicing/charging commonality is **not** part of it. (a)
- **Charging connectors:** commercial drone connectors are fragmented (XT90S, AS150, Molex, ACES, proprietary per vendor) — **no common military charging-interface standard found** for the small-UAS class. (c)/(d) — this is an authorship surface, not a solved standard.

### 5. Throughput under mix — the published mechanism (the citable core)

- **Berth allocation problem (container terminals):** heterogeneous ships with different lengths, service times, and berth constraints. Key references: Buhrkal et al., "Models for the discrete berth allocation problem" (2011, ~270 citations); Umang, Bierlaire & Vacca, "Exact and heuristic methods to solve the berth allocation problem in bulk ports" (TRANSP-OR 120617, 2012). **Mechanism:** mixing vessel classes turns a FIFO berth into a combinatorial assignment; the discrete berth allocation problem is NP-hard. (b — academic)
- **Airport gate assignment problem:** heterogeneous aircraft, gate constraints, buffer times. Survey reference available (PMC4258332). **Mechanism:** heterogeneity forces explicit assignment with buffer times rather than greedy occupancy. (b)
- **Translation to OTTO-Q:** a site serving air + ground + heavy equipment is a *multi-class berth/gate allocation* problem. The degradation under mix is not anecdotal — it is the documented transition from tractable FIFO to NP-hard assignment. Our CP-SAT solver is the right machinery, and these papers are the formulation priors for the mixed-fleet constraint set.

## OPEN QUESTIONS

1. **Mothership launch/recover cycle times** — demonstrated but no primary timing published. Needs a program office datasheet or field report before it can enter the kernel. (NOT FOUND)
2. **Node displacement speed (ACE/EABO)** — doctrine is qualitative. Whether "how quickly nodes move" is even a schedulable variable in our model is an open design question, not just a research gap.
3. **Common charging-interface for military small UAS** — appears not to exist. Before claiming it as authorship space, verify against the newest NDAA/DoD charging-standardization language (may have changed recently — flagged for re-verification).
4. **Whether "nobody has done this" is stable** — the absence finding is as of 2026-08-22. Run B (IP Watch) should re-check the "mixed unmanned fleet depot arbitration" space monthly; this is the highest-value surface to watch.
