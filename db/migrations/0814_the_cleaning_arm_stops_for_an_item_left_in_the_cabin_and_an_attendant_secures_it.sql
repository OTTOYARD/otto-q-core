-- migration-version: 20261112024432
-- migration-name:    the_cleaning_arm_stops_for_an_item_left_in_the_cabin_and_an_attendant_secures_it
--
-- 0814  **The cleaning arm stops for an item left in the cabin, and an attendant secures it.**
--       Chase, 2026-11-11: "Vaccuum arm- maybe let's have a flag for 'items found in vehicle' that an attendent has to
--       walk over and pick up to secure. This will be crucial for lost and found items that aren't just sucked into the
--       vaccuum or ignored (wallets, phones, personal items). The machine can pause and let out an alert that an
--       attendent has to walk over and clear and then. Manually confirm reactivation from the pulse app. This should be
--       realatively quick turnaround from a simulation perspective since it only takes an individual a few seconds to
--       walk over, address the flagged item, secure it, and re-activate the robot and allow OTTO-Q to continue it's
--       orchestration." And, the same evening, to four questions put to him: "Go with your recommendations on all four
--       and execute" (the twin's own attendant clears an item in 60 to 90 seconds when nobody confirms in OTTO-PULSE
--       first; the twin finds an item in about 1 clean in 25, an ASSUMPTION; Claude Code writes and applies this).
--
-- ══ §1 WHAT THE ENGINE DOES TODAY (read-only, 2026-11-11, 8:30 to 9:10 PM CT) ════════════════════════════════════════
--
--   A fast charger's cleaning arm does a car's interior tidy as a visit atom (0758, 0764, 0765, 0767, 0798):
--   status in_progress, performed_by 'stall_cabin_robot', robot_stall_id, started_at, ends_at = started_at + the cycle
--   (5.8 minutes at the defaults: 2 x cabin_robot_side_min 2.5 + cabin_robot_motion_min 0.8). The completion step
--   (twin.ottoq_sim_advance_visit_atoms) completes it at ends_at, and ottoq.ottoq_uplink_transfer_holds keeps the car on
--   its post while the atom is in progress. Nothing models an object in the cabin: the arm never stops, and nothing is
--   recorded for an owner's lost property. Both tick orchestrators (public.ottoq_sim_advance_tick_world, md5(prosrc)
--   033519ac; twin.ottoq_world_advance, md5 361c6d44) call ottoq.ottoq_owner_orders_tick and then the completion step.
--
-- ══ §2 WHAT THIS CHANGES (all behind cabin_found_item_rate; 0, the default, changes nothing) ═════════════════════════
--
--   (a) Three dials, a person's, not agent-writable: cabin_found_item_rate (the share of the arm's cleans in which the
--       twin puts an item in the cabin; 0 to 1, default 0), cabin_found_item_attendant_s_min and _max (how long the
--       twin's own attendant takes to walk over, secure the item and restart the arm; 60 and 90 sim seconds).
--   (b) public.ottoq_cabin_found_items: one row per item, class 'evidence' (an owner's lost property is a record that
--       outlives its run; no FK to ottoq_sim_runs, as 0340's ledger has none): the run, the depot, the post, the car and
--       its owner, what kind of thing it is, when the arm found it, when the twin's attendant is due, when and by whom
--       it was secured, and how long the arm stood still.
--   (c) twin.ottoq_sim_cabin_found_items_tick(run, clock), called once a tick by both orchestrators right after the
--       owners' orders and BEFORE the completion step. It does two things.
--         1. An item whose attendant is due is secured: by 'twin_attendant', at the due time.
--         2. Each of the arm's cleans that is in progress and has not been checked is checked once: a seeded draw keyed
--            on (the run's seed, the car, sim seconds from the run's start to the clean's start), what a run reproduces
--            (0052's rule; never the run's id, a minted id or the wall clock). On a find the arm stops inside its first
--            side (found_at = started_at + 25 to 75 % of cabin_robot_side_min), the attendant is due 60 to 90 seconds
--            later, and the clean's ends_at moves later by exactly that wait. The atom records it (item_check 'found',
--            found_item {key, kind, found_at, attendant_due_at, status}, ends_at_before_item); otherwise item_check
--            'clear'. The clean is never skipped or shortened (rule 9): it ends later by the time the arm stood still.
--       The existing hold keeps the car on its post until the arm is home, because the atom stays in progress.
--   (d) public.ottoq_cabin_item_secure(run, item_key, by): an attendant's confirm from OTTO-PULSE. It secures an item that
--       has been found and is still waiting, at the run's sim clock, and moves the clean's ends_at EARLIER by the wait
--       the twin's attendant would still have taken. A person who is faster than the twin's attendant wins; one who is
--       slower finds it already secured. Signed-in callers only (as ottoq_comms_teleop_respond).
--   (e) public.ottoq_cabin_found_items_feed(run, limit): what the cockpits read. An item is listed from its found_at on
--       the run's sim clock, never before (the draw happens a tick before the arm reaches the item).
--   (f) Two events, catalogued: cabin.item_found (warning) and cabin.item_secured (info).
--
--   Not built, and why. The snapshot (public.ottoq_twin_snapshot) does not publish the atom's new keys: the cockpits
--   read (e), which is one small function, where the snapshot is a 60 kB body another session is changing this week.
--   The arm's itinerary leg keeps its planned end; the completion step closes it at the real end, as it does today.
--
-- ══ §3 THE NUMBERS, AND THEIR SOURCES ═════════════════════════════════════════════════════════════════════════════
--
--   cabin_found_item_rate 0.04 at the twin depot: ASSUMPTION, Chase's to change (he accepted "about 1 clean in 25" on
--   2026-11-11). No public rate of items left in a robotaxi per trip was looked for or found; it is a demonstration
--   setting, not a measurement, and no KPI may be read as depending on it without saying so.
--   60 to 90 seconds for the attendant: Chase's own words ("only takes an individual a few seconds to walk over ...
--   relatively quick turnaround"), set a little longer so the stop is visible at 1x. ASSUMPTION.
--
-- ══ §4 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 both orchestrators are the bodies this file was written against (md5 above), each holding
--   its owner-orders anchor exactly once. P2 once. V1 each body less its insertion is its pre-image. V2 at rate 0 the
--   tick function returns before it reads a run. V3 the functions exist with the grants (d) and (e) name. V4 plays the
--   behaviour on one of the arm's past cleans (the find, a person's confirm, the twin's attendant, the events) inside a
--   block that is rolled back, and fails the whole file if any step is not as §2 says. What V4 measured is written into
--   this file's lineage note.
--   Not rehearsed in the research lab: its only export is 2026-11-04, 20 migrations behind production, and this session
--   holds no token for a fresh one. V4 is the rehearsal, on production's own catalog and data, inside the apply.
--
-- ══ §5 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE: at rate 0 the new call returns at its first statement and nothing else is reached (V2), and no
--   certification arm, canon cell or dial experiment sets the rate. forces_dial_restart FALSE: no experiment varies it.
--
-- ══ §6 ON AT THE TWIN DEPOT (CLAUDE.md rule 12) ═══════════════════════════════════════════════════════════════════
--
--   cabin_found_item_rate 0.04 at depot scope, twin depot only (rule 8), under "Chase (delegated to Claude Code: 0814)".
--   From each run's next tick. Undo: DELETE that ottoq_policy_params row.
--
-- ROLLBACK: EXECUTE both `definition`s in ottoq_schema_snapshots WHERE label = '0814_pre'; DELETE FROM
--   public.ottoq_policy_params WHERE param_key LIKE 'cabin_found_item%'; DELETE FROM public.ottoq_policy_param_catalog
--   WHERE param_key LIKE 'cabin_found_item%'; DROP FUNCTION public.ottoq_cabin_item_secure(uuid, text, text),
--   public.ottoq_cabin_found_items_feed(uuid, integer), twin.ottoq_sim_cabin_found_items_tick(uuid, timestamptz);
--   DELETE FROM public.ottoq_cert_lineage WHERE name LIKE '0814_%'. Keep public.ottoq_cabin_found_items: it is the
--   record of what was found.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0814 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the bodies this file was written against ──
DO $p1$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_sim_advance_tick_world(uuid)', '033519acab76a0b28553aa674545100e'),
      ('twin.ottoq_world_advance()',                '361c6d44d5dcc7cb6793ae51a291db0d')) v(fn, want) LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(r.fn)) IS DISTINCT FROM r.want THEN
      RAISE EXCEPTION '0814 P1: % is not the body this file was written against', r.fn;
    END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'cabin_robot_side_min') THEN
    RAISE EXCEPTION '0814 P1: 0758 is not applied';
  END IF;
