-- 0272  0379 VALIDATED: THE FOURTH TIER FIRES, THE WIDENED KEY DEDUPES, DETERMINISM
--       HOLDS A THIRD TIME, AND THE PATH TEST LEFT NOTHING BEHIND.
--
-- Read-only. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8).
-- Validation for `0379`, and the method correction `0377` earned.
--
-- ══ 1. DETERMINISM, THIRD CONSECUTIVE PAIR ══════════════════════════════════
--
-- `0379` adds a second accessor read (`ottoq_active_charge_cap_kw`) and a conditional
-- second write to a detector that runs on every tick of every arm. Fired at
-- **2026-09-20 13:25:08 UTC**:
--
--   arm A  230733c3-eadf-48b8-ad10-f68fb5415d21  12 ticks  **passed**
--   arm B  f5814600-8575-42e9-92ce-95f877a9a82b  12 ticks  **passed**
--   ottoq_twin_determinism_verdict: 12 compared, **12 identical**, 0 divergent,
--     **deterministic true**, first_divergence NULL
--
-- Three pairs now, across `0374`, `0376` and `0379`: **12/12 each time.** And the
-- beacon stands at **4 `armed` rows across 4 runs**, `source_kind='live'` -- so the
-- detector demonstrably executed on this pair too, with the new read in place.

SELECT r.sim_run_id, r.validation_status, r.tick_count, r.started_at
  FROM public.ottoq_sim_runs r
 WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
 ORDER BY r.started_at DESC LIMIT 4;

SELECT l.severity_tier, l.source_kind, count(*) AS rows,
       count(DISTINCT l.sim_run_id) AS runs
  FROM public.ottoq_site_power_excursion_ledger l
 GROUP BY 1,2 ORDER BY 1,2;

-- ══ 2. THE KEY HAD TO WIDEN, AND THAT WAS A BUG CAUGHT BEFORE IT SHIPPED ════
--
-- `0376` keyed the ledger `UNIQUE (snapshot_id) WHERE severity_tier <> 'armed'`, on the
-- stated invariant *"one row per metered instant"*. Correct **while the tiers were
-- mutually exclusive**: `excursion` and `high_water` come from one `if/elsif` and
-- cannot both fire.
--
-- **`ev_over_published_cap` is INDEPENDENT of both.** A tick can be over the site cap
-- *and* over the published EV cap, and under the old key the second row would have hit
-- `ON CONFLICT (snapshot_id) DO NOTHING` and **been silently dropped** -- the exact
-- suppression `0376` was written to prevent, one tier later. `0379` widens it to
-- `(snapshot_id, severity_tier)`: one row per instant **per finding**, which is the
-- invariant that was actually wanted all along.
--
-- Its P2 asserts the old shape before changing it, so the change is justified by the
-- schema rather than by the file's description of it.

SELECT i.indisunique, i.indpred IS NOT NULL AS is_partial,
       pg_get_indexdef(i.indexrelid) AS def
  FROM pg_index i
 WHERE i.indrelid = 'public.ottoq_site_power_excursion_ledger'::regclass
 ORDER BY 2 DESC, 3;

