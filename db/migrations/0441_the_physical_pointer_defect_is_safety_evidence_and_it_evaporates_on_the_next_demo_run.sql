-- migration-version: 20260923023300
-- migration-name:    the_physical_pointer_defect_is_safety_evidence_and_it_evaporates_on_the_next_demo_run
--
-- 0441  **G157's 49 physical-pointer divergences — a charging stall that records a DIFFERENT vehicle, or
--       no vehicle, while a charge session is open on it — are recorded in exactly one place,
--       `ottoq_rule_evaluations`, and that table is `class='engine'`. A demo run started at 02:15 UTC
--       today took it from ~150,000 rows to 208 BETWEEN TWO OF MY OWN QUERIES (`db/checks/0350`).**
--
--       So the count of a `critical` safety rule's failures is not a slow-moving total that drifts; it
--       is a per-run working set that a colleague starting a demo can take to zero while a sentence
--       about it is being written. **That makes the defect unquantifiable in BOTH directions** — "G157
--       happens 49 times" and "G157 does not happen" are equally unsupported the morning after — which
--       is the argument `0231` made for cuOpt and `0340` settled with an append-only `class='evidence'`
--       ledger. This is that pattern, applied to physical-space integrity.
--
--       **THIS MIGRATION CHANGES NO ENFORCEMENT AND NO DECIDE PATH.** It adds one table, one capture
--       trigger on the ledger of rule evaluations, one view and one assertion. HW.006 stays advisory —
--       `0346` §3's finding that enforcing it today would refuse 7.7% of L2 charge completions is
--       unchanged, and `0345`'s rule (fix the input, measure the rate, promote ONE checkpoint) is why
--       this file measures instead of promoting.
--
--       `forces_recert` **FALSE**: one new evidence table plus read-only objects; no engine function is
--       altered, and no verdict atom reads any of them (`h_evt` digests
--       `event_type|entity_id|sim_clock_at` and nothing else).
--
-- ══ §1 WHAT G157 ACTUALLY IS, NOW THAT BOTH PRODUCERS ARE IDENTIFIED ═════════
--
-- `0347` found the writer that clears the stall pointer — `public.sync_stall_occupancy`, an
-- `AFTER UPDATE ON public.vehicles` trigger — and concluded *"the tether exemption IS the l2/dcfc
-- split."* **That is half right, and the half that is wrong matters.**
--
--   (a) **The split is real but not a boundary.** On 30x `0346`'s evidence: `dcfc` fails **7 of 727
--       (0.96%)**, `l2` **39 of 420 (9.29%)**. The tether is a **~10x reduction, not an exemption**
--       (`0350` §5). Any sentence confining G157 to L2 is wrong.
--
--   (b) **The tether is not a charging guard at all — it is the ROBOTIC ARM's lease.** It is written
--       only by `twin.ottoq_arm_begin_cycle` and `twin.ottoq_arm_advance_cycles` (and extended by
--       `twin.ottoq_sim_stop_charge_session`). Measured on a live run: **8 of 8 `dcfc` sessions
--       tethered, 0 of 24 `l2`.** So G157's "l2 vs dcfc" is really **"stalls an arm serves vs stalls
--       it does not"**, and it protects DCFC only incidentally.
--
--   (c) **Transcribing the trigger's exemption as a predicate gives an exposure census, which does not
--       require waiting for an incident.** Live: `l2` **22 of 22 exposed**, `dcfc` **0 of 9**. Note the
--       guard tests `robotic_tether_until IS NOT NULL` and **never that it is in the future**, so an
--       expired-but-unreaped tether still exempts — the exposure is absence or mismatch, not staleness.
--
--   (d) **And the DCFC producer is a different function, found by reading it:
--       `public.ottoq_release_expired_tethers`.** On expiry with `direction='demate'` it clears the
--       vehicle's `current_stall_id` AND, in its `freed` CTE, sets the stall's `current_vehicle_id =
--       NULL` with `status → 'available'`. **It never consults `ocpp_sessions`.** So when an arm lease
--       expires mid-charge, both pointers are cleared under an open session — G157's `pointer_empty`
--       form on `dcfc`. (It writes status and pointer **together**, so it is *not* a G121 producer;
--       G121 needs `available` WITH a live pointer. Keeping those two apart is exactly the conflation
--       `0333` made in the other direction.)
--
--   **THE ROOT CAUSE, STATED ONCE: no writer of `vehicles.current_stall_id` or `stalls.current_vehicle_id`
--   consults `ocpp_sessions` for an open session.** Of the 22 functions that write
--   `vehicles.current_stall_id`, **three mention `ocpp_sessions` at all**, and two of those are reset
--   harnesses (`ottoq_benchmark_reset`, `ottoq_sim_release_depot`). The site's three-gate availability
--   doctrine (pointer · calendar · charger-not-faulted) has **no fourth gate for "a session is open
--   here."**
--
--   **That fourth gate is NOT built here, deliberately.** It changes the offer path, which is the
--   certified decide path, and the decision of whether to refuse or to repair belongs on durable
--   evidence rather than on a population that a demo run deletes. This file makes that evidence exist.
--
-- ══ §2 WHY A NEW TABLE RATHER THAN AN EXISTING ONE — I CHECKED BOTH ══════════
--
-- Rule 5 forbids duplicating an existing capability, so both candidates were measured, not assumed:
--
--     table                     registry class   rows after the 02:15 purge
--     ottoq_rule_evaluations    engine           208          (was ~150,000)
--     space_conflict_ledger     engine           24 / 2 runs  (was 2,312)
--
-- **`space_conflict_ledger` is the near-miss worth recording.** It is shaped almost perfectly for this
-- — `stall_id`, `conflict_kind`, `resolution`, `present_vehicle_id`, `displaced_vehicle_id` — and
-- before the purge it read 2,312 rows with `min(recorded_at) = 2026-08-30`, from which I concluded it
-- survives purges. **After the purge it STILL reads `min(recorded_at) = 2026-08-30`**, because a
-- couple of old rows remain. **A table's earliest row says nothing about whether it is purged: the
-- purge is by run, not chronological.** Read `ottoq_run_scope_registry.class`. (Its vocabulary
-- confirms the loss: `0347` saw `standing_claim_contradicted` and `stale_claim_displaced`; one kind
-- remains.)
--
-- So there is no durable home to extend, and the `0340`/`0364` pattern is the house answer.
--
-- ══ §3 THE REGISTRY CONTRACT, READ RATHER THAN ASSUMED ═══════════════════════
--
-- From `public.ottoq_check_run_scope_registry()`'s own source:
--
--   * a table carrying `sim_run_id` and **not** registered raises a `warn` — so it must be registered;
--   * `class IN ('engine','stamp')` **requires** an FK to `ottoq_sim_runs` (`block` if absent), and an
--     `ON DELETE CASCADE` FK to it is also `block`. `evidence` requires neither, which is why `0340`
--     gave its ledger **no FK**: an enforcing FK on evidence can only block the purge or, as CASCADE,
--     erase what must not be erased;
--   * the append-only-guard check — *"does not honour `set_config('ottoq.retention')`"* — is filtered
--     **`WHERE g.class = 'engine'`**. **Verified before writing this file, because if it applied to
--     every class an unconditional guard here would make `ottoq_purge_prior_runs` RAISE and every
--     future demo run fail.** It does not. An unconditional guard on evidence is correct and is what
--     `ottoq_model_call_ledger_append_only` already does.
--
-- ══ §4 THE PAYLOAD KEYS COME FROM THE EVALUATOR, NOT FROM A SAMPLE ═══════════
--
-- `0340`'s defect was a probe spelling a key `svc` while the evaluator read `service_code`. So the keys
-- here are taken from `public.ottoq_eval_hw_006_presence_verification`'s source. Its failure branch,
-- and **only** its failure branch, emits:
--
--     'stall_id', 'expected_vehicle_id', 'stall_current_vehicle_id'
--
-- (the two passing branches emit `stall_id` + `vehicle_id`). **`expected_vehicle_id` is therefore an
-- exact discriminator of a real presence failure**, and the capture trigger's `WHEN` clause uses it
-- rather than matching on the reason text. A sample could not have established this: at the moment of
-- writing, the live run had produced HW.006 passes and no failures at all.
--
-- ══ §5 THE DEDUPLICATION IS PART OF THE SCHEMA, BECAUSE COUNTING THIS WRONG IS THE DEFAULT ══
--
-- `0346` established that this ledger carries ~2 rows per `(stall, vehicle, evaluated_at)` triple, so
-- quoting the row count doubles the defect; `0350` §6 found the sharper form — **3 triples carry both
-- a passed and a failed row**, so a `DISTINCT ON` whose key omits `passed` keeps whichever sorts first
-- and **reports 46 incidents where there are 49**. My own first pass did that.
--
-- **So the unique index is the fix, not a query convention:** one row per
-- `(run, stall, expected_vehicle, evaluated_at)`, `ON CONFLICT DO NOTHING`. The ledger counts
-- INCIDENTS by construction, and no reader can get 46 by being careless. `sim_run_id` is wrapped in
-- `COALESCE` because NULLs do not conflict in a plain unique index, which would silently re-admit the
-- duplication for any row without a run.
--
-- **What this ledger still cannot say: WHO cleared the pointer.** `ottoq_probe_task_completion` takes
-- no argument naming its caller, so the producer is inferred from the facts captured beside the
-- incident (stall type, tether state) and is **not** recorded as fact. That is the same gap G148/G149
-- keep naming — the ledger records what was decided, not who asked — and the honest fix is a
-- `p_source` argument, which is tracked separately and not smuggled in here.