END $p1$;

-- ── P2: once ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0814_the_cleaning_arm_stops_for_an_item_left_in_the_cabin_and_an_attendant_secures_it') THEN
    RAISE EXCEPTION '0814 P2: already applied';
  END IF;
END $once$;

-- ── the pre-images ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0814_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_sim_advance_tick_world(uuid)'::regprocedure, 'twin.ottoq_world_advance()'::regprocedure);

-- ── (a) the dials ──
INSERT INTO public.ottoq_policy_param_catalog
       (param_key, description, default_value, min_value, max_value, affects, agent_writable)
VALUES
  ('cabin_found_item_rate',
   '0814: the share of the fast-charger cleaning arm''s cabin cleans in which the twin puts an item in the cabin (a '
   'wallet, a phone). The arm stops, an attendant secures the item, and the clean ends later by the wait. 0 = never '
   '(nothing runs). ASSUMPTION at the twin depot (0.04, Chase 2026-11-11): a demonstration setting, not a measured rate.',
   0, 0, 1, 'twin.ottoq_sim_cabin_found_items_tick', false),
  ('cabin_found_item_attendant_s_min',
   '0814: the shortest time, in sim seconds, the twin''s own attendant takes to walk to the post, secure a found item '
   'and restart the arm, when nobody confirms in OTTO-PULSE first. ASSUMPTION (Chase 2026-11-11: a quick turnaround).',
   60, 5, 3600, 'twin.ottoq_sim_cabin_found_items_tick', false),
  ('cabin_found_item_attendant_s_max',
   '0814: the longest time, in sim seconds, the twin''s own attendant takes. Drawn evenly between the two. ASSUMPTION.',
   90, 5, 3600, 'twin.ottoq_sim_cabin_found_items_tick', false);

-- ── (b) the record ──
CREATE TABLE public.ottoq_cabin_found_items (
  item_id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  item_key           text NOT NULL,
  sim_run_id         uuid,
  depot_id           uuid NOT NULL,
  stall_id           uuid NOT NULL,
  vehicle_id         uuid NOT NULL,
  fleet_operator_id  uuid,
  visit_id           uuid,
  item_kind          text NOT NULL,
  found_at           timestamptz NOT NULL,
  attendant_due_at   timestamptz NOT NULL,
  secured_at         timestamptz,
  secured_by         text,
  status             text NOT NULL DEFAULT 'awaiting_attendant' CHECK (status IN ('awaiting_attendant', 'secured')),
  pause_seconds      numeric,
  data_source        text NOT NULL DEFAULT 'twin',
  recorded_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (sim_run_id, item_key),
  CHECK (attendant_due_at >= found_at),
  CHECK ((status = 'secured') = (secured_at IS NOT NULL))
);
COMMENT ON TABLE public.ottoq_cabin_found_items IS
  '0814: every item a fast charger''s cleaning arm found in a car''s cabin: where, whose car, when it was found and '
  'when and by whom it was secured. Evidence (an owner''s lost property outlives its run): no FK to ottoq_sim_runs. '
  'Times are the run''s SIM clock. item_key is a digest of what a run reproduces (its seed, the car, the clean''s start), '
  'never a minted id, so two runs on one seed carry the same key: the row is one run''s by (sim_run_id, item_key).';
