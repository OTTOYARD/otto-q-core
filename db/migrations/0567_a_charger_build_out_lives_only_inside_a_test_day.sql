-- migration-version: 20260929191451
-- migration-name:    a_charger_build_out_lives_only_inside_a_test_day
--
-- 0567  **A robotic fast-charger build-out the twin can test, which lives only inside the test day that uses it.**
--       Lane A, phase 2. Chase, 2026-09-29: "150-200 vehicles can be accommodated at any given time through 10-20 DCFC
--       robotic chargers, a couple wash bays, and a service bay or two. I'm starting to get away from the L2 strategy,
--       only bc they are so slow ... Just make sure to accomodate robotic arms with the DCFC for quick connections."
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   The twin depot has 10 fast chargers (CANOPY-01, ABB Terra HP 350, each with an OTTO-CHARGE ARM) and 30 L2 spaces
--   (CANOPY-02 and -03, 19.2 kW). To measure 15 and 20 fast chargers, the twin needs those chargers, on the one site
--   rule 8 allows. Changing the depot for good would change every demo and every certified canon column, and the 3D
--   depot has no drawing for them yet (Lane D's rendering work lands first). So a build-out is applied INSIDE the one
--   transaction a test day runs in, and taken back out before that transaction ends. Nobody else ever sees it: the
--   cockpit, the demo, the canon and the other lanes keep reading the depot as built.
--
-- ══ §2 WHAT THIS BUILDS ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   public.ottoq_site_buildouts                 the build-outs, as data: which L2 spaces become robotic fast chargers,
--                                               the fast-charger count that results, and the site power that goes with
--                                               it, each figure with its source.
--   public.ottoq_site_buildout_apply(depot, code)
--                                               converts the named L2 spaces to 350 kW robotic fast chargers: stall
--                                               type, connector rating, a fiducial and a UWB beacon for the arm's
--                                               registration (the ten it joins carry both), zone, the charger's rating
--                                               and make, the space's charge capability (charge_l2 -> charge_dcfc), and
--                                               the depot's power limits. It records exactly what it changed and returns
--                                               a receipt the caller stamps on the run.
--   public.ottoq_site_buildout_restore(depot)   puts back exactly what apply changed, from that record.
--   public.ottoq_site_buildout_active           the record. A DEFERRED constraint trigger refuses to COMMIT while a row
--                                               is still in it, so a build-out cannot outlive the transaction that
--                                               applied it: if a caller forgets to restore, its whole transaction
--                                               rolls back, and the depot is as built again.
--   public.ottoq_site_buildout_census(depot)    fast chargers, L2, the power limits and the build-out applied (visible
--                                               only inside the transaction that applied it).
--   public.ottoq_throughput_scorecard(run)      CREATE OR REPLACE, scorecard_version '0567'. A day that ran on a
--                                               build-out is scored from its own record (payload.site_buildout): its
--                                               fast-charger count, and its converted spaces' sessions counted as fast
--                                               charges. 0566 read today's stall table, which after the restore says
--                                               L2 again, so re-scoring such a day later would have undercounted it.
--
--   Nothing calls apply yet. 0568's sweep arms are the first caller.
--
-- ══ §3 THE BUILD-OUTS AND WHERE THEIR NUMBERS COME FROM ════════════════════════════════════════════════════════════
--
--   dcfc10              the twin as built: 10 fast chargers, dcfc_max_concurrent_kw 1,800, service_max_kw 2,500.
--                       Applying it changes nothing and still leaves a receipt, so every test day names its build-out.
--   dcfc15              + NASH-L2-STALL-01..05 (CANOPY-02, west row, north end): 15 fast chargers, 2,700 kW, 3,431.5 kW.
--   dcfc20              + NASH-L2-STALL-01..10 (the west row and two east spaces): 20 fast chargers, 3,600 kW, 4,363 kW.
--   dcfc20_grid_today   the same 20 chargers on today's 1,800 kW and 2,500 kW: what OTTO-Q does with a site whose
--                       chargers outnumber its power.
--
--   Converted spaces keep their place, heading and stall code; CANOPY-02's west row faces CANOPY-01's east row, so the
--   fast-charge zone stays in one block. 20 L2 spaces remain for overnight dwell.
--
--   Power per added charger (sourced; read 2026-09-29):
--     DC: +180 kW per added charger, the twin's own ratio today (1,800 kW over 10 chargers). It matches ABB's shared
--         pair to 3%: "power cabinets can be connected to charge one vehicle at up to 350kW and 500A or two vehicles
--         simultaneously at up to 175kW and 375A" (175 kW per charger when both of a pair charge).
--     Service: +186.3 kW per added charger, one 175 kW power cabinet's AC draw at full load: 480 V x 231 A x sqrt(3) x
--         power factor 0.97. The spec sheet: "Voltage 480Y / 277 Vac", "Max Current Draw 231A", "Power Factor >= 0.97",
--         "Power - Max 175kW (one cabinet), 350kW (two cabinets)".
--     No credit is taken for the 19.2 kW of L2 load a converted space stops carrying.
--     Source: InCharge Energy, "ABB Terra High Power 175kW/350kW DC Fast Split System", spec sheet ver 1.4 (PDF dated
--     2025-02-20), https://inchargeus.com/wp-content/uploads/2025/02/InCharge_Specsheet_Terra-High-Power_v1.4.pdf
--
--   The robotic arm is the model every fast charger here already runs: twin.ottoq_sim_start_charge_session starts an
--   OTTO-CHARGE ARM mate cycle on any stall whose stall_type is 'dcfc' (unstow, approach, align, insert, latch; then
--   unlatch, extract, retract, from the robotic_arm_* dials), and its registration reads the space's fiducial and UWB
--   beacon. No engine function names a charger stall, zone, canopy or fiducial (checked by P1), so a converted space is
--   read as the fast charger it has become.
--
-- ══ §4 WHAT IT WRITES THAT OUTLIVES THE TRANSACTION ════════════════════════════════════════════════════════════════
--
--   The stall trigger signs a stall.state_changed event for each converted and each restored space (twenty per 20-charger
--   day). apply and restore say who is acting (actor ottoq_engine, actor_id site_buildout:<code>), and the caller files
--   them to no run, as 0421 files a fleet reset: harness setup, not the day's evidence. They are true: the space was a
--   fast charger for that day and an L2 space after it.
--
-- ══ §5 WHEN TO APPLY ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Any time. The new objects are called by nothing yet, and the scorecard is a read function no engine path calls;
--   forces_recert and forces_dial_restart are FALSE. V2's round trip on the live depot runs only when no run is live
--   (apply refuses under a live run by design) and rolls itself back; otherwise it says so and the same round trip is run
--   by hand afterwards.
--
-- ROLLBACK: DROP FUNCTION public.ottoq_site_buildout_census(uuid), public.ottoq_site_buildout_restore(uuid),
--   public.ottoq_site_buildout_apply(uuid, text); DROP TABLE public.ottoq_site_buildout_active; DROP FUNCTION
--   public.ottoq_site_buildout_must_not_commit(); DROP TABLE public.ottoq_site_buildouts; re-create 0566's
--   ottoq_throughput_scorecard body; DELETE FROM public.ottoq_cert_lineage WHERE name =
--   '0567_a_charger_build_out_lives_only_inside_a_test_day'.

BEGIN;

-- ── P1: what a conversion must change, and the proof that nothing else would still read the space as L2 ──
DO $premises$
DECLARE
  v_missing text;
  v_named   text;
BEGIN
  SELECT string_agg(t || '.' || c, ', ') INTO v_missing
    FROM (VALUES ('stalls', 'stall_type'), ('stalls', 'stall_code'), ('stalls', 'connector_max_kw'),
                 ('stalls', 'fiducial_marker_id'), ('stalls', 'uwb_beacon_id'), ('stalls', 'equipment_config'),
                 ('stalls', 'zone'), ('stalls', 'ocpp_charger_id'), ('stalls', 'depot_id'),
                 ('ottoq_ocpp_chargers', 'charger_id'), ('ottoq_ocpp_chargers', 'max_kw'),
                 ('ottoq_ocpp_chargers', 'vendor'), ('ottoq_ocpp_chargers', 'model'),
                 ('ottoq_service_point_capabilities', 'stall_id'), ('ottoq_service_point_capabilities', 'asset_class_code'),
                 ('ottoq_service_point_capabilities', 'operation_code'),
                 ('depots', 'dcfc_max_concurrent_kw'), ('depots', 'service_max_kw'),
                 ('ottoq_sim_runs', 'payload'), ('ottoq_cert_lineage', 'forces_dial_restart')) AS need(t, c)
   WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema = 'public' AND table_name = need.t AND column_name = need.c);
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION '0567 P1: a conversion reads or writes columns that do not exist: %', v_missing;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_throughput_scorecard(uuid)')
                    AND prosrc ~ $re$'scorecard_version', '0566'$re$) THEN
    RAISE EXCEPTION '0567 P1: ottoq_throughput_scorecard is not 0566''s body; this replaces that one only';
  END IF;
  -- The arm starts on stall_type, and the charge kind is the charger's rating: the two things a conversion sets.
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_start_charge_session'
                    AND p.prosrc ~ 'ottoq_arm_begin_cycle' AND p.prosrc ~ $re$stall_type = 'dcfc'$re$
                    AND p.prosrc ~ $re$max_kw > 50 THEN 'dcfc'$re$) THEN
    RAISE EXCEPTION '0567 P1: twin.ottoq_sim_start_charge_session no longer starts the arm on stall_type dcfc and reads the charge kind off the charger rating';
  END IF;
  -- Nothing may know a charger by its name, zone, canopy or fiducial, or a converted space would still read as L2.
  -- Comments are stripped first: ottoq_l2_optimize_assignments names NASH-L2-STALL-03 in a comment, which reads nothing.
  SELECT string_agg(n.nspname || '.' || p.proname, ', ' ORDER BY 1) INTO v_named
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public', 'ottoq', 'twin') AND p.proname NOT LIKE 'ottoq_fn_backup%'
     AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g')
         ~ '(DCFC-STALL|L2-STALL|dcfc_zone|l2_zone|CANOPY-0[123]|FID-D1|UWB-D1)';
  IF v_named IS NOT NULL THEN
    RAISE EXCEPTION '0567 P1: these functions name a charger space, zone, canopy or fiducial, so a converted space could still read as L2 to them: %', v_named;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.depots WHERE id = '11111111-1111-1111-1111-111111111111'
                    AND dcfc_max_concurrent_kw = 1800 AND service_max_kw = 2500) THEN
    RAISE EXCEPTION '0567 P1: the twin depot''s power limits are no longer 1,800 kW DC and 2,500 kW service; section 3''s arithmetic starts from them';
  END IF;
  IF (SELECT count(*) FROM public.stalls WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND stall_type = 'dcfc') <> 10
     OR (SELECT count(*) FROM public.stalls s WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type = 'l2'
            AND s.ocpp_charger_id IS NOT NULL AND s.canopy_code = 'CANOPY-02'
            AND s.stall_code IN ('NASH-L2-STALL-01','NASH-L2-STALL-02','NASH-L2-STALL-03','NASH-L2-STALL-04','NASH-L2-STALL-05',
                                 'NASH-L2-STALL-06','NASH-L2-STALL-07','NASH-L2-STALL-08','NASH-L2-STALL-09','NASH-L2-STALL-10')) <> 10 THEN
    RAISE EXCEPTION '0567 P1: the twin depot no longer has 10 fast chargers and the ten CANOPY-02 L2 chargers the build-outs name';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_operation_catalog WHERE pack_id = 'robotaxi' AND operation_code = 'charge_dcfc') THEN
    RAISE EXCEPTION '0567 P1: the robotaxi pack has no charge_dcfc operation for a converted space to carry';
  END IF;