BEGIN;

-- ── P1 · the registry must be clean before adding to it ──────────────────────
DO $p1$
DECLARE v_block int;
BEGIN
  SELECT count(*) FILTER (WHERE severity='block') INTO v_block
    FROM public.ottoq_check_run_scope_registry();
  IF v_block > 0 THEN
    RAISE EXCEPTION '0441 P1: run-scope registry already has % blocking defect(s); fix before adding a table', v_block;
  END IF;
END $p1$;

-- ── P2 · the engine-only filter on the append-only-guard check (see §3) ──────
DO $p2$
DECLARE v_src text;
BEGIN
  SELECT regexp_replace(regexp_replace(prosrc,'/\*.*?\*/','','g'),'--[^'||chr(10)||']*','','g')
    INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_check_run_scope_registry';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0441 P2: ottoq_check_run_scope_registry() not found';
  END IF;
  IF v_src !~ 'retention' THEN
    RAISE EXCEPTION '0441 P2: the retention guard check is absent; re-read the registry contract';
  END IF;
  IF v_src !~ 'g\.class\s*=\s*''engine''' THEN
    RAISE EXCEPTION '0441 P2: the append-only-guard check is NOT filtered to class=engine. An '
      'unconditional guard on an evidence table would make ottoq_purge_prior_runs RAISE and every '
      'demo run fail. Re-read the check before proceeding.';
  END IF;