CREATE INDEX ottoq_cabin_found_items_run_idx ON public.ottoq_cabin_found_items (sim_run_id, found_at DESC);
CREATE INDEX ottoq_cabin_found_items_waiting_idx ON public.ottoq_cabin_found_items (sim_run_id, attendant_due_at)
  WHERE status = 'awaiting_attendant';
ALTER TABLE public.ottoq_cabin_found_items ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ottoq_cabin_found_items FROM PUBLIC, anon, authenticated;

INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public', 'ottoq_cabin_found_items', 'sim_run_id', 'evidence',
        '0814: the record of items found in cabins. Evidence, not engine: an owner''s lost property must outlive the '
        'run it was found in. No FK to ottoq_sim_runs, as 0340''s ledger has none.');

-- ── (f) the events ──
INSERT INTO public.ottoq_event_types_catalog (event_type, category, description, emitter, default_severity, introduced_in)
VALUES
  ('cabin.item_found', 'integration_event',
   'A fast charger''s cleaning arm found an item in a car''s cabin and stopped. An attendant must secure it. Emitted by '
   'twin.ottoq_sim_cabin_found_items_tick (actor_id=twin_clean_arm). Payload: item_key, item_kind, stall_id, '
   'found_at, attendant_due_at (sim clock).',
   'twin_simulator', 'warning', '0814_cabin_found_items'),
  ('cabin.item_secured', 'integration_event',
   'A found item was secured and the cleaning arm restarted: by the twin''s own attendant (actor_id=twin_attendant) or '
   'by a person confirming in OTTO-PULSE (public.ottoq_cabin_item_secure). Payload: item_key, secured_by, human, '
   'pause_seconds.',
   'twin_simulator', 'info', '0814_cabin_found_items');

-- ── (c) the tick ──
CREATE FUNCTION twin.ottoq_sim_cabin_found_items_tick(p_sim_run_id uuid, p_clock timestamptz)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = twin, ottoq, public, extensions
AS $fn$
DECLARE
  v_rate numeric; v_lo numeric; v_hi numeric; v_side numeric;
  v_depot uuid; v_seed bigint; v_start timestamptz;
  v_it record; v_vn record; v_a jsonb; v_new jsonb; v_changed boolean;
  v_salt text; v_wait numeric; v_found timestamptz; v_due timestamptz; v_key text; v_kind text; v_n int := 0;
  v_veh record;
  c_kinds constant text[] := ARRAY['phone', 'wallet', 'keys', 'bag', 'glasses', 'earbuds', 'umbrella', 'card holder'];