END $premises$;

-- ── P2: not applied already ──
DO $fresh$
BEGIN
  IF to_regclass('public.ottoq_site_buildouts') IS NOT NULL
     OR to_regprocedure('public.ottoq_site_buildout_apply(uuid,text)') IS NOT NULL THEN
    RAISE EXCEPTION '0567 P2: the build-outs already exist; this file has already been applied';
  END IF;
END $fresh$;

-- ── 1. the build-outs, as data ──
CREATE TABLE public.ottoq_site_buildouts (
  buildout_code          text PRIMARY KEY CHECK (buildout_code ~ '^[a-z0-9_]+$'),
  depot_id               uuid NOT NULL REFERENCES public.depots(id),
  title                  text NOT NULL,
  dcfc_posts             integer NOT NULL CHECK (dcfc_posts > 0),
  convert_l2             text[] NOT NULL DEFAULT '{}',
  dcfc_max_concurrent_kw numeric NOT NULL CHECK (dcfc_max_concurrent_kw > 0),
  service_max_kw         numeric NOT NULL CHECK (service_max_kw > 0),
  basis                  jsonb NOT NULL,
  created_at             timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_site_buildouts ENABLE ROW LEVEL SECURITY;
CREATE POLICY ottoq_site_buildouts_read ON public.ottoq_site_buildouts FOR SELECT TO authenticated, service_role USING (true);
REVOKE ALL ON public.ottoq_site_buildouts FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.ottoq_site_buildouts TO authenticated, service_role;
COMMENT ON TABLE public.ottoq_site_buildouts IS
'0567. Robotic fast-charger build-outs of a depot, as data: the L2 spaces converted, the fast-charger count that results and the site power that goes with it, each with its source in basis. Applied only inside a test day''s own transaction (public.ottoq_site_buildout_apply); the depot as built is dcfc10.';

INSERT INTO public.ottoq_site_buildouts
  (buildout_code, depot_id, title, dcfc_posts, convert_l2, dcfc_max_concurrent_kw, service_max_kw, basis)
WITH src AS (
  SELECT jsonb_build_object(
    'title', 'ABB Terra High Power 175kW/350kW DC Fast Split System, spec sheet ver 1.4',
    'publisher', 'InCharge Energy',
    'url', 'https://inchargeus.com/wp-content/uploads/2025/02/InCharge_Specsheet_Terra-High-Power_v1.4.pdf',
    'dated', '2025-02-20 (PDF metadata)',
    'read', '2026-09-29',
    'quotes', jsonb_build_array(
      'power cabinets can be connected to charge one vehicle at up to 350kW and 500A or two vehicles simultaneously at up to 175kW and 375A',
      'Power - Max: 175kW (one cabinet), 350kW (two cabinets)',
      'Voltage: 480Y / 277 Vac; Max Current Draw: 231A; Power Factor: >= 0.97')) AS s
), common AS (
  SELECT jsonb_build_object(
    'dc_kw_per_added_charger', 180,
    'dc_basis', 'the twin''s own ratio today, dcfc_max_concurrent_kw 1,800 over 10 chargers; ABB''s shared pair gives 175 kW per charger when both of a pair charge',
    'service_kw_per_added_charger', 186.3,
    'service_basis', 'one 175 kW power cabinet at full load: 480 V x 231 A x sqrt(3) x power factor 0.97 = 186.3 kW',
    'l2_credit', 'none: the 19.2 kW of L2 load a converted space stops carrying is not credited back',
    'arm', 'the OTTO-CHARGE ARM model every dcfc stall runs (twin.ottoq_arm_begin_cycle, robotic_arm_* dials); a converted space gets a fiducial and a UWB beacon like the ten it joins',
    'source', (SELECT s FROM src)) AS c
)
SELECT v.code, '11111111-1111-1111-1111-111111111111'::uuid, v.title, v.posts, v.conv, v.dc_kw, v.svc_kw,
       (SELECT c FROM common) || v.extra
  FROM (VALUES
    ('dcfc10', '10 robotic fast chargers: the twin depot as built', 10, '{}'::text[], 1800::numeric, 2500::numeric,
     jsonb_build_object('note', 'no conversion; applying it leaves a receipt, so every test day names its build-out')),
    ('dcfc15', '15 robotic fast chargers: five CANOPY-02 L2 spaces converted, the grid grown with them', 15,
     ARRAY['NASH-L2-STALL-01','NASH-L2-STALL-02','NASH-L2-STALL-03','NASH-L2-STALL-04','NASH-L2-STALL-05'],
     2700::numeric, 3431.5::numeric,
     jsonb_build_object('note', '1,800 + 5 x 180 kW DC; 2,500 + 5 x 186.3 kW service')),
    ('dcfc20', '20 robotic fast chargers: CANOPY-02''s west row and two east spaces converted, the grid grown with them', 20,
     ARRAY['NASH-L2-STALL-01','NASH-L2-STALL-02','NASH-L2-STALL-03','NASH-L2-STALL-04','NASH-L2-STALL-05',
           'NASH-L2-STALL-06','NASH-L2-STALL-07','NASH-L2-STALL-08','NASH-L2-STALL-09','NASH-L2-STALL-10'],
     3600::numeric, 4363::numeric,
     jsonb_build_object('note', '1,800 + 10 x 180 kW DC; 2,500 + 10 x 186.3 kW service')),
    ('dcfc20_grid_today', '20 robotic fast chargers on today''s grid', 20,
     ARRAY['NASH-L2-STALL-01','NASH-L2-STALL-02','NASH-L2-STALL-03','NASH-L2-STALL-04','NASH-L2-STALL-05',
           'NASH-L2-STALL-06','NASH-L2-STALL-07','NASH-L2-STALL-08','NASH-L2-STALL-09','NASH-L2-STALL-10'],
     1800::numeric, 2500::numeric,
     jsonb_build_object('note', 'the dcfc20 chargers with the power limits unchanged: chargers outnumber power'))
  ) AS v(code, title, posts, conv, dc_kw, svc_kw, extra);

-- ── 2. the record, and the guard that it never commits ──
CREATE TABLE public.ottoq_site_buildout_active (
  depot_id      uuid PRIMARY KEY REFERENCES public.depots(id),
  buildout_code text NOT NULL REFERENCES public.ottoq_site_buildouts(buildout_code),
  applied_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
  backend_pid   integer NOT NULL DEFAULT pg_backend_pid(),
  pre_image     jsonb NOT NULL
);
ALTER TABLE public.ottoq_site_buildout_active ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ottoq_site_buildout_active FROM PUBLIC, anon, authenticated, service_role;
COMMENT ON TABLE public.ottoq_site_buildout_active IS
'0567. The build-out applied to a depot inside the current transaction, with exactly what it changed (pre_image). Always empty outside that transaction: a deferred constraint trigger refuses to COMMIT while a row is here.';

-- SECURITY DEFINER: the check runs at COMMIT as whoever commits, and must see the record whoever that is.
CREATE FUNCTION public.ottoq_site_buildout_must_not_commit()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_site_buildout_active a WHERE a.depot_id = NEW.depot_id) THEN
    RAISE EXCEPTION 'build-out % is still applied to depot % at commit. A build-out lives only inside the transaction that applied it: call public.ottoq_site_buildout_restore first. This transaction rolls back, and the depot is as built.',
      NEW.buildout_code, NEW.depot_id USING ERRCODE = 'P0001';
  END IF;
  RETURN NULL;