END $p2$;

-- ── P3 · the payload keys, asserted against the evaluator's own source ───────
DO $p3$
DECLARE v_src text;
BEGIN
  SELECT regexp_replace(regexp_replace(prosrc,'/\*.*?\*/','','g'),'--[^'||chr(10)||']*','','g')
    INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_eval_hw_006_presence_verification';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0441 P3: HW.006 evaluator not found under the name ottoq_rules declares';
  END IF;
  IF v_src !~ 'expected_vehicle_id' OR v_src !~ 'stall_current_vehicle_id' THEN
    RAISE EXCEPTION '0441 P3: the HW.006 evaluator does not emit the keys this capture reads. '
      'Re-read it -- this is the 0340 svc/service_code defect.';
  END IF;
END $p3$;

-- ── the ledger ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ottoq_space_integrity_ledger (
  incident_id              bigserial PRIMARY KEY,
  recorded_at              timestamptz NOT NULL DEFAULT now(),
  -- DELIBERATELY NO FK to ottoq_sim_runs: see §3. An enforcing FK on evidence can only block the
  -- purge or, as CASCADE, erase what this table exists to keep.
  sim_run_id               uuid,
  depot_id                 uuid,
  evaluated_at             timestamptz NOT NULL,
  sim_clock                timestamptz,
  rule_code                text        NOT NULL,
  action_context           text,
  incident_kind            text        NOT NULL
    CHECK (incident_kind IN ('pointer_empty','holds_different_vehicle')),
  stall_id                 uuid        NOT NULL,
  stall_type               text,
  stall_status             text,
  expected_vehicle_id      uuid        NOT NULL,
  stall_current_vehicle_id uuid,
  -- context captured AT DETECTION, because it is unrecoverable afterwards
  had_open_charge_session  boolean,
  open_session_started_at  timestamptz,
  tether_until             timestamptz,
  tether_stall_id          uuid,
  exposed_to_pointer_clear boolean,
  source_evaluation_id     uuid,          -- ottoq_rule_evaluations.evaluation_id is UUID, not bigint
  detail                   jsonb       NOT NULL DEFAULT '{}'::jsonb
);