BEGIN
  v_rate := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'cabin_found_item_rate', 0), 0);
  IF v_rate <= 0 THEN RETURN 0; END IF;                                  -- off: nothing below is reached (V2)

  SELECT depot_id, COALESCE(random_seed, 42), sim_clock_start INTO v_depot, v_seed, v_start
    FROM public.ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL OR v_start IS NULL THEN RETURN 0; END IF;
  v_lo   := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id, 'cabin_found_item_attendant_s_min', 60), 60), 5);
  v_hi   := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id, 'cabin_found_item_attendant_s_max', 90), 90), v_lo);
  v_side := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id, 'cabin_robot_side_min', 2.5), 2.5), 0.5);

  -- 1. the twin's attendant has reached these: secured at the due time. The clean's end already counts the wait.
  FOR v_it IN
    SELECT * FROM public.ottoq_cabin_found_items
     WHERE sim_run_id = p_sim_run_id AND status = 'awaiting_attendant' AND attendant_due_at <= p_clock
     ORDER BY attendant_due_at, item_key
  LOOP
    UPDATE public.ottoq_cabin_found_items
       SET status = 'secured', secured_at = v_it.attendant_due_at, secured_by = 'twin_attendant',
           pause_seconds = round(extract(epoch FROM (v_it.attendant_due_at - v_it.found_at))::numeric, 1)
     WHERE item_id = v_it.item_id;
    UPDATE public.ottoq_visit_needs vn
       SET atoms = (SELECT jsonb_agg(CASE WHEN a->'found_item'->>'key' = v_it.item_key
                                          THEN jsonb_set(jsonb_set(a, '{found_item,status}', '"secured"'),
                                                         '{found_item,secured_at}', to_jsonb(v_it.attendant_due_at))
                                          ELSE a END ORDER BY ord)
                      FROM jsonb_array_elements(vn.atoms) WITH ORDINALITY x(a, ord))
     WHERE vn.visit_id = v_it.visit_id
       AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a WHERE a->'found_item'->>'key' = v_it.item_key);
    PERFORM public.ottoq_record_event(
      p_actor_type := 'system', p_actor_id := 'twin_attendant', p_event_type := 'cabin.item_secured',
      p_entity_type := 'vehicle', p_entity_id := v_it.vehicle_id, p_depot_id := v_it.depot_id,
      p_fleet_operator_id := v_it.fleet_operator_id,
      p_payload := jsonb_build_object('item_key', v_it.item_key, 'item_kind', v_it.item_kind, 'stall_id', v_it.stall_id,
                                      'secured_by', 'twin_attendant', 'human', false,
                                      'pause_seconds', round(extract(epoch FROM (v_it.attendant_due_at - v_it.found_at))::numeric, 1)),
      p_severity := 'info', p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
    v_n := v_n + 1;
  END LOOP;

  -- 2. each of the arm's cleans under way that has not been checked is checked once
  FOR v_vn IN
    SELECT vn.visit_id, vn.vehicle_id, vn.atoms
      FROM public.ottoq_visit_needs vn
     WHERE vn.depot_id = v_depot AND vn.status IN ('open', 'in_progress')
       AND vn.sim_run_id = p_sim_run_id
       AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                    WHERE a->>'status' = 'in_progress' AND a->>'performed_by' = 'stall_cabin_robot'
                      AND NOT (a ? 'item_check') AND a->>'started_at' IS NOT NULL AND a->>'ends_at' IS NOT NULL
                      AND a->>'robot_stall_id' IS NOT NULL)
     ORDER BY vn.vehicle_id, vn.visit_id
  LOOP
    v_new := '[]'::jsonb; v_changed := false;
    FOR v_a IN SELECT a FROM jsonb_array_elements(v_vn.atoms) WITH ORDINALITY x(a, ord) ORDER BY ord LOOP
      IF v_a->>'status' = 'in_progress' AND v_a->>'performed_by' = 'stall_cabin_robot' AND NOT (v_a ? 'item_check')
         AND v_a->>'started_at' IS NOT NULL AND v_a->>'ends_at' IS NOT NULL AND v_a->>'robot_stall_id' IS NOT NULL THEN
        -- what a run reproduces: its seed, the car, and sim seconds from the run's start to this clean's start (0052)
        v_salt := 'cabin_item:' || v_vn.vehicle_id::text || ':'
                  || round(extract(epoch FROM ((v_a->>'started_at')::timestamptz - v_start)))::text;
        IF twin.ottoq_sim_seeded_random(v_seed, v_salt) < v_rate THEN
          v_found := (v_a->>'started_at')::timestamptz
                     + make_interval(secs => (0.25 + 0.5 * twin.ottoq_sim_seeded_random(v_seed, v_salt || ':when'))::double precision
                                             * v_side::double precision * 60.0);
          v_wait  := round(v_lo + (v_hi - v_lo) * twin.ottoq_sim_seeded_random(v_seed, v_salt || ':wait'), 1);
          v_due   := v_found + make_interval(secs => v_wait::double precision);
          v_kind  := c_kinds[1 + floor(twin.ottoq_sim_seeded_random(v_seed, v_salt || ':kind') * array_length(c_kinds, 1))::int];
          v_key   := md5(v_seed::text || '|' || v_salt);
          SELECT v.fleet_operator_id INTO v_veh FROM public.vehicles v WHERE v.id = v_vn.vehicle_id;
          INSERT INTO public.ottoq_cabin_found_items
                 (item_key, sim_run_id, depot_id, stall_id, vehicle_id, fleet_operator_id, visit_id, item_kind,
                  found_at, attendant_due_at)
          VALUES (v_key, p_sim_run_id, v_depot, (v_a->>'robot_stall_id')::uuid, v_vn.vehicle_id, v_veh.fleet_operator_id,
                  v_vn.visit_id, v_kind, v_found, v_due)
          ON CONFLICT (sim_run_id, item_key) DO NOTHING;
          v_a := v_a || jsonb_build_object(
                   'item_check', 'found',
                   'ends_at_before_item', v_a->'ends_at',
                   'ends_at', to_jsonb((v_a->>'ends_at')::timestamptz + make_interval(secs => v_wait::double precision)),
                   'found_item', jsonb_build_object('key', v_key, 'kind', v_kind, 'found_at', to_jsonb(v_found),
                                                    'attendant_due_at', to_jsonb(v_due), 'status', 'awaiting_attendant'));
          PERFORM public.ottoq_record_event(
            p_actor_type := 'system', p_actor_id := 'twin_clean_arm', p_event_type := 'cabin.item_found',
            p_entity_type := 'vehicle', p_entity_id := v_vn.vehicle_id, p_depot_id := v_depot,
            p_fleet_operator_id := v_veh.fleet_operator_id,
            p_payload := jsonb_build_object('item_key', v_key, 'item_kind', v_kind, 'stall_id', v_a->>'robot_stall_id',
                                            'found_at', v_found, 'attendant_due_at', v_due),
            p_severity := 'warning', p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
          v_n := v_n + 1;
        ELSE
          v_a := v_a || jsonb_build_object('item_check', 'clear');
        END IF;
        v_changed := true;
      END IF;
      v_new := v_new || jsonb_build_array(v_a);
    END LOOP;
    IF v_changed THEN
      UPDATE public.ottoq_visit_needs SET atoms = v_new WHERE visit_id = v_vn.visit_id;
    END IF;
  END LOOP;
  RETURN v_n;
END;
$fn$;
COMMENT ON FUNCTION twin.ottoq_sim_cabin_found_items_tick(uuid, timestamptz) IS
  '0814: once a tick, before the completion step. Secures the items the twin''s attendant has reached, and checks each '
  'of the cleaning arm''s cleans under way once for an item in the cabin (a seeded draw at cabin_found_item_rate). A '
  'find moves the clean''s end later by the attendant''s wait: the clean is never shortened or skipped (rule 9).';
REVOKE ALL ON FUNCTION twin.ottoq_sim_cabin_found_items_tick(uuid, timestamptz) FROM PUBLIC, anon, authenticated;

-- ── (d) an attendant's confirm ──
CREATE FUNCTION public.ottoq_cabin_item_secure(p_sim_run_id uuid, p_item_key text, p_by text DEFAULT 'depot_attendant')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = twin, ottoq, public, extensions
AS $fn$
DECLARE v_it record; v_now timestamptz; v_at timestamptz; v_saved numeric; v_by text;
BEGIN
  v_by := left(COALESCE(NULLIF(btrim(p_by), ''), 'depot_attendant'), 80);
  SELECT * INTO v_it FROM public.ottoq_cabin_found_items
   WHERE sim_run_id = p_sim_run_id AND item_key = p_item_key FOR UPDATE;
  IF v_it.item_id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'no such item'); END IF;
  IF v_it.status = 'secured' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already secured', 'secured_by', v_it.secured_by, 'secured_at', v_it.secured_at);
  END IF;
  SELECT sim_clock_current INTO v_now FROM public.ottoq_sim_runs WHERE sim_run_id = v_it.sim_run_id;
  IF v_now IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'the run has no clock'); END IF;
  IF v_now < v_it.found_at THEN RETURN jsonb_build_object('ok', false, 'error', 'the arm has not found it yet'); END IF;
  v_at    := LEAST(v_now, v_it.attendant_due_at);
  v_saved := GREATEST(extract(epoch FROM (v_it.attendant_due_at - v_at))::numeric, 0);

  UPDATE public.ottoq_cabin_found_items
     SET status = 'secured', secured_at = v_at, secured_by = v_by,
         pause_seconds = round(extract(epoch FROM (v_at - v_it.found_at))::numeric, 1)
   WHERE item_id = v_it.item_id;
  -- the arm restarts now: its clean ends earlier by the wait the twin's attendant would still have taken
  UPDATE public.ottoq_visit_needs vn
     SET atoms = (SELECT jsonb_agg(CASE WHEN a->'found_item'->>'key' = v_it.item_key THEN
                             jsonb_set(jsonb_set(
                               CASE WHEN a->>'status' = 'in_progress' AND a->>'ends_at' IS NOT NULL
                                    THEN jsonb_set(a, '{ends_at}', to_jsonb((a->>'ends_at')::timestamptz - make_interval(secs => v_saved::double precision)))
                                    ELSE a END,
                               '{found_item,status}', '"secured"'), '{found_item,secured_at}', to_jsonb(v_at))
                           ELSE a END ORDER BY ord)
                    FROM jsonb_array_elements(vn.atoms) WITH ORDINALITY x(a, ord))
   WHERE vn.visit_id = v_it.visit_id
     AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a WHERE a->'found_item'->>'key' = v_it.item_key);
  PERFORM public.ottoq_record_event(
    p_actor_type := 'depot_tech', p_actor_id := v_by, p_event_type := 'cabin.item_secured',
    p_entity_type := 'vehicle', p_entity_id := v_it.vehicle_id, p_depot_id := v_it.depot_id,
    p_fleet_operator_id := v_it.fleet_operator_id,
    p_payload := jsonb_build_object('item_key', v_it.item_key, 'item_kind', v_it.item_kind, 'stall_id', v_it.stall_id,
                                    'secured_by', v_by, 'human', true,
                                    'pause_seconds', round(extract(epoch FROM (v_at - v_it.found_at))::numeric, 1)),
    p_severity := 'info', p_ingest_source := 'app', p_data_source := 'twin', p_sim_run_id := v_it.sim_run_id);
  RETURN jsonb_build_object('ok', true, 'item_key', v_it.item_key, 'secured_at', v_at, 'secured_by', v_by,
                            'seconds_saved', round(v_saved, 1));