END $fn$;
REVOKE ALL ON FUNCTION public.ottoq_site_buildout_must_not_commit() FROM PUBLIC, anon, authenticated, service_role;

CREATE CONSTRAINT TRIGGER ottoq_site_buildout_never_commits
  AFTER INSERT ON public.ottoq_site_buildout_active
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_site_buildout_must_not_commit();

-- ── 3. apply ──
CREATE FUNCTION public.ottoq_site_buildout_apply(p_depot uuid, p_code text)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  b        public.ottoq_site_buildouts%ROWTYPE;
  v_ids    uuid[];
  v_found  integer;
  v_bad    text;
  v_dcfc   integer;
  v_pre    jsonb;
  v_actor_type text := current_setting('ottoq.actor_type', true);
  v_actor_id   text := current_setting('ottoq.actor_id', true);
BEGIN
  SELECT * INTO b FROM public.ottoq_site_buildouts WHERE buildout_code = p_code;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'site_buildout_apply: no build-out %', p_code USING ERRCODE = 'P0002';
  END IF;
  IF b.depot_id IS DISTINCT FROM p_depot THEN
    RAISE EXCEPTION 'site_buildout_apply: build-out % belongs to depot %, not %', p_code, b.depot_id, p_depot
      USING ERRCODE = 'P0001';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_site_buildout_active WHERE depot_id = p_depot) THEN
    RAISE EXCEPTION 'site_buildout_apply: build-out % is already applied to depot % in this transaction; restore it first',
      (SELECT buildout_code FROM public.ottoq_site_buildout_active WHERE depot_id = p_depot), p_depot USING ERRCODE = 'P0001';
  END IF;
  -- Only between runs: a run in progress was dealt the depot as it was.
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE depot_id = p_depot AND status IN ('running', 'paused')) THEN
    RAISE EXCEPTION 'site_buildout_apply: a run is live at depot %; a build-out is applied only before a test day starts', p_depot
      USING ERRCODE = '55006';
  END IF;

  SELECT array_agg(s.id ORDER BY u.ord), count(*) INTO v_ids, v_found
    FROM unnest(b.convert_l2) WITH ORDINALITY AS u(code, ord)
    JOIN public.stalls s ON s.stall_code = u.code AND s.depot_id = p_depot
                        AND s.stall_type = 'l2' AND s.ocpp_charger_id IS NOT NULL;
  v_ids := COALESCE(v_ids, '{}'::uuid[]);
  IF COALESCE(v_found, 0) <> cardinality(b.convert_l2) THEN
    SELECT string_agg(u.code, ', ') INTO v_bad
      FROM unnest(b.convert_l2) AS u(code)
     WHERE NOT EXISTS (SELECT 1 FROM public.stalls s WHERE s.stall_code = u.code AND s.depot_id = p_depot
                          AND s.stall_type = 'l2' AND s.ocpp_charger_id IS NOT NULL);
    RAISE EXCEPTION 'site_buildout_apply: % names spaces that are not L2 chargers at depot %: %', p_code, p_depot, v_bad
      USING ERRCODE = 'P0001';
  END IF;
  SELECT count(*) INTO v_dcfc FROM public.stalls WHERE depot_id = p_depot AND stall_type = 'dcfc';
  IF v_dcfc + cardinality(b.convert_l2) <> b.dcfc_posts THEN
    RAISE EXCEPTION 'site_buildout_apply: % declares % fast chargers, but the depot has % and it converts %', p_code,
      b.dcfc_posts, v_dcfc, cardinality(b.convert_l2) USING ERRCODE = 'P0001';
  END IF;

  -- Exactly the columns this changes, so the restore puts back exactly what it found.
  v_pre := jsonb_build_object(
    'stalls', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                 'id', s.id, 'stall_type', s.stall_type::text, 'connector_max_kw', s.connector_max_kw,
                 'fiducial_marker_id', s.fiducial_marker_id, 'uwb_beacon_id', s.uwb_beacon_id,
                 'equipment_config', s.equipment_config, 'zone', s.zone) ORDER BY s.id)
               FROM public.stalls s WHERE s.id = ANY (v_ids)), '[]'::jsonb),
    'chargers', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                 'charger_id', c.charger_id, 'max_kw', c.max_kw, 'vendor', c.vendor, 'model', c.model) ORDER BY c.charger_id)
               FROM public.ottoq_ocpp_chargers c JOIN public.stalls s ON s.ocpp_charger_id = c.charger_id
              WHERE s.id = ANY (v_ids)), '[]'::jsonb),
    'capabilities', COALESCE((SELECT jsonb_agg(jsonb_build_object('stall_id', k.stall_id, 'asset_class_code', k.asset_class_code)
                                               ORDER BY k.stall_id, k.asset_class_code)
               FROM public.ottoq_service_point_capabilities k
              WHERE k.stall_id = ANY (v_ids) AND k.operation_code = 'charge_l2'), '[]'::jsonb),
    'depot', (SELECT jsonb_build_object('dcfc_max_concurrent_kw', d.dcfc_max_concurrent_kw, 'service_max_kw', d.service_max_kw)
                FROM public.depots d WHERE d.id = p_depot));

  INSERT INTO public.ottoq_site_buildout_active (depot_id, buildout_code, pre_image) VALUES (p_depot, p_code, v_pre);

  -- Say who is acting: the stall trigger signs an event for each converted space (0423(C)'s doctrine).
  PERFORM set_config('ottoq.actor_type', 'ottoq_engine', true);
  PERFORM set_config('ottoq.actor_id', 'site_buildout:' || p_code, true);

  UPDATE public.stalls s
     SET stall_type         = 'dcfc',
         connector_max_kw   = 350.0,
         fiducial_marker_id = 'FID-BO-' || regexp_replace(s.stall_code, '^[A-Z]+-', '') || '-A',
         uwb_beacon_id      = 'UWB-BO-' || regexp_replace(s.stall_code, '^[A-Z]+-', ''),
         equipment_config   = COALESCE(s.equipment_config, '{}'::jsonb)
                              || jsonb_build_object('charger_kw', 350, 'robotic_arm', true, 'buildout', p_code),
         zone               = 'dcfc_zone'
   WHERE s.id = ANY (v_ids);
  UPDATE public.ottoq_ocpp_chargers c
     SET max_kw = 350, vendor = 'ABB', model = 'Terra HP 350'
    FROM public.stalls s
   WHERE s.ocpp_charger_id = c.charger_id AND s.id = ANY (v_ids);
  UPDATE public.ottoq_service_point_capabilities k
     SET operation_code = 'charge_dcfc'
   WHERE k.stall_id = ANY (v_ids) AND k.operation_code = 'charge_l2';
  UPDATE public.depots d
     SET dcfc_max_concurrent_kw = b.dcfc_max_concurrent_kw, service_max_kw = b.service_max_kw
   WHERE d.id = p_depot;

  PERFORM set_config('ottoq.actor_type', COALESCE(v_actor_type, ''), true);
  PERFORM set_config('ottoq.actor_id', COALESCE(v_actor_id, ''), true);

  RETURN jsonb_build_object(
    'buildout_code', p_code, 'depot_id', p_depot, 'title', b.title,
    'dcfc_posts', b.dcfc_posts,
    'converted', COALESCE((SELECT jsonb_agg(jsonb_build_object('stall_id', s.id, 'stall_code', s.stall_code) ORDER BY u.ord)
                             FROM unnest(v_ids) WITH ORDINALITY AS u(id, ord) JOIN public.stalls s ON s.id = u.id), '[]'::jsonb),
    'converted_stall_ids', to_jsonb(v_ids),
    'dcfc_max_concurrent_kw', b.dcfc_max_concurrent_kw, 'service_max_kw', b.service_max_kw,
    'applied_at', clock_timestamp());
END $fn$;
COMMENT ON FUNCTION public.ottoq_site_buildout_apply(uuid, text) IS
'0567. Converts the build-out''s L2 spaces to 350 kW robotic fast chargers and sets the depot''s power limits, recording exactly what it changed in ottoq_site_buildout_active. Refuses under a live run. The transaction cannot commit until public.ottoq_site_buildout_restore puts the depot back.';

-- ── 4. restore ──
CREATE FUNCTION public.ottoq_site_buildout_restore(p_depot uuid)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  a public.ottoq_site_buildout_active%ROWTYPE;
  v_stalls int; v_chargers int; v_caps int;
  v_actor_type text := current_setting('ottoq.actor_type', true);
  v_actor_id   text := current_setting('ottoq.actor_id', true);
BEGIN
  SELECT * INTO a FROM public.ottoq_site_buildout_active WHERE depot_id = p_depot FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('restored', false, 'depot_id', p_depot, 'why', 'no build-out is applied');
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE depot_id = p_depot AND status IN ('running', 'paused')) THEN
    RAISE EXCEPTION 'site_buildout_restore: a run is live at depot %; restore after its teardown', p_depot USING ERRCODE = '55006';
  END IF;

  PERFORM set_config('ottoq.actor_type', 'ottoq_engine', true);
  PERFORM set_config('ottoq.actor_id', 'site_buildout:' || a.buildout_code, true);

  UPDATE public.stalls s
     SET stall_type         = (x->>'stall_type')::public.stall_type,
         connector_max_kw   = (x->>'connector_max_kw')::numeric,
         fiducial_marker_id = x->>'fiducial_marker_id',
         uwb_beacon_id      = x->>'uwb_beacon_id',
         equipment_config   = CASE WHEN jsonb_typeof(x->'equipment_config') = 'null' THEN NULL ELSE x->'equipment_config' END,
         zone               = x->>'zone'
    FROM jsonb_array_elements(a.pre_image->'stalls') AS x
   WHERE s.id = (x->>'id')::uuid;
  GET DIAGNOSTICS v_stalls = ROW_COUNT;
  UPDATE public.ottoq_ocpp_chargers c
     SET max_kw = (x->>'max_kw')::numeric, vendor = x->>'vendor', model = x->>'model'
    FROM jsonb_array_elements(a.pre_image->'chargers') AS x
   WHERE c.charger_id = (x->>'charger_id')::uuid;
  GET DIAGNOSTICS v_chargers = ROW_COUNT;
  UPDATE public.ottoq_service_point_capabilities k
     SET operation_code = 'charge_l2'
    FROM jsonb_array_elements(a.pre_image->'capabilities') AS x
   WHERE k.stall_id = (x->>'stall_id')::uuid AND k.asset_class_code = x->>'asset_class_code'
     AND k.operation_code = 'charge_dcfc';
  GET DIAGNOSTICS v_caps = ROW_COUNT;
  UPDATE public.depots d
     SET dcfc_max_concurrent_kw = (a.pre_image->'depot'->>'dcfc_max_concurrent_kw')::numeric,
         service_max_kw         = (a.pre_image->'depot'->>'service_max_kw')::numeric
   WHERE d.id = p_depot;

  IF v_stalls <> jsonb_array_length(a.pre_image->'stalls')
     OR v_chargers <> jsonb_array_length(a.pre_image->'chargers')
     OR v_caps <> jsonb_array_length(a.pre_image->'capabilities') THEN
    RAISE EXCEPTION 'site_buildout_restore: % put back % of % spaces, % of % chargers and % of % capabilities; the depot is not as built',
      a.buildout_code, v_stalls, jsonb_array_length(a.pre_image->'stalls'), v_chargers,
      jsonb_array_length(a.pre_image->'chargers'), v_caps, jsonb_array_length(a.pre_image->'capabilities')
      USING ERRCODE = 'P0001';
  END IF;

  DELETE FROM public.ottoq_site_buildout_active WHERE depot_id = p_depot;
  PERFORM set_config('ottoq.actor_type', COALESCE(v_actor_type, ''), true);
  PERFORM set_config('ottoq.actor_id', COALESCE(v_actor_id, ''), true);

  RETURN jsonb_build_object('restored', true, 'buildout_code', a.buildout_code, 'depot_id', p_depot,
                            'spaces', v_stalls, 'chargers', v_chargers, 'capabilities', v_caps);