-- one row per incident, not per ledger row (§5). COALESCE because NULLs do not conflict.
CREATE UNIQUE INDEX IF NOT EXISTS ottoq_space_integrity_ledger_incident_uk
  ON public.ottoq_space_integrity_ledger
     (COALESCE(sim_run_id,'00000000-0000-0000-0000-000000000000'::uuid),
      stall_id, expected_vehicle_id, evaluated_at);

CREATE INDEX IF NOT EXISTS ottoq_space_integrity_ledger_run_idx
  ON public.ottoq_space_integrity_ledger (sim_run_id, evaluated_at DESC);

-- ── append-only, unconditionally (evidence, not engine — §3) ────────────────
CREATE OR REPLACE FUNCTION public.ottoq_space_integrity_ledger_append_only()
RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
  RAISE EXCEPTION
    'ottoq_space_integrity_ledger is append-only evidence (0441): % refused. It is class=evidence and '
    'is deliberately not clearable by ottoq_purge_prior_runs.', TG_OP;
END $fn$;

DROP TRIGGER IF EXISTS ottoq_space_integrity_ledger_append_only_trg
  ON public.ottoq_space_integrity_ledger;
CREATE TRIGGER ottoq_space_integrity_ledger_append_only_trg
  BEFORE DELETE OR UPDATE ON public.ottoq_space_integrity_ledger
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_space_integrity_ledger_append_only();

