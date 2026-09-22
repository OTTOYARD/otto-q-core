-- 0329  **All nine pairs certified 2026-09-22 recorded `equal=true` with `disagreeing_atoms = {}`. Recompute
--       atom 4, `events`, from the stored rows today and **all nine disagree.** The verdicts were right when
--       they were taken. The evidence they were taken on is mutated afterwards — by the NEXT arm's fleet
--       reset, attributed to the previous arm by a cached transaction-local setting.**
--
--       So the fourteen-atom verdict is a **live** assertion and is **not reproducible from the archive**,
--       which is the one property CLAUDE.md 2.9a sells outward: *"same inputs, byte-identical outputs,
--       verified continuously, across fourteen independent atoms."* An auditor recomputing from the stored
--       rows finds every pair failing.
--
--       Found while checking whether the recert sweep had exercised the fault path (`0328` §5). **No
--       migration: the fix is small and known (§4) but the sweep just went green and fixing this
--       re-invalidates it, which is Chase's call to time.**
--
--       Measured 2026-09-22 ~12:40 UTC (07:40 CT) over the nine pairs certified 09:34–10:10 UTC.
--
-- ══ §1 THE HEADLINE, MEASURED ═════════════════════════════════════════════════
--
--     pairs certified 2026-09-22 09:34-10:10                    9
--     verdicts recording `disagreeing_atoms = {}`               9
--     whose `events` atom still agrees when recomputed today    **0**
--     whose `events` atom DISAGREES when recomputed today       **9**
--
-- Atom 4 is compared in `ottoq_determinism_pair` as
-- `NOT ((v_arms[1]->>'h_evt') = (v_arms[2]->>'h_evt'))`, and `h_evt` is
--
--     md5(string_agg(event_type||'|'||<entity, blanked for 3 kinds>||'|'||sim_clock_at ORDER BY the same))
--       FROM ottoq_events WHERE sim_run_id = <arm>
--
-- **with no filter of any kind** — every row of the arm's event table. So a difference in row count cannot
-- hide from it, and today there is one in every pair.
--
-- ══ §2 WHAT THE DIFFERENCE IS, TO THE ROW ═════════════════════════════════════
--
-- In **every** pair, arm A has exactly one extra `vehicle.state_changed` event **per vehicle at that
-- depot**, all at arm A's **final** `sim_clock_at`, and every one of them carries a diff with **no
-- `current_state` key**:
--
--     pair  scenario     seed     ticks   soc-only @final: A / B   all state_changed: A / B   delta
--     ----  ----------   ------   -----   ----------------------   ------------------------   -----
--     1     grid_smoke   239001       6            14 /   10             73 /    69              4
--     2     grid_smoke   424242       6            12 /    8             66 /    62              4
--     3     busy_day     171717      12           186 /   70          2,353 / 2,237            116
--     4     busy_day     314159      12           182 /   66          2,336 / 2,220            116
--     5     busy_day     424242      12           189 /   73          2,277 / 2,161            116
--     6     normal_day   171717      12           185 /   69          2,399 / 2,283            116
--     7     busy_day     171717      24           175 /   60          3,195 / 3,080            115
--     8     busy_day     424242      24           168 /   53          3,197 / 3,082            115
--     9     busy_day     171717      48           223 /  107          5,584 / 5,468            116
--
-- **The delta equals the depot's vehicle count** — 116 at the twin depot, 4 at the `grid_smoke` fixture
-- depot `aacd0bb0` — and it is identical in the `all state_changed` column and the `soc-only at final
-- clock` column. One write per vehicle, once, into arm A.
--
-- **The transition population is untouched and identical.** Events carrying a `current_state` diff number
-- **1,734 in both arms** of pair 9, and every diff-key combination containing `current_state` matches
-- exactly (452/452, 16/16, …). So nothing about the simulated state machine diverged; only SoC-shaped rows
-- were added.
--
-- ══ §3 THE CAUSE, FROM SOURCE RATHER THAN INFERENCE ═══════════════════════════
--
-- Three facts compose:
--
--   1. **`ottoq_determinism_pair` runs BOTH arms in one transaction**, and per arm does
--      `PERFORM public.ottoq_tick_invariance_reset_fleet(p_depot, p_seed, p_sim_start);` **BEFORE**
--      `v_run := twin.ottoq_sim_start_run(...)`. The reset therefore executes while no new run exists.
--   2. **`ottoq.ottoq_active_sim_run_id()` caches its answer in a transaction-local GUC.** It reads
--      `current_setting('ottoq.sim_run_id')`; on a miss it takes
--      `SELECT sim_run_id FROM ottoq_sim_runs WHERE status='running' ORDER BY started_at DESC LIMIT 1` and
--      **`set_config(..., true)` — transaction-local, so it survives for the rest of the pair.**
--   3. **`ottoq_tick_invariance_reset_fleet` writes every vehicle**: `current_soc` (seed-derived),
--      `current_state='offline'`, `current_stall_id`, four tether columns, `current_depot_id`,
--      `last_state_change`, `current_soc_source`, `target_soc=90`, and a whitelisted `config`. The
--      row trigger `ottoq_vehicles_state_change` fires on each and calls `ottoq_active_sim_run_id()`.
--
-- So when arm 2's reset runs, the cached run id is **still arm 1's**, and the cached `ottoq.sim_clock` is
-- still arm 1's final clock. **Arm 2's fleet reset is recorded as 116 events belonging to arm 1, stamped at
-- arm 1's last tick.** Symmetrically, arm 1's own reset was attributed to whatever ran before it.
--
-- **Why no `current_state` in those diffs:** the reset sets `current_state='offline'`, and by the time it
-- runs every vehicle already *is* offline (arm 1 has ended), so that column does not change while SoC,
-- `target_soc`, `config` and `last_state_change` all do. That is why the contamination is invisible to any
-- transition-based analysis and visible to a row count.
--
-- ══ §4 THE FIX, AND WHY IT IS NOT APPLIED HERE ════════════════════════════════
--
-- One line, at the top of each arm's loop body in `ottoq_determinism_pair`, before the reset:
--
--     PERFORM set_config('ottoq.sim_run_id', 'none', true);   -- 'none' is the documented sentinel that
--                                                             -- ottoq_active_sim_run_id maps to NULL
--
-- The reset's writes then belong to **no run**, which is honest — they are harness setup, not simulated
-- behaviour — and both arms' event tables contain only their own ticks. `0092`'s warning ("NEVER cache a
-- miss") does not apply: that was about caching a miss *before a run exists and then blinding the run*;
-- here the sentinel is set deliberately and `twin.ottoq_sim_start_run` overwrites it moments later.
--
-- **Not applied tonight, for one reason and it is not doubt about the fix.** The recert sweep completed
-- 25 minutes ago and all nine canons are green for the first time since `0420`. This change alters
-- `ottoq_events` content for cert runs, so `events` is one of the fourteen and every canon would need
-- re-running again. **Taking the reproducibility apparatus down twice in one morning is a scheduling
-- decision that belongs to Chase**, and nothing is at risk while it waits: the live verdict is correct
-- today and stays correct.
--
-- ══ §5 WHAT IS AND IS NOT COMPROMISED — THE PART TO READ BEFORE QUOTING THIS ═══
--
-- **NOT compromised:** every verdict. Each `h_evt` pair was computed before the next arm's reset existed,
-- so the comparison was over clean, complete, equal sets. Nine pairs genuinely agreed on fourteen atoms.
-- Determinism itself is not in question and neither is `0420` (`0328` §1).
--
-- **NOT compromised: `0328`'s λ measurement.** It reconstructs exposure from events filtered on
-- `payload->'diff' ? 'current_state'`, and **every contaminating row fails that filter** (§2). Both arms
-- read 1,734 transition events; the λ figures are unaffected. Checked rather than assumed, because a
-- denominator built on contaminated rows would have been the sixth such defect in two days.
--
-- **COMPROMISED: auditability.** A verdict that cannot be recomputed from its own evidence is a claim on
-- trust, not on arithmetic. 2.9a's sentence — *"same inputs, byte-identical outputs, verified continuously,
-- across fourteen independent atoms"* — describes a live check and **must not be offered as something a
-- reviewer can re-derive from the archive**, because today they would find nine of nine failing on atom 4.
-- That is the gap between "we verified it" and "you can verify it", and the second is what the claim is
-- worth in hostile diligence.
--
-- **AND IT IS THE FOURTH INSTANCE OF ONE CLASS**, which is why it belongs in the brief rather than a
-- footnote: `0137` hashed a write timestamp, `0139` was id-blind only after a fix, `0216` hashed a
-- `uuid_generate_v4()` session id — each a fingerprint spoiled by something that is not the thing being
-- fingerprinted. **This one is the inverse and the more dangerous shape: the fingerprint is sound and the
-- EVIDENCE moves underneath it.** No amount of care in the digest catches that.
--
-- The honest status: *nine of nine pairs are correctly certified and none of the nine can be re-verified
-- from its stored rows; the cause is one cached setting and the fix is one line, held only so the canon
-- matrix is not reset twice in a morning.*

\echo '=== 0329 §1 — nine certified with no disagreement; nine disagree when recomputed today ==='
WITH pairs AS (
  SELECT certified_at, scenario, seed, ticks, arm_a_run, arm_b_run, disagreeing_atoms
    FROM public.ottoq_determinism_verdict_ledger
   WHERE certified_at >= '2026-09-22 09:00:00+00'
), h AS (
  SELECT p.*,
    (SELECT md5(COALESCE(string_agg(
       event_type||'|'||CASE WHEN entity_type IN ('ocpp_session','service_detail_record','sim_run')
                             THEN '-' ELSE COALESCE(entity_id::text,'-') END||'|'||
       COALESCE(e.sim_clock_at::text,'-'), E'\n'
       ORDER BY event_type, CASE WHEN entity_type IN ('ocpp_session','service_detail_record','sim_run')
                                 THEN '-' ELSE COALESCE(entity_id::text,'-') END, e.sim_clock_at), ''))
       FROM public.ottoq_events e WHERE e.sim_run_id=p.arm_a_run) AS h_evt_a_now,
    (SELECT md5(COALESCE(string_agg(
       event_type||'|'||CASE WHEN entity_type IN ('ocpp_session','service_detail_record','sim_run')
                             THEN '-' ELSE COALESCE(entity_id::text,'-') END||'|'||
       COALESCE(e.sim_clock_at::text,'-'), E'\n'
       ORDER BY event_type, CASE WHEN entity_type IN ('ocpp_session','service_detail_record','sim_run')
                                 THEN '-' ELSE COALESCE(entity_id::text,'-') END, e.sim_clock_at), ''))
       FROM public.ottoq_events e WHERE e.sim_run_id=p.arm_b_run) AS h_evt_b_now
    FROM pairs p
)
SELECT count(*) AS pairs_certified,
       count(*) FILTER (WHERE disagreeing_atoms = '{}') AS verdict_said_no_disagreement,
       count(*) FILTER (WHERE h_evt_a_now =  h_evt_b_now) AS events_atom_agrees_today,
       count(*) FILTER (WHERE h_evt_a_now <> h_evt_b_now) AS events_atom_DISAGREES_today
  FROM h;
-- 9 / 9 / 0 / 9. The h_evt expression is copied verbatim from ottoq_determinism_pair, including its
-- entity-blanking CASE and its ORDER BY; it filters nothing, so a row-count difference cannot hide.

\echo '=== 0329 §2 — the difference is one write per vehicle, at arm As FINAL clock, SoC-shaped ==='
WITH pairs AS (
  SELECT arm_a_run, arm_b_run, scenario, seed, ticks,
         row_number() OVER (ORDER BY certified_at) AS ord
    FROM public.ottoq_determinism_verdict_ledger
   WHERE certified_at >= '2026-09-22 09:00:00+00'
), arms AS (
  SELECT ord, scenario, seed, ticks, 'A' AS arm, arm_a_run AS rid FROM pairs
  UNION ALL SELECT ord, scenario, seed, ticks, 'B', arm_b_run FROM pairs
)
SELECT a.ord, a.scenario, a.seed, a.ticks, a.arm,
       (SELECT count(*) FROM public.ottoq_events e
         WHERE e.sim_run_id=a.rid AND e.event_type='vehicle.state_changed'
           AND e.sim_clock_at = s.sim_clock_current
           AND NOT (e.payload->'diff' ? 'current_state'))        AS soc_only_at_final_clock,
       (SELECT count(*) FROM public.ottoq_events e
         WHERE e.sim_run_id=a.rid AND e.event_type='vehicle.state_changed') AS all_state_changed,
       (SELECT count(*) FROM public.ottoq_events e
         WHERE e.sim_run_id=a.rid AND e.event_type='vehicle.state_changed'
           AND (e.payload->'diff' ? 'current_state'))            AS transition_events
  FROM arms a JOIN public.ottoq_sim_runs s ON s.sim_run_id=a.rid
 ORDER BY a.ord, a.arm;
-- Every pair: arm A exceeds arm B by exactly the depot's vehicle count, in both the all_state_changed
-- and the soc_only_at_final_clock column, while transition_events is IDENTICAL. Nothing about the
-- simulated state machine diverged.

\echo '=== 0329 §3 — the cached setting that causes it, from source ==='
SELECT n.nspname||'.'||p.proname AS fn,
       (p.prosrc LIKE '%set_config(''ottoq.sim_run_id''%')                      AS caches_the_run_id,
       (p.prosrc LIKE '%status = ''running''%')                                 AS falls_back_to_newest_running
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='ottoq' AND p.proname='ottoq_active_sim_run_id';

\echo '=== 0329 §3 — and the ordering in the pair that makes the cache stale ==='
-- COMMENT-STRIPPED, and that is not decoration: the first draft of this query returned FALSE because
-- `twin.ottoq_sim_start_run` appears in the 0175 comment block at the top of the function, so position()
-- found the comment rather than the call. prosrc carries comments; the same trap 0220 and 0414 recorded,
-- hit again here in the assertion meant to prove §3.
WITH s AS (
  SELECT regexp_replace(
           regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^'||chr(10)||']*','','g'),
           E'\\s+',' ','g') AS src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair'
)
SELECT position('ottoq_tick_invariance_reset_fleet' in src) AS pos_reset,
       position('twin.ottoq_sim_start_run' in src)          AS pos_start_run,
       (position('ottoq_tick_invariance_reset_fleet' in src) > 0
        AND position('ottoq_tick_invariance_reset_fleet' in src)
            < position('twin.ottoq_sim_start_run' in src))  AS reset_runs_BEFORE_the_run_is_created,
       (position('set_config(''ottoq.sim_run_id''' in src) = 0) AS pair_never_clears_the_cached_run_id
  FROM s;
-- 880 / 954 / true / true. One transaction, two arms, a transaction-local cache that is never reset, and
-- a fleet reset that runs before its own run exists -- so arm 2's setup is filed as arm 1's evidence.

\echo '=== 0329 §5 — and 0328s lambda measurement is NOT affected: contaminants fail its filter ==='
WITH arms(label, rid) AS (VALUES
  ('A','c32754de-a827-4eef-97e6-d4382a6e8513'::uuid),
  ('B','cf95a88f-1587-4239-a9c0-6779f0a9de08'::uuid))
SELECT a.label,
       count(*) FILTER (WHERE e.payload->'diff' ? 'current_state')       AS transition_events_used_by_0328,
       count(*) FILTER (WHERE NOT (e.payload->'diff' ? 'current_state')) AS excluded_by_the_filter
  FROM arms a JOIN public.ottoq_events e ON e.sim_run_id=a.rid
 WHERE e.event_type='vehicle.state_changed'
 GROUP BY a.label ORDER BY a.label;
-- 1,734 in both arms. 0328 reconstructs exposure only from transition-carrying events, and every
-- contaminating row lacks current_state, so the lambda figures stand. Checked, not assumed.