END $fn$;
COMMENT ON FUNCTION public.ottoq_site_buildout_restore(uuid) IS
'0567. Puts back exactly what public.ottoq_site_buildout_apply changed, from its record, and clears the record so the transaction may commit. A no-op receipt when nothing is applied.';

-- ── 5. the census ──
CREATE FUNCTION public.ottoq_site_buildout_census(p_depot uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
  SELECT jsonb_build_object(
    'depot_id', p_depot,
    'dcfc', (SELECT count(*) FROM public.stalls WHERE depot_id = p_depot AND stall_type = 'dcfc'),
    'l2',   (SELECT count(*) FROM public.stalls WHERE depot_id = p_depot AND stall_type = 'l2'),
    'dcfc_max_concurrent_kw', (SELECT dcfc_max_concurrent_kw FROM public.depots WHERE id = p_depot),
    'service_max_kw',         (SELECT service_max_kw FROM public.depots WHERE id = p_depot),
    'applied',                (SELECT buildout_code FROM public.ottoq_site_buildout_active WHERE depot_id = p_depot));
$fn$;
COMMENT ON FUNCTION public.ottoq_site_buildout_census(uuid) IS
'0567. Fast chargers, L2 spaces and power limits at a depot, and the build-out applied (visible only inside the transaction that applied it; NULL everywhere else, which is the depot as built).';

-- ── 6. the scorecard reads a day's own census ──
CREATE OR REPLACE FUNCTION public.ottoq_throughput_scorecard(p_run uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = twin, ottoq, public, extensions
AS $fn$
DECLARE
  v_five   jsonb;
  v_wait   jsonb;
  v_svc    jsonb;
  v_errors jsonb := '{}'::jsonb;
  v_bo     jsonb;
  v_conv   uuid[];
  v_out    jsonb;
BEGIN
  -- The KPI functions this reuses are read as they are. One that fails on a run (ottoq_kpi_five raises "field name
  -- must not be null" on the August production run e8a0ba01) is reported under kpi_errors, never allowed to take the
  -- throughput numbers down with it.
  BEGIN v_five := public.ottoq_kpi_five(p_run);
  EXCEPTION WHEN OTHERS THEN v_errors := v_errors || jsonb_build_object('kpi_five', SQLERRM); END;
  BEGIN v_wait := public.ottoq_kpi_charge_wait(p_run);
  EXCEPTION WHEN OTHERS THEN v_errors := v_errors || jsonb_build_object('charge_wait', SQLERRM); END;
  BEGIN v_svc := public.ottoq_kpi_service_completion(p_run);
  EXCEPTION WHEN OTHERS THEN v_errors := v_errors || jsonb_build_object('service_completion', SQLERRM); END;

  -- 0567: a day that ran on a build-out carries its own census (payload.site_buildout, stamped by the caller that
  -- applied it). After the restore the stall table says L2 again, so a later re-score must read the day's record.
  SELECT sr.payload->'site_buildout' INTO v_bo FROM public.ottoq_sim_runs sr WHERE sr.sim_run_id = p_run;
  IF jsonb_typeof(v_bo) = 'object' THEN
    SELECT COALESCE(array_agg(e::uuid), '{}'::uuid[]) INTO v_conv
      FROM jsonb_array_elements_text(COALESCE(v_bo->'converted_stall_ids', '[]'::jsonb)) AS e;
  ELSE
    v_bo := NULL;
    v_conv := '{}'::uuid[];
  END IF;

  WITH r AS (
    SELECT sr.sim_run_id, sr.depot_id, sr.scenario_code, sr.random_seed, sr.tick_count, sr.policy, sr.status,
           sr.sim_clock_start, sr.sim_clock_current,
           round((sr.tick_interval_seconds * COALESCE(sr.time_scale, 1) / 60.0)::numeric, 2) AS step_min_nominal,
           round((extract(epoch FROM (sr.sim_clock_current - sr.sim_clock_start)) / 60.0
                  / NULLIF(sr.tick_count, 0))::numeric, 2) AS step_min,
           GREATEST(extract(epoch FROM (sr.sim_clock_current - sr.sim_clock_start)) / 3600.0, 0)::numeric AS horizon_h
      FROM public.ottoq_sim_runs sr
     WHERE sr.sim_run_id = p_run
  ), o AS (
    SELECT * FROM public.ottoq_visit_outcomes(p_run)
  ), s AS (
    SELECT * FROM o WHERE departed_at IS NOT NULL
  ), grp AS (
    SELECT g.tier_group,
           count(*)                                                       AS visits,
           count(*) FILTER (WHERE g.departed_at IS NOT NULL)              AS served,
           count(*) FILTER (WHERE g.in_depot_at_horizon)                  AS in_depot,
           percentile_cont(0.5)  WITHIN GROUP (ORDER BY g.door_min)       AS p50,
           percentile_cont(0.95) WITHIN GROUP (ORDER BY g.door_min)       AS p95,
           count(*) FILTER (WHERE g.due_at IS NOT NULL AND g.departed_at IS NOT NULL) AS due_served,
           count(*) FILTER (WHERE g.on_time)                              AS on_time
      FROM o g
     GROUP BY g.tier_group
  ), peak AS (
    SELECT COALESCE(max(n), 0) AS n
      FROM (SELECT (SELECT count(*) FROM s s2
                     WHERE s2.departed_at >= s1.departed_at
                       AND s2.departed_at <  s1.departed_at + interval '60 minutes') AS n
              FROM s s1) z
  ), sess AS (
    SELECT CASE WHEN x.stall_id = ANY (v_conv) THEN 'dcfc' ELSE st.stall_type::text END AS stall_type,
           x.stall_id, x.started_at, x.ended_at, x.energy_delivered_kwh, x.avg_power_kw
      FROM public.ocpp_sessions x
      JOIN public.stalls st ON st.id = x.stall_id
     WHERE x.sim_run_id = p_run AND x.started_at IS NOT NULL
  ), dc AS (
    SELECT count(*)                                                                          AS sessions,
           count(DISTINCT stall_id)                                                          AS chargers_used,
           sum(extract(epoch FROM (ended_at - started_at)) / 3600.0) FILTER (WHERE ended_at IS NOT NULL) AS hours,
           sum(energy_delivered_kwh)                                                         AS kwh,
           avg(avg_power_kw)                                                                 AS mean_kw,
           avg(extract(epoch FROM (ended_at - started_at)) / 60.0) FILTER (WHERE ended_at IS NOT NULL) AS mean_min
      FROM sess
     WHERE stall_type = 'dcfc'
  ), fleet AS (
    SELECT COALESCE((v_bo->>'dcfc_posts')::bigint,
                    (SELECT count(*) FROM public.stalls st, r WHERE st.depot_id = r.depot_id AND st.stall_type = 'dcfc'))
             AS dcfc_at_depot
  ), ar AS (
    SELECT a.engine_hash, a.config_hash FROM public.ottoq_run_archives a WHERE a.sim_run_id = p_run LIMIT 1
  )
  SELECT jsonb_build_object(
    'sim_run_id', r.sim_run_id,
    'scorecard_version', '0567',
    'run', jsonb_build_object(
       'scenario', r.scenario_code, 'seed', r.random_seed, 'ticks', r.tick_count, 'policy', r.policy,
       'status', r.status, 'depot_id', r.depot_id, 'sim_start', r.sim_clock_start, 'horizon', r.sim_clock_current,
       'horizon_h', round(r.horizon_h, 2),
       'engine_hash', (SELECT engine_hash FROM ar), 'config_hash', (SELECT config_hash FROM ar),
       'site_buildout', v_bo->>'buildout_code'),
    'step_min', r.step_min,
    'step_min_nominal', r.step_min_nominal,
    'throughput', jsonb_build_object(
       'visits',              (SELECT count(*) FROM o),
       'visits_served',       (SELECT count(*) FROM s),
       'vehicles_served',     (SELECT count(DISTINCT vehicle_id) FROM s),
       'in_depot_at_horizon', (SELECT count(*) FROM o WHERE in_depot_at_horizon),
       'served_per_day',      CASE WHEN r.horizon_h >= 6
                                   THEN round((SELECT count(*) FROM s) * 24.0 / r.horizon_h, 1) END,
       'peak_hour_served',    (SELECT n FROM peak)),
    'by_tier_group', COALESCE((SELECT jsonb_object_agg(tier_group, jsonb_build_object(
       'visits', visits, 'served', served, 'in_depot', in_depot,
       'door_p50_min', round(p50::numeric, 0), 'door_p95_min', round(p95::numeric, 0),
       'due_served', due_served, 'on_time', on_time,
       'on_time_pct', CASE WHEN due_served > 0 THEN round(100.0 * on_time / due_served, 1) END)) FROM grp), '{}'::jsonb),
    'timeliness', jsonb_build_object(
       'door_p50_min', (SELECT round((percentile_cont(0.5)  WITHIN GROUP (ORDER BY door_min))::numeric, 0) FROM s),
       'door_p95_min', (SELECT round((percentile_cont(0.95) WITHIN GROUP (ORDER BY door_min))::numeric, 0) FROM s),
       'due_served',   (SELECT count(*) FROM s WHERE due_at IS NOT NULL),
       'on_time',      (SELECT count(*) FROM s WHERE on_time),
       'on_time_pct',  (SELECT CASE WHEN count(*) FILTER (WHERE due_at IS NOT NULL) > 0
                                    THEN round(100.0 * count(*) FILTER (WHERE on_time)
                                               / count(*) FILTER (WHERE due_at IS NOT NULL), 1) END FROM s),
       'late_p50_min', (SELECT round((percentile_cont(0.5)  WITHIN GROUP (ORDER BY late_min))::numeric, 0) FROM s
                         WHERE late_min IS NOT NULL),
       'late_p95_min', (SELECT round((percentile_cont(0.95) WITHIN GROUP (ORDER BY late_min))::numeric, 0) FROM s
                         WHERE late_min IS NOT NULL)),
    'rule9', jsonb_build_object(
       'departures',                  (SELECT count(*) FROM s),
       'left_below_target',           (SELECT count(*) FROM s
                                        WHERE soc_out IS NOT NULL AND soc_out < COALESCE(target_soc, 100) - 1),
       'left_with_needed_work_open',  (SELECT count(*) FROM s WHERE needed_open_at_departure > 0),
       'charge_unknown_at_departure', (SELECT count(*) FROM s WHERE soc_out IS NULL),
       'atoms_cleared_by_triage',     (SELECT COALESCE(sum(cleared_by_triage), 0) FROM o),
       'done_atoms_without_a_time',   (SELECT COALESCE(sum(done_without_time), 0) FROM o)),
    'fast_chargers', jsonb_build_object(
       'at_depot',                  (SELECT dcfc_at_depot FROM fleet),
       'used',                      dc.chargers_used,
       'sessions',                  dc.sessions,
       'turns_per_charger_per_day', CASE WHEN r.horizon_h >= 6 AND (SELECT dcfc_at_depot FROM fleet) > 0
                                         THEN round(dc.sessions * 24.0 / r.horizon_h
                                                    / (SELECT dcfc_at_depot FROM fleet), 2) END,
       'busy_pct',                  CASE WHEN r.horizon_h > 0 AND (SELECT dcfc_at_depot FROM fleet) > 0
                                         THEN round(100.0 * COALESCE(dc.hours, 0)
                                                    / (r.horizon_h * (SELECT dcfc_at_depot FROM fleet)), 1) END,
       'mean_session_min',          round(dc.mean_min::numeric, 1),
       'mean_kw',                   round(dc.mean_kw::numeric, 1),
       'kwh_per_session_hour',      round((dc.kwh / NULLIF(dc.hours, 0))::numeric, 1)),
    'l2_sessions', (SELECT count(*) FROM sess WHERE stall_type = 'l2'),
    'charge_wait', v_wait,
    'service_completion', CASE WHEN v_svc IS NOT NULL THEN
                            jsonb_build_object('must_do', v_svc->'must_do', 'must_do_done', v_svc->'must_do_done',
                                               'pct', v_svc->'service_completion_pct') END,
    'kpi', CASE WHEN v_five IS NOT NULL THEN
             jsonb_build_object('peak_site_kw', v_five->'peak_site_kw',
                                'peak_site_kw_demand', v_five->'peak_site_kw_demand',
                                'touch_events_per_turn', v_five->'touch_events_per_turn',
                                'p95_time_to_service_min', v_five->'p95_time_to_service_min') END,
    'kpi_errors', v_errors,
    'comparability', jsonb_build_object(
       'all_policies', 'visits, dispatches and charge sessions: every arm''s vehicles produce them, because the policy only proposes and the kernel disposes (0261)',
       'rule', 'db/checks/0149: a comparative metric read from an artifact only one arm produces measures which arm it is'),
    'caveats', (SELECT jsonb_agg(u.c ORDER BY u.o) FROM unnest(ARRAY[
       format('Times are quantized to the run''s %s-minute steps. A visit needs about three steps (arrive, plug, close) before it can leave, so coarse steps add time to every visit.', r.step_min),
       CASE WHEN r.horizon_h < 6 THEN format('The run covers %s hours, under 6, so per-day rates are not extrapolated from it.', round(r.horizon_h, 2)) END,
       CASE WHEN v_bo IS NOT NULL THEN format('This day ran on build-out %s (%s robotic fast chargers, %s kW DC, %s kW service). Its charger count and its converted spaces come from the run''s own record, not from today''s stall table.',
                                              v_bo->>'buildout_code', v_bo->>'dcfc_posts', v_bo->>'dcfc_max_concurrent_kw', v_bo->>'service_max_kw') END,
       'tier_group groups the generator''s visit archetypes. It is not yet a commercial tier.',
       'A visit still in the depot at the horizon is counted in in_depot_at_horizon and kept out of every time percentile.'])
       WITH ORDINALITY AS u(c, o) WHERE u.c IS NOT NULL))
    INTO v_out
  FROM r, dc;
  RETURN v_out;
END $fn$;

-- ── grants: apply and restore rewrite the depot, so service_role only; the census reads like the scorecard ──
REVOKE ALL ON FUNCTION public.ottoq_site_buildout_apply(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_site_buildout_restore(uuid)     FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_site_buildout_census(uuid)      FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ottoq_site_buildout_apply(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_site_buildout_restore(uuid)     TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_site_buildout_census(uuid)      TO authenticated, service_role;

-- ── V1: the objects are what they claim to be ──
DO $verify_catalog$
DECLARE
  v_bad text;
BEGIN
  IF (SELECT count(*) FROM public.ottoq_site_buildouts) <> 4 THEN
    RAISE EXCEPTION '0567 V1: expected 4 build-outs';
  END IF;
  -- each build-out's count adds up against the depot as built
  SELECT string_agg(b.buildout_code, ', ') INTO v_bad
    FROM public.ottoq_site_buildouts b
   WHERE b.dcfc_posts <> (SELECT count(*) FROM public.stalls s WHERE s.depot_id = b.depot_id AND s.stall_type = 'dcfc')
                         + cardinality(b.convert_l2)
      OR (SELECT count(*) FROM unnest(b.convert_l2) u(code)
           JOIN public.stalls s ON s.stall_code = u.code AND s.depot_id = b.depot_id AND s.stall_type = 'l2')
         <> cardinality(b.convert_l2);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0567 V1: these build-outs do not add up against the depot as built: %', v_bad;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'ottoq_site_buildout_never_commits' AND tgdeferrable AND tginitdeferred) THEN
    RAISE EXCEPTION '0567 V1: the commit guard is not a deferred constraint trigger';
  END IF;
  IF has_function_privilege('anon', 'public.ottoq_site_buildout_apply(uuid,text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.ottoq_site_buildout_apply(uuid,text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.ottoq_site_buildout_restore(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.ottoq_site_buildout_apply(uuid,text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.ottoq_site_buildout_census(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '0567 V1: grants are not service_role-only for apply/restore and readable for the census';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_site_buildout_active) THEN
    RAISE EXCEPTION '0567 V1: a build-out record exists outside its transaction';
  END IF;
END $verify_catalog$;

-- ── V2: a round trip on the live depot puts back exactly what it found (only between runs; rolled back either way) ──
DO $verify_round_trip$
DECLARE
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_before text; v_after text; v_census jsonb; v_receipt jsonb; v_l2_before int;
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE depot_id = c_depot AND status IN ('running', 'paused')) THEN
    RAISE NOTICE '0567 V2: a run is live at the twin depot, so the live round trip is skipped (apply refuses under a live run by design). Run it by hand between runs.';
    RETURN;
  END IF;
  BEGIN
    SELECT md5(string_agg(t, E'\n' ORDER BY t)) INTO v_before FROM (
      SELECT concat_ws('|', s.id, s.stall_type, s.connector_max_kw, s.fiducial_marker_id, s.uwb_beacon_id, s.equipment_config, s.zone) t
        FROM public.stalls s WHERE s.depot_id = c_depot
      UNION ALL SELECT concat_ws('|', c.charger_id, c.max_kw, c.vendor, c.model)
        FROM public.ottoq_ocpp_chargers c WHERE c.depot_id = c_depot
      UNION ALL SELECT concat_ws('|', k.stall_id, k.asset_class_code, k.operation_code)
        FROM public.ottoq_service_point_capabilities k JOIN public.stalls s ON s.id = k.stall_id WHERE s.depot_id = c_depot
      UNION ALL SELECT concat_ws('|', d.dcfc_max_concurrent_kw, d.service_max_kw) FROM public.depots d WHERE d.id = c_depot) z;

    v_l2_before := (public.ottoq_site_buildout_census(c_depot)->>'l2')::int;
    v_receipt := public.ottoq_site_buildout_apply(c_depot, 'dcfc20');
    v_census := public.ottoq_site_buildout_census(c_depot);
    IF (v_census->>'dcfc')::int <> 20 OR (v_census->>'l2')::int <> v_l2_before - 10
       OR (v_census->>'dcfc_max_concurrent_kw')::numeric <> 3600
       OR (v_census->>'service_max_kw')::numeric <> 4363 OR v_census->>'applied' <> 'dcfc20'
       OR jsonb_array_length(v_receipt->'converted_stall_ids') <> 10 THEN
      RAISE EXCEPTION '0567 V2: dcfc20 applied reads %', v_census;
    END IF;
    IF EXISTS (SELECT 1 FROM public.stalls s WHERE s.id IN (SELECT (jsonb_array_elements_text(v_receipt->'converted_stall_ids'))::uuid)
                  AND (s.fiducial_marker_id IS NULL OR s.uwb_beacon_id IS NULL OR s.connector_max_kw <> 350)) THEN
      RAISE EXCEPTION '0567 V2: a converted space lacks the fiducial, beacon or rating the arm and the charge kind read';
    END IF;
    IF EXISTS (SELECT 1 FROM public.ottoq_service_point_capabilities k
                WHERE k.stall_id IN (SELECT (jsonb_array_elements_text(v_receipt->'converted_stall_ids'))::uuid)
                  AND k.operation_code = 'charge_l2') THEN
      RAISE EXCEPTION '0567 V2: a converted space still carries charge_l2';
    END IF;
    PERFORM public.ottoq_site_buildout_restore(c_depot);

    SELECT md5(string_agg(t, E'\n' ORDER BY t)) INTO v_after FROM (
      SELECT concat_ws('|', s.id, s.stall_type, s.connector_max_kw, s.fiducial_marker_id, s.uwb_beacon_id, s.equipment_config, s.zone) t
        FROM public.stalls s WHERE s.depot_id = c_depot
      UNION ALL SELECT concat_ws('|', c.charger_id, c.max_kw, c.vendor, c.model)
        FROM public.ottoq_ocpp_chargers c WHERE c.depot_id = c_depot
      UNION ALL SELECT concat_ws('|', k.stall_id, k.asset_class_code, k.operation_code)
        FROM public.ottoq_service_point_capabilities k JOIN public.stalls s ON s.id = k.stall_id WHERE s.depot_id = c_depot
      UNION ALL SELECT concat_ws('|', d.dcfc_max_concurrent_kw, d.service_max_kw) FROM public.depots d WHERE d.id = c_depot) z;
    IF v_after IS DISTINCT FROM v_before THEN
      RAISE EXCEPTION '0567 V2: the restore did not put the depot back as built (% -> %)', v_before, v_after;
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = '0567_V2_ROLLBACK';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> '0567_V2_ROLLBACK' THEN RAISE; END IF;
  END;
  RAISE NOTICE '0567 V2: dcfc20 applied and restored on the live twin depot; the depot reads as built, and the round trip was rolled back';
END $verify_round_trip$;

-- ── V3: the scorecard is 0566's for every day without a build-out ──
DO $verify_scorecard$
DECLARE
  v_n int := 0; v_bad int := 0; r record; v_new jsonb;
BEGIN
  FOR r IN SELECT l.sim_run_id, l.scorecard
             FROM public.ottoq_throughput_scores_latest l
            WHERE l.scorecard->>'scorecard_version' = '0566'
              AND EXISTS (SELECT 1 FROM public.ottoq_sim_runs sr        -- a purged run has nothing left to re-read,
                           WHERE sr.sim_run_id = l.sim_run_id               -- and a build-out day is the one 0567 changes
                             AND sr.status NOT IN ('running', 'paused', 'initializing')
                             AND NOT (COALESCE(sr.payload, '{}'::jsonb) ? 'site_buildout'))
            ORDER BY l.sim_run_id
  LOOP
    v_new := public.ottoq_throughput_scorecard(r.sim_run_id);
    v_n := v_n + 1;
    IF (v_new - 'scorecard_version') #- '{run,site_buildout}' IS DISTINCT FROM (r.scorecard - 'scorecard_version') THEN
      v_bad := v_bad + 1;
    END IF;
  END LOOP;
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0567 V3: % of % stored 0566 scorecards read differently under 0567 on a day with no build-out', v_bad, v_n;
  END IF;
  RAISE NOTICE '0567 V3: % stored 0566 scorecards read the same under 0567', v_n;
END $verify_scorecard$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0567_a_charger_build_out_lives_only_inside_a_test_day', false, false,
  'Build-out definitions, apply/restore/census functions called by nothing yet, a commit guard on a table that is always empty between transactions, and a new body for the read-only throughput scorecard. No engine path, runner or determinism pair calls any of them, so no certified digest can move and no dial experiment spans a changed engine.',
  now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