-- ── the capture, error-swallowing (0340's pattern: a capture must never break its writer) ──
CREATE OR REPLACE FUNCTION public.ottoq_capture_space_integrity_incident()
RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE
  v_stall_id  uuid;
  v_expected  uuid;
  v_held      uuid;
  v_st        record;
  v_veh       record;
  v_sess      record;
  v_exposed   boolean;
BEGIN
  v_stall_id := NULLIF(NEW.result_payload->>'stall_id','')::uuid;
  v_expected := NULLIF(NEW.result_payload->>'expected_vehicle_id','')::uuid;
  v_held     := NULLIF(NEW.result_payload->>'stall_current_vehicle_id','')::uuid;

  IF v_stall_id IS NULL OR v_expected IS NULL THEN
    RETURN NULL;   -- not a resolvable presence failure; nothing to record
  END IF;

  SELECT s.stall_type::text AS stall_type, s.status::text AS status, s.depot_id
    INTO v_st FROM public.stalls s WHERE s.id = v_stall_id;

  SELECT v.robotic_tether_until, v.robotic_tether_stall_id
    INTO v_veh FROM public.vehicles v WHERE v.id = v_expected;

  SELECT o.started_at
    INTO v_sess
    FROM public.ocpp_sessions o
   WHERE o.stall_id = v_stall_id AND o.vehicle_id = v_expected AND o.status = 'active'
   ORDER BY o.started_at DESC LIMIT 1;

  -- sync_stall_occupancy's exemption, transcribed (§1c)
  v_exposed := NOT (v_veh.robotic_tether_until IS NOT NULL
                    AND v_veh.robotic_tether_stall_id IS NOT DISTINCT FROM v_stall_id);

  INSERT INTO public.ottoq_space_integrity_ledger (
    sim_run_id, depot_id, evaluated_at, sim_clock, rule_code, action_context,
    incident_kind, stall_id, stall_type, stall_status,
    expected_vehicle_id, stall_current_vehicle_id,
    had_open_charge_session, open_session_started_at,
    tether_until, tether_stall_id, exposed_to_pointer_clear,
    source_evaluation_id, detail)
  VALUES (
    NEW.sim_run_id, COALESCE(NEW.depot_id, v_st.depot_id), NEW.evaluated_at,
    NULL, NEW.rule_code, NEW.action_context,
    CASE WHEN v_held IS NULL THEN 'pointer_empty' ELSE 'holds_different_vehicle' END,
    v_stall_id, v_st.stall_type, v_st.status,
    v_expected, v_held,
    (v_sess.started_at IS NOT NULL), v_sess.started_at,
    v_veh.robotic_tether_until, v_veh.robotic_tether_stall_id, v_exposed,
    NEW.evaluation_id,
    jsonb_build_object('severity', NEW.severity, 'enforcement', NEW.enforcement,
                       'reason', NEW.reason))
  ON CONFLICT DO NOTHING;   -- one row per incident (§5)

  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  -- never break the shield's own write
  RAISE WARNING '0441 space-integrity capture: %', SQLERRM;
  RETURN NULL;
END $fn$;

DROP TRIGGER IF EXISTS ottoq_capture_space_integrity_incident_trg
  ON public.ottoq_rule_evaluations;
CREATE TRIGGER ottoq_capture_space_integrity_incident_trg
  AFTER INSERT ON public.ottoq_rule_evaluations
  FOR EACH ROW
  WHEN (NEW.passed = false
        AND NEW.rule_code LIKE 'HW.006%'
        AND NEW.result_payload ? 'expected_vehicle_id')
  EXECUTE FUNCTION public.ottoq_capture_space_integrity_incident();

-- ── backfill whatever survives right now (0 is a legitimate answer) ──────────
INSERT INTO public.ottoq_space_integrity_ledger (
  sim_run_id, depot_id, evaluated_at, rule_code, action_context, incident_kind,
  stall_id, stall_type, stall_status, expected_vehicle_id, stall_current_vehicle_id,
  source_evaluation_id, detail)
SELECT re.sim_run_id, COALESCE(re.depot_id, s.depot_id), re.evaluated_at, re.rule_code,
       re.action_context,
       CASE WHEN NULLIF(re.result_payload->>'stall_current_vehicle_id','') IS NULL
            THEN 'pointer_empty' ELSE 'holds_different_vehicle' END,
       (re.result_payload->>'stall_id')::uuid, s.stall_type::text, s.status::text,
       (re.result_payload->>'expected_vehicle_id')::uuid,
       NULLIF(re.result_payload->>'stall_current_vehicle_id','')::uuid,
       re.evaluation_id,
       jsonb_build_object('backfilled', true, 'reason', re.reason)
  FROM public.ottoq_rule_evaluations re
  LEFT JOIN public.stalls s ON s.id = (re.result_payload->>'stall_id')::uuid
 WHERE re.rule_code LIKE 'HW.006%' AND re.passed = false
   AND re.result_payload ? 'expected_vehicle_id'
   AND NULLIF(re.result_payload->>'stall_id','') IS NOT NULL
ON CONFLICT DO NOTHING;

-- ── the reading surface ─────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.ottoq_space_integrity_summary AS
SELECT COALESCE(stall_type,'(unknown)') AS stall_type,
       incident_kind,
       count(*)                                        AS incidents,
       count(DISTINCT sim_run_id)                      AS runs,
       count(DISTINCT stall_id)                        AS stalls,
       count(DISTINCT expected_vehicle_id)             AS vehicles,
       count(*) FILTER (WHERE had_open_charge_session) AS with_open_session_at_detection,
       count(*) FILTER (WHERE exposed_to_pointer_clear) AS untethered_at_detection,
       min(evaluated_at)                               AS first_seen,
       max(evaluated_at)                               AS last_seen
  FROM public.ottoq_space_integrity_ledger
 GROUP BY 1,2;

CREATE OR REPLACE FUNCTION public.ottoq_assert_space_integrity(p_sim_run_id uuid DEFAULT NULL)
RETURNS TABLE (metric text, value text, verdict text)
LANGUAGE sql STABLE AS $fn$
  WITH l AS (
    SELECT * FROM public.ottoq_space_integrity_ledger
     WHERE p_sim_run_id IS NULL OR sim_run_id = p_sim_run_id)
  SELECT 'incidents', count(*)::text,
         CASE WHEN count(*)=0 THEN 'NONE RECORDED' ELSE 'OPEN (G157)' END FROM l
  UNION ALL
  SELECT 'holds_different_vehicle', count(*)::text,
         CASE WHEN count(*)=0 THEN 'OK'
              ELSE 'SERIOUS -- a charger physically allocated twice' END
    FROM l WHERE incident_kind='holds_different_vehicle'
  UNION ALL
  SELECT 'pointer_empty', count(*)::text,
         CASE WHEN count(*)=0 THEN 'OK' ELSE 'OPEN -- pointer cleared under an open session' END
    FROM l WHERE incident_kind='pointer_empty'
  UNION ALL
  SELECT 'distinct runs affected', count(DISTINCT sim_run_id)::text, 'INFORMATION' FROM l
  UNION ALL
  SELECT 'rows per incident', COALESCE(round(count(*)::numeric
           / NULLIF(count(DISTINCT (COALESCE(sim_run_id,'00000000-0000-0000-0000-000000000000'::uuid),
                                    stall_id, expected_vehicle_id, evaluated_at)),0),3)::text,'n/a'),
         CASE WHEN count(*) = count(DISTINCT (COALESCE(sim_run_id,'00000000-0000-0000-0000-000000000000'::uuid),
                                              stall_id, expected_vehicle_id, evaluated_at))
              THEN 'OK -- 1.000 by unique index'
              ELSE 'BROKEN -- the unique index is not holding' END
    FROM l;
$fn$;

-- ── registry: evidence, so ottoq_purge_prior_runs leaves it alone ────────────
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public','ottoq_space_integrity_ledger','sim_run_id','evidence',
        '0441 (G157): the durable record of physical-space integrity incidents -- a stall whose '
        'current_vehicle_id disagrees with an open charge session. Evidence, not engine: the defect it '
        'measures is a critical safety finding and its only prior home (ottoq_rule_evaluations, engine) '
        'is emptied by every demo run, which made the defect unquantifiable in both directions. No FK '
        'to ottoq_sim_runs by design.')