END;
$fn$;
COMMENT ON FUNCTION public.ottoq_cabin_item_secure(uuid, text, text) IS
  '0814: an attendant confirms in OTTO-PULSE that a found item is secured. The arm restarts and its clean ends earlier '
  'by the wait the twin''s own attendant would still have taken. Signed-in callers only.';
REVOKE ALL ON FUNCTION public.ottoq_cabin_item_secure(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ottoq_cabin_item_secure(uuid, text, text) TO authenticated, service_role;

-- ── (e) what the cockpits read ──
CREATE FUNCTION public.ottoq_cabin_found_items_feed(p_sim_run_id uuid, p_limit integer DEFAULT 50)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = twin, ottoq, public, extensions
AS $fn$
  WITH run AS (SELECT sim_clock_current AS now_sim FROM public.ottoq_sim_runs WHERE sim_run_id = p_sim_run_id),
  it AS (
    SELECT i.*, s.stall_code, v.display_name AS vehicle_name
      FROM public.ottoq_cabin_found_items i
      JOIN run r ON true
      LEFT JOIN public.stalls s ON s.id = i.stall_id
      LEFT JOIN public.vehicles v ON v.id = i.vehicle_id
     WHERE i.sim_run_id = p_sim_run_id AND i.found_at <= r.now_sim
     ORDER BY (i.status = 'awaiting_attendant') DESC, i.found_at DESC
     LIMIT GREATEST(LEAST(COALESCE(p_limit, 50), 200), 1)
  )
  SELECT jsonb_build_object(
    'sim_run_id', p_sim_run_id,
    'sim_clock', (SELECT now_sim FROM run),
    'waiting', (SELECT count(*) FROM it WHERE status = 'awaiting_attendant'),
    'items', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'item_key', item_key, 'item_kind', item_kind, 'status', status,
        'stall_id', stall_id, 'stall_code', stall_code,
        'vehicle_id', vehicle_id, 'vehicle_name', vehicle_name, 'fleet_operator_id', fleet_operator_id,
        'found_at', found_at, 'attendant_due_at', attendant_due_at,
        'secured_at', secured_at, 'secured_by', secured_by, 'pause_seconds', pause_seconds)
        ORDER BY (status = 'awaiting_attendant') DESC, found_at DESC) FROM it), '[]'::jsonb));
$fn$;
COMMENT ON FUNCTION public.ottoq_cabin_found_items_feed(uuid, integer) IS
  '0814: the items the cleaning arms found in a run, the ones still waiting first. An item is listed from its found_at '
  'on the run''s sim clock, never before. Times are the sim clock.';
