# relay/status.md — OTTOYARD Defense Workstream (Hermes research agent)

Append-only. Every entry dated.

---

## 2026-08-25 — Bootstrap

- Hermes is live (hosted environment). Repo already cloned at `/opt/data/otto-q-core`; GitHub
  token in `/opt/data/.env`. SETUP step 1 (from MASTER_SHEET) is therefore already satisfied.
- **Discrepancy resolved:** the three context packs arrived via Telegram, NOT already in the repo.
  Hermes committed them verbatim as the baseline (sha256 below) per the standing byte-for-byte rule.
- `relay/` structure established: `requests/` (REQ-*.md from build agent), `research/`
  (RES-###-*.md outputs), `for-chase/` (human-facing items).
- Context pack sha256 (source → committed, byte-exact):
  - CONTEXT_PACK_STRATEGY.md `8cc84dc7b76c604c61f1017af5aaebc9ec18cfe62d2d3e41afc219e6ffc1a171`
  - CONTEXT_PACK_BUILD.md `ac67a996f8e0377d9b5bab971adc6c0486d5f15983d14539847b80bf7d5225a5`
  - MASTER_SHEET_HERMES.md `dd13bc67f7a2be028af3a2421962779e15219fae8ae63891430a8b285bae18ac`

---

## Re-prioritized standing queue (re-prioritized against CONTEXT_PACK_STRATEGY.md §6)

§6 = the standing questions Hermes owns beyond the R-queue. Order below folds §6 questions into
the R-queue and inserts two new §6 items (S1, S2).

**Tier 1 — the pitch-in-government-writing anchor (§6 Q1)**
- R1 — Navy vendor-neutral USV maintenance/sustainment/training Request for Solutions (reported
  Jul 2026): actual solicitation, issuing office, POC, status, response window, follow-on
  vehicles/lineage. → RES-001

**Tier 2 — non-dilutive entry doors + money (§6 Q2, Q5)**
- R2 — Army xTech: open/announced competitions, deadlines, eligibility, prize/contract structure. → RES-003
- R3 — AFWERX Open Topic SBIR: current/next windows, submission checklist, Phase I award size. → RES-003
- R4 — NAMC: membership process, small-business fee, base agreement terms, onboarding time. → RES-004
- R5 — NavalX Tech Bridges: Midsouth/Memphis vs Gulf Coast for Nashville, director/POC, intro path. → RES-004
- R10 — Adjacent money: Office of Strategic Capital, APFIT, TN + NC state defense/innovation grants. → RES-004

**Tier 3 — §6 extension (NEW, not in original R-queue)**
- S1 — Does America's Maritime Action Plan (EO 14269) spawn fundable programs (Maritime Security
  Trust Fund, prosperity zones) touching autonomy infrastructure? → RES-002
- S2 — Which EABO exercises in FY27 accept industry demos? → RES-005

**Tier 4 — build dependencies (FOR CLAUDE-CODE)**
- R7 — UMAA: latest public version, where to obtain, digest of sustainment-relevant interfaces
  (energy, health, availability, tasking). → RES-006
- R8 — Open-source OCPP charge-point simulators: compare, recommend one for CSMS-side adapter. → RES-006
- R9 — ArduPilot SITL best setup + 2–3 COTS MAVLink quadcopter kits under $1,000. → RES-006

**Tier 5 — ongoing**
- R6 — DIU open solicitations (maritime resupply, autonomous logistics, ALPV lineage). Weekly re-check. → RES-005
- R11 — standing weekly sweep: Navy SBIR, MUSV/GARC, contested-logistics CTA. Deltas only.

**Strategy verification (umbrella task):** every load-bearing claim in CONTEXT_PACK_STRATEGY.md is
being verified, dated, and extended by the same wave — not rediscovered. Results fold back into the
dossier.

---

## Loop status

- Recurring task (45-min pull → process REQ-*.md → advance queue → commit+push): **pending** a
  governance decision — MASTER_SHEET says "push wakes the build agent" (direct-to-main), but
  AGENTS.md says "never merge; branch + PR, Chase merges." Flagged to Chase; defaulting to
  branch + PR until confirmed. Research itself is not blocked by this.

## Log

- 2026-08-25 01:35 UTC — bootstrap: context packs committed (pending PR), relay/ + status.md
  written, 6-agent research wave dispatched (RES-001…RES-006).