ON CONFLICT (table_schema, table_name, column_name)
DO UPDATE SET class = EXCLUDED.class, note = EXCLUDED.note;

COMMENT ON TABLE public.ottoq_space_integrity_ledger IS
  '0441 (G157) append-only, class=evidence. One row per physical-space integrity incident: a stall '
  'whose current_vehicle_id is empty or holds a different vehicle while a charge session is open on '
  'it. Filled by a capture trigger on ottoq_rule_evaluations (HW.006 failures carrying '
  'expected_vehicle_id -- the only branch of the evaluator that emits that key). ONE ROW PER INCIDENT '
  'by unique index: the source ledger carries ~1.5 rows per (stall, vehicle, evaluated_at) triple and '
  'three of those triples disagree on `passed`, so a DISTINCT ON over it reports 46 where there are 49 '
  '(0350 s6). It does NOT record WHO cleared the pointer -- the probe takes no caller argument.';

COMMENT ON VIEW public.ottoq_space_integrity_summary IS
  '0441: G157 by stall type and incident kind. `holds_different_vehicle` is the serious form -- the '
  'physical pointer disagreeing with the session, which the ottoq_stall_bookings EXCLUDE constraint '
  'cannot catch because it guards the calendar, not the pointer. Read `runs` beside `incidents`: a '
  'determinism pair cannot produce independent samples (G153, 0339), so count distinct runs.';