REVOKE ALL ON FUNCTION public.ottoq_cabin_found_items_feed(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ottoq_cabin_found_items_feed(uuid, integer) TO anon, authenticated, service_role;

-- ── the two insertions ──
CREATE TEMP TABLE _0814_patch (fn text, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0814_patch VALUES
('public.ottoq_sim_advance_tick_world(uuid)',
$o$  PERFORM ottoq.ottoq_owner_orders_tick(p_sim_run_id, v_new_sim_clock);
$o$,
$n$  PERFORM ottoq.ottoq_owner_orders_tick(p_sim_run_id, v_new_sim_clock);
  -- 0814: an item the stall's cleaning arm finds in a cabin (the stop, and the twin's attendant), before the visit atoms
  -- advance. Inert at cabin_found_item_rate 0: one dial read. A failure here never stops the tick.
  BEGIN PERFORM twin.ottoq_sim_cabin_found_items_tick(p_sim_run_id, v_new_sim_clock);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'advance_tick_world cabin_found_items: %', SQLERRM; END;
$n$),
('twin.ottoq_world_advance()',
$o$  BEGIN PERFORM ottoq.ottoq_owner_orders_tick(v_run.sim_run_id, v_now);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance owner_orders: %', SQLERRM; END;
$o$,
$n$  BEGIN PERFORM ottoq.ottoq_owner_orders_tick(v_run.sim_run_id, v_now);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance owner_orders: %', SQLERRM; END;
  -- 0814: an item the stall's cleaning arm finds in a cabin, before the visit atoms advance. Inert at rate 0.
  BEGIN PERFORM twin.ottoq_sim_cabin_found_items_tick(v_run.sim_run_id, v_now);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance cabin_found_items: %', SQLERRM; END;
$n$);
UPDATE _0814_patch SET c_old = replace(c_old, E'\r\n', E'\n'), c_new = replace(c_new, E'\r\n', E'\n');

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  FOR p IN SELECT * FROM _0814_patch ORDER BY fn LOOP
    v_def := pg_get_functiondef(to_regprocedure(p.fn));
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN RAISE EXCEPTION '0814: the anchor in % matches % times, not 1', p.fn, n; END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
    EXECUTE v_def;
    IF pg_get_functiondef(to_regprocedure(p.fn)) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0814: % is not stored as patched', p.fn;
    END IF;
  END LOOP;
END $patch$;

-- ── V1: each body less its insertion is its pre-image ──
DO $v1$
DECLARE p record; v_body text; v_want text;
BEGIN
  FOR p IN SELECT * FROM _0814_patch ORDER BY fn LOOP
    SELECT replace(prosrc, p.c_new, p.c_old) INTO v_body FROM pg_proc WHERE oid = to_regprocedure(p.fn);
    v_want := CASE p.fn WHEN 'public.ottoq_sim_advance_tick_world(uuid)' THEN '033519acab76a0b28553aa674545100e'
                        ELSE '361c6d44d5dcc7cb6793ae51a291db0d' END;
    IF md5(v_body) IS DISTINCT FROM v_want THEN
      RAISE EXCEPTION '0814 V1: % less its insertion is not its pre-image (md5 %)', p.fn, md5(v_body);
    END IF;
  END LOOP;
END $v1$;

-- ── V2: at rate 0 the tick function returns before it reads a run (a run that does not exist is not looked for) ──
DO $v2$
BEGIN
  IF twin.ottoq_sim_cabin_found_items_tick('00000000-0000-0000-0000-000000000000'::uuid, now()) <> 0 THEN
    RAISE EXCEPTION '0814 V2: the tick function did something at rate 0';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cabin_found_items) THEN
    RAISE EXCEPTION '0814 V2: the record is not empty at apply';
  END IF;
END $v2$;

-- ── V3: the grants ──
DO $v3$
BEGIN
  IF has_function_privilege('anon', 'public.ottoq_cabin_item_secure(uuid,text,text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.ottoq_cabin_item_secure(uuid,text,text)', 'EXECUTE')
     OR NOT has_function_privilege('anon', 'public.ottoq_cabin_found_items_feed(uuid,integer)', 'EXECUTE')
     OR has_function_privilege('anon', 'twin.ottoq_sim_cabin_found_items_tick(uuid,timestamptz)', 'EXECUTE')
     OR has_table_privilege('anon', 'public.ottoq_cabin_found_items', 'SELECT') THEN
    RAISE EXCEPTION '0814 V3: a grant is not as §2 names it';
  END IF;
END $v3$;

-- ── V4: the behaviour, on a past clean, inside a block that is rolled back ──
-- Stages one of the cleaning arm's past cleans as under way at rate 1, plays the find, a person's confirm and the twin's
-- attendant, and asserts each. Everything it writes is undone when the inner block ends in its own exception. What it
-- measured goes into this file's lineage note. With no past clean to stage it says so and asserts nothing.
CREATE TEMP TABLE _0814_selftest (result jsonb) ON COMMIT DROP;
DO $v4$
DECLARE
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_visit uuid; v_run uuid; v_started timestamptz; v_ends0 timestamptz; v_ends1 timestamptz; v_ends2 timestamptz;
  v_it record; v_n int; v_n2 int; v_s text; v_ends3 timestamptz; v_r jsonb; v_feed jsonb; v_res jsonb; v_wait interval;