-- ══ 3. THE TIER FIRES, AND THE `ON CONFLICT` INFERENCE RESOLVES ═════════════
--
-- The composite `ON CONFLICT (snapshot_id, severity_tier) WHERE severity_tier <>
-- 'armed'` is an index inference resolved **at execution**, not at function creation --
-- so `0379` applying cleanly proved nothing about it, and a wrong inference would have
-- raised inside the detector, been swallowed as a WARNING by `decide_and_dispatch`, and
-- silently lost the finding. Exercised deliberately:
--
--   insert a `charge_cap_kw` of **1.0 kW**, `status='executed'`, at the run's clock
--   first call   tier **ev_over_published_cap** written · published_cap_kw **1.0**
--                · ev_over_cap_kw **441.1**
--   second call  **no duplicate** -- ledger still holds n=1 for that tier
--
-- So the branch fires, the new columns populate, and the widened key dedupes. The other
-- tiers were untouched alongside it (4 `armed`, 1 `excursion`, 15 `high_water`), which
-- is the direct evidence that widening the key suppressed nothing.
--
-- ══ 4. AND THIS TIME THE PATH TEST ROLLED BACK ══════════════════════════════
--
-- **`0377` exists only because the equivalent test on `0376` wrote a 498.2 kW row
-- tiered `high_water` into an append-only evidence table**, and `high_water` means
-- "crossed 60% of the declared cap" -- 1,500 kW here -- so that row made the tail floor
-- read 498 kW with nothing but `warn_kw = 2.5` to betray it. I recorded then that the
-- test was right and the method was sloppy, and that it should have run in a
-- transaction that rolled back.
--
-- **It did this time.** The whole probe -- the synthetic 1.0 kW command and both
-- detector calls -- ran inside `BEGIN … ROLLBACK`, and afterwards:
--
--   ev_over_published_cap rows in the ledger        **0**
--   rows with source='path_test' in energy commands  **0**
--   ledger back to 4 armed + 1 excursion + 15 high_water  (**20**, unchanged)
--
-- So the Management API honours an explicit `BEGIN … ROLLBACK` in one call, which means
-- **there was never a reason to write to evidence to test a write path.** That is the
-- standing method from here: a path test that mutates anything goes inside a
-- transaction that rolls back, and the proof it rolled back is part of the test.
--
-- The scratch probe is kept at `scratchpad/_0379_pathtest.sql` rather than committed --
-- it inserts a deliberately false energy command, and a file that does that should not
-- sit in `db/` where someone might run it against a live run by mistake.

SELECT (SELECT count(*) FROM public.ottoq_site_power_excursion_ledger
         WHERE severity_tier = 'ev_over_published_cap')            AS ev_over_rows_remaining,
       (SELECT count(*) FROM public.ottoq_energy_commands
         WHERE source = 'path_test')                              AS path_test_commands_remaining,
       (SELECT count(*) FROM public.ottoq_site_power_excursion_ledger) AS ledger_rows_total;

-- ══ 5. WHAT IS MEASURED AND WHAT IS STILL NOT ═══════════════════════════════
--
-- `ev_over_published_cap` reads **0 in live capture** and will until a run draws more EV
-- load than its published cap. The reconstruction in `db/checks/0271` §2 says that
-- happened **26 times in 1,260 ticks on run `5b37ee46`, worst 205.0 kW** -- so it should
-- appear on the next busy_day run, and if it does not, that reconstruction is what to
-- doubt first.
--
-- **Not backfilled, and this is the same refusal as `0376`'s beacon.** The historical
-- answer cannot be reconstructed: `ottoq_active_charge_cap_kw` filters
-- `status='executed'`, `twin.ottoq_sim_energy_controller` rewrites each prior cap to
-- `superseded`, and on `5b37ee46` **1,259 of 1,260** commands read superseded with the
-- single executed row being the run's final command. Writing backfilled rows here would
-- mean picking a pairing rule and presenting its output as the cap the engine saw --
-- which is precisely the overstatement `0271` §6 retracts. `0271` §2's number stays
-- labelled a reconstruction; this tier will produce the measured one.
--
-- So the honest coverage statement for the whole site-power instrument tonight:
--
--   * **deterministic inside the certified path** -- 12/12, three pairs;
--   * **executes on the live tick path** -- observed, 4 `armed` rows, not inferred;
--   * **metered excursion branch** -- proven on stored data and by direct call;
--   * **`ev_over_published_cap` branch** -- proven by a rolled-back path test, awaiting
--     its first live capture;
--   * **enforcement** -- none, by design and by decision. The cap stays advisory, the
--     `LEAST(v_service_max, …)` clamp stays unapplied, and both are Chase's.

SELECT * FROM public.ottoq_site_power_ledger;