COMMENT ON FUNCTION public.ottoq_assert_space_integrity(uuid) IS
  '0441: G157''s verdict, per run or lifetime. `rows per incident` must read 1.000 -- if it does not, '
  'the unique index is not holding and every count from this ledger is inflated.';

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
  ('0441_the_physical_pointer_defect_is_safety_evidence_and_it_evaporates_on_the_next_demo_run', FALSE,
   'One new class=evidence table (ottoq_space_integrity_ledger) with an append-only guard, a capture '
   'trigger on ottoq_rule_evaluations gated to HW.006 failures carrying expected_vehicle_id, a summary '
   'view and an assertion. No engine function altered, no enforcement changed, HW.006 stays advisory '
   '(0346 s3: enforcing it today would refuse 7.7% of L2 charge completions). FALSE: no verdict atom '
   'reads any of these objects -- h_evt digests event_type|entity_id|sim_clock_at only -- and the one '
   'write path added is an AFTER INSERT trigger on a ledger no atom digests.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert, note = EXCLUDED.note;

COMMIT;

-- ══ §6 VERIFICATIONS (run after applying) ════════════════════════════════════
--
--   -- V1 append-only, BOTH operations
--   UPDATE public.ottoq_space_integrity_ledger SET stall_type='x';   -- must RAISE
--   DELETE FROM public.ottoq_space_integrity_ledger;                 -- must RAISE
--
--   -- V2 the purge still works: the registry must report no blocking defect
--   SELECT count(*) FILTER (WHERE severity='block') AS blocking
--     FROM public.ottoq_check_run_scope_registry();                  -- must be 0
--
--   -- V3 the capture fires, and is idempotent under the duplication (rolled back)
--   -- V4 the assertion
--   SELECT * FROM public.ottoq_assert_space_integrity();
--   SELECT * FROM public.ottoq_space_integrity_summary ORDER BY incidents DESC;
--
-- **V2 IS THE ONE THAT MATTERS MOST AND IS NOT A FORMALITY.** A new table carrying `sim_run_id` that
-- the registry does not recognise raises a `warn`, and a *wrongly classified* one can make
-- `ottoq_purge_prior_runs` RAISE — which would fail every demo run, not merely this file. P1 checks the
-- registry was clean going in; V2 checks it is clean coming out. Run V2 before starting a run.
--
-- **And note what a clean V4 does NOT mean.** The ledger starts empty because the 02:15 purge took the
-- 49 incidents before this table existed, so `NONE RECORDED` on day one is an empty instrument, not a
-- clean depot — exactly the `ottoq_ab_runs` mistake `db/checks/0145` caught, where a well-shaped table
-- with no writer was read as a working one. It becomes evidence only after a run produces an incident,
-- and `0350` §5 says to expect roughly 9% of L2 charge completions and 1% of DCFC.

-- ══ APPLIED 20260923023300 (2026-09-23 02:33 UTC / 2026-09-22 09:33 PM CT) ═══
--
-- **P1, P2, P3 all passed.** P2 is the one that earned its place: it asserts the append-only-guard
-- check is filtered `WHERE g.class = 'engine'`, and had it not been, the unconditional guard below
-- would have made `ottoq_purge_prior_runs` RAISE and **every future demo run fail**. That was checked
-- before the guard was written, not after.
--
-- **V1: UPDATE refused, DELETE refused** — both, on a seeded row, with the probe rolled back.
-- **V2: 0 blocking registry defects and 0 self-flags** — the purge is still safe and the registry
-- recognises the new table. Run V2 before starting a run, not after.
-- **V3: two evaluations of ONE incident produced ONE ledger row**, `incident_kind` =
-- `holds_different_vehicle`, `stall_type` = `l2` (so the capture's three lookups ran), and
-- `exposed_to_pointer_clear` = **true**, which is §1(c)'s prediction for an L2 stall. Rolled back.
-- **V4: the assertion reads 0 incidents / `rows per incident` OK.**
--
-- **AND V4's ZERO IS AN EMPTY INSTRUMENT, NOT A CLEAN DEPOT.** The 02:15 purge took the 49 incidents
-- before this table existed, so the backfill inserted **0 rows** — it is the `ottoq_ab_runs` shape
-- `db/checks/0145` caught, where a well-formed table with no data was read as a working one. It
-- becomes evidence only once a run produces an incident; `0350` §5 says to expect ~9% of L2 charge
-- completions and ~1% of DCFC.
--
-- ══ RENUMBERED FROM 0431, AND THE REASON IS A HAZARD WORTH MORE THAN THE RENAME ══
--
-- This file was written as `0431`. It is `0441` because **0431 through 0440 were already taken**, by a
-- concurrent session working on the same database:
--
--     0431 a_quarter_of_departures_skipped_the_readiness_check…    0436 the_twins_afternoon_peaked_at_eight_pm…
--     0432 the_agent_could_rewrite_the_simulated_demand…           0437 the_readiness_check_had_a_second_door…
--     0433 a_demand_response_reduction_was_read_as_the_depots…     0438 three_of_the_agents_five_dials_did_nothing…
--     0434 three_consumers_of_the_deploy_demand_defaulted_it…      0439 the_learning_loop_had_nothing_to_compare…
--     0435 the_battery_planned_eight_hours_ahead…                  0440 the_dial_runner_lost_its_lock…
--
-- **Ten migrations are APPLIED to this database and are NOT in the repository** — `origin/main` ends at
-- `0430`. So for the moment **the repo is not ground truth for the schema**, which inverts the
-- assumption every check file in `db/checks/` is written under. Anyone reading migration files to learn
-- what the engine does today is reading a prefix. Read `ottoq_cert_lineage` and
-- `supabase_migrations.schema_migrations`; they are the authority until those files land.
--
-- **The collision was detected by accident and could easily have been missed.** Nothing warned me: the
-- number was free in the repo, and `ottoq_cert_lineage` briefly held **two rows both starting `0431`**
-- until I noticed a sibling migration whose own name contains the string `0431`. The duplicate row has
-- been removed and this file's row re-inserted as `0441`. **A migration number must be checked against
-- `ottoq_cert_lineage`, never against `ls db/migrations`.**
--
-- **AND IT EXPLAINS THE PURGE THAT ATE THIS FILE'S MOTIVATING MEASUREMENT.** `db/checks/0350` records
-- that `ottoq_rule_evaluations` fell from ~150,000 rows to 208 *between two of my own queries*, which I
-- attributed to "a demo run started at 02:15." It was the other session's run. **Two agents on one
-- `class='engine'` database will silently delete each other's evidence** — not through any fault in the
-- purge, which is doing exactly its job, but because run-scoped working data has one global namespace.
-- That is the strongest argument this file could have for its own existence: the ledger it adds is
-- `class='evidence'` precisely so the next concurrent run cannot take it.
--
-- **What is NOT claimed:** no attempt was made to reconcile with those ten migrations. They touch
-- readiness checks, demand-response ceilings, BESS planning, the twin's diurnal curve and the agent's
-- dials; this file touches none of those, and its only write path is an `AFTER INSERT` trigger on a
-- ledger no atom digests. The objects here were created with `IF NOT EXISTS` / `OR REPLACE` and none
-- pre-existed. **But "no conflict was found" and "no conflict exists" are different statements, and
-- only the first was verified.**