BEGIN
  SELECT vn.visit_id, vn.sim_run_id INTO v_visit, v_run
    FROM public.ottoq_visit_needs vn JOIN public.ottoq_sim_runs r ON r.sim_run_id = vn.sim_run_id
   WHERE vn.depot_id = c_depot AND r.sim_clock_start IS NOT NULL
     AND (SELECT count(*) FROM jsonb_array_elements(vn.atoms) a
           WHERE a->>'performed_by' = 'stall_cabin_robot' AND a->>'started_at' IS NOT NULL AND a->>'ends_at' IS NOT NULL
             AND a->>'robot_stall_id' IS NOT NULL) = 1
   ORDER BY vn.created_at DESC, vn.visit_id LIMIT 1;
  IF v_visit IS NULL THEN
    INSERT INTO _0814_selftest VALUES (jsonb_build_object('ran', false, 'why', 'no past clean by the arm to stage'));
    RETURN;
  END IF;
  BEGIN
    INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
    VALUES ('depot', c_depot, 'cabin_found_item_rate', 1, '0814 self-test', now());
    UPDATE public.ottoq_visit_needs vn
       SET status = 'open',
           atoms = (SELECT jsonb_agg(CASE WHEN a->>'performed_by' = 'stall_cabin_robot'
                                          THEN (a - 'item_check' - 'found_item' - 'done_at' - 'ends_at_before_item')
                                               || jsonb_build_object('status', 'in_progress')
                                          ELSE a END ORDER BY ord)
                      FROM jsonb_array_elements(vn.atoms) WITH ORDINALITY x(a, ord))
     WHERE vn.visit_id = v_visit;
    SELECT (a->>'started_at')::timestamptz, (a->>'ends_at')::timestamptz INTO v_started, v_ends0
      FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
     WHERE vn.visit_id = v_visit AND a->>'performed_by' = 'stall_cabin_robot';

    -- the find
    v_n := twin.ottoq_sim_cabin_found_items_tick(v_run, v_started + interval '20 seconds');
    SELECT * INTO v_it FROM public.ottoq_cabin_found_items WHERE visit_id = v_visit;
    IF v_n <> 1 OR v_it.item_id IS NULL OR v_it.status <> 'awaiting_attendant' THEN
      RAISE EXCEPTION '0814 V4: at rate 1 the staged clean found no item (n=%)', v_n;
    END IF;
    v_wait := v_it.attendant_due_at - v_it.found_at;
    IF v_wait < interval '60 seconds' OR v_wait > interval '90 seconds'
       OR v_it.found_at < v_started + interval '37 seconds' OR v_it.found_at > v_started + interval '113 seconds' THEN
      RAISE EXCEPTION '0814 V4: the find or the wait is outside its bounds (found +% s, wait %)',
        extract(epoch FROM v_it.found_at - v_started), v_wait;
    END IF;
    SELECT (a->>'ends_at')::timestamptz INTO v_ends1
      FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
     WHERE vn.visit_id = v_visit AND a->'found_item'->>'key' = v_it.item_key AND a->>'item_check' = 'found';
    IF v_ends1 IS DISTINCT FROM v_ends0 + v_wait THEN
      RAISE EXCEPTION '0814 V4: the clean''s end did not move later by the wait (% -> %, wait %)', v_ends0, v_ends1, v_wait;
    END IF;
    IF twin.ottoq_sim_cabin_found_items_tick(v_run, v_started + interval '25 seconds') <> 0 THEN
      RAISE EXCEPTION '0814 V4: a checked clean was checked again';
    END IF;

    -- not listed before the arm reaches it; listed after
    UPDATE public.ottoq_sim_runs SET sim_clock_current = v_it.found_at - interval '1 second' WHERE sim_run_id = v_run;
    IF (public.ottoq_cabin_found_items_feed(v_run)->>'waiting')::int <> 0 THEN
      RAISE EXCEPTION '0814 V4: the feed lists an item before it is found';
    END IF;
    IF (public.ottoq_cabin_item_secure(v_run, v_it.item_key, 'self-test')->>'ok')::boolean THEN
      RAISE EXCEPTION '0814 V4: an item was secured before it was found';
    END IF;
    UPDATE public.ottoq_sim_runs SET sim_clock_current = v_it.found_at + interval '10 seconds' WHERE sim_run_id = v_run;
    v_feed := public.ottoq_cabin_found_items_feed(v_run);
    IF (v_feed->>'waiting')::int <> 1 OR v_feed->'items'->0->>'item_key' <> v_it.item_key THEN
      RAISE EXCEPTION '0814 V4: the feed does not list the waiting item';
    END IF;

    -- a person confirms 10 seconds after the find: the clean ends earlier by the rest of the wait
    v_r := public.ottoq_cabin_item_secure(v_run, v_it.item_key, 'self-test');
    SELECT (a->>'ends_at')::timestamptz INTO v_ends2
      FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
     WHERE vn.visit_id = v_visit AND a->'found_item'->>'key' = v_it.item_key AND a->'found_item'->>'status' = 'secured';
    IF NOT (v_r->>'ok')::boolean OR v_ends2 IS DISTINCT FROM v_ends0 + interval '10 seconds'
       OR (SELECT status || '|' || secured_by FROM public.ottoq_cabin_found_items WHERE item_id = v_it.item_id) <> 'secured|self-test' THEN
      RAISE EXCEPTION '0814 V4: a person''s confirm did not restart the arm as written (%; end %)', v_r, v_ends2;
    END IF;
    IF (public.ottoq_cabin_item_secure(v_run, v_it.item_key, 'self-test')->>'ok')::boolean THEN
      RAISE EXCEPTION '0814 V4: an item was secured twice';
    END IF;

    -- the twin's own attendant: the same clean staged again, nobody confirms
    DELETE FROM public.ottoq_cabin_found_items WHERE item_id = v_it.item_id;
    UPDATE public.ottoq_visit_needs vn
       SET atoms = (SELECT jsonb_agg(CASE WHEN a->>'performed_by' = 'stall_cabin_robot'
                                          THEN (a - 'item_check' - 'found_item' - 'ends_at_before_item')
                                               || jsonb_build_object('ends_at', to_jsonb(v_ends0))
                                          ELSE a END ORDER BY ord)
                      FROM jsonb_array_elements(vn.atoms) WITH ORDINALITY x(a, ord))
     WHERE vn.visit_id = v_visit;
    v_n  := twin.ottoq_sim_cabin_found_items_tick(v_run, v_started + interval '20 seconds');
    v_n2 := twin.ottoq_sim_cabin_found_items_tick(v_run, v_it.attendant_due_at + interval '1 second');
    SELECT status || '|' || COALESCE(secured_by, '-') || '|' || COALESCE((secured_at = attendant_due_at)::text, '-') INTO v_s
      FROM public.ottoq_cabin_found_items WHERE visit_id = v_visit;
    SELECT (a->>'ends_at')::timestamptz INTO v_ends3
      FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
     WHERE vn.visit_id = v_visit AND a->'found_item'->>'status' = 'secured';
    IF v_n <> 1 OR v_n2 <> 1 OR v_s IS DISTINCT FROM 'secured|twin_attendant|true' OR v_ends3 IS DISTINCT FROM v_ends1 THEN
      RAISE EXCEPTION '0814 V4: the twin''s attendant did not secure the item at its due time (find %, secure %, item %, end % want %, visit status %, atom %)',
        v_n, v_n2, v_s, v_ends3, v_ends1,
        (SELECT status FROM public.ottoq_visit_needs WHERE visit_id = v_visit),
        (SELECT a::text FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
          WHERE vn.visit_id = v_visit AND a->>'performed_by' = 'stall_cabin_robot');
    END IF;
    IF (SELECT count(*) FROM public.ottoq_events WHERE sim_run_id = v_run AND event_type LIKE 'cabin.item_%') <> 4 THEN
      RAISE EXCEPTION '0814 V4: the events are not 2 finds and 2 securings';
    END IF;

    v_res := jsonb_build_object('ran', true, 'visit', v_visit, 'run', v_run, 'kind', v_it.item_kind,
               'found_s_after_start', round(extract(epoch FROM v_it.found_at - v_started)::numeric, 1),
               'wait_s', round(extract(epoch FROM v_wait)::numeric, 1),
               'person_at_10s_saved_s', round(extract(epoch FROM v_ends1 - v_ends2)::numeric, 1));
    RAISE EXCEPTION USING ERRCODE = 'P0814', MESSAGE = v_res::text;       -- undo everything the test wrote
  EXCEPTION WHEN SQLSTATE 'P0814' THEN
    v_res := SQLERRM::jsonb;
  END;
  IF EXISTS (SELECT 1 FROM public.ottoq_cabin_found_items)
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'cabin_found_item_rate') THEN
    RAISE EXCEPTION '0814 V4: the self-test left something behind';
  END IF;
  INSERT INTO _0814_selftest VALUES (v_res);
END $v4$;

-- ── §6: on at the twin depot ──
INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
VALUES ('depot', '11111111-1111-1111-1111-111111111111', 'cabin_found_item_rate', 0.04,
        'Chase (delegated to Claude Code: 0814)', now());

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0814_the_cleaning_arm_stops_for_an_item_left_in_the_cabin_and_an_attendant_secures_it',
        false, false,
        'Behind cabin_found_item_rate (default 0): both tick orchestrators call twin.ottoq_sim_cabin_found_items_tick '
        'after the owners'' orders and before the completion step. At 0 it returns at its first statement (V2). At the '
        'twin depot (0.04, an ASSUMPTION) a seeded draw puts an item in about 1 of the cleaning arm''s cleans in 25: the '
        'arm stops, the clean''s end moves later by the attendant''s wait (60 to 90 s, or less when a person confirms in '
        'OTTO-PULSE first), and the item is recorded in ottoq_cabin_found_items (evidence). No certification arm, canon '
        'cell or dial experiment sets the rate. V4 self-test at apply (rolled back): '
        || COALESCE((SELECT result::text FROM _0814_selftest LIMIT 1), 'no result'),
        now());

COMMIT;

-- APPLIED 2026-11-12 at 02:44:32 UTC (8:44 PM CT on 2026-11-11), ledger 20261112024432, through apply_migration, on
--   Chase's word ("Go with your recommendations on all four and execute", after the four questions put to him that
--   evening, the fourth being whether Claude Code may write and apply this). Nothing live: no run running or paused
--   (read 02:10 UTC), nothing in flight (P0), both orchestrators at the md5 P1 names. The text sent was this file from
--   its BEGIN to its COMMIT.
--   A FIRST SEND FAILED AND CHANGED NOTHING. Its V4 read the item and the clean's end inside the same IF that called
--   the tick function, and a statement does not see what a function it calls has just written, so the read was stale
--   and V4 stopped the apply ("the twin's attendant did not secure the item"). The find, the feed and the person's
--   confirm had already passed in that send. V4 now calls first and reads after, as it stands above, and passed.
--   Read back at 02:44:44 UTC: md5(prosrc) twin.ottoq_sim_cabin_found_items_tick 06cc62e8, public.ottoq_cabin_item_secure
--   b640e8b9, public.ottoq_cabin_found_items_feed e323f1a4 (each equal to this file's body, compared by md5),
--   public.ottoq_sim_advance_tick_world 68e1972b, twin.ottoq_world_advance 4a078b59; cabin_found_item_rate 0.04 at the
--   twin depot under "Chase (delegated to Claude Code: 0814)"; ottoq_cabin_found_items empty.
--   V4 as recorded in the lineage note: staged visit 5bc49730 of run 9a909c7b; the arm found an umbrella 83.2 s into
--   its clean; the twin's attendant was due 68.8 s later; a person confirming 10 s after the find saved 58.8 s.
--   NOT YET SEEN ON A RUN: no demo run has been started since the apply. The first run with the dial on is the check
--   rule 12 asks for, and it is still owed.
