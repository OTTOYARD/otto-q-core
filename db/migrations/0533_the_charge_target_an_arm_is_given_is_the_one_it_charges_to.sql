-- migration-version: 20260927171208
-- migration-name:    the_charge_target_an_arm_is_given_is_the_one_it_charges_to
--
-- 0533  **G258: an experiment on the three charge-target dials could not move its arms, and its verdict would have read
--       "the dial changes nothing". `ottoq_target_soc_cap` read the GLOBAL value only; the dial pair writes each arm's
--       value at run scope and the promoter writes a winner at depot scope, and neither was ever read. Now the cap reads
--       the run in scope, and each arm records whether it read its own dial, so a dial no arm reads is named as such and
--       not concluded on.**
--
-- ══ §1 WHAT WAS WRONG ═════════════════════════════════════════════════════════════════════════════════════════════════
--
--   `ottoq_target_soc_cap(stall_type, at)` is the depot's ceiling for one plug at one moment. The charge session applies
--   it as a LEAST when it starts and on every tick of its advance; the booking's stop target, the duration evidence, the
--   depot cards, the visit's charge plan and the L2 proposer read it too. It returned
--   `ottoq_policy_get(NULL, 'dcfc_target_soc_day', 90)`, and the same for `_night` and `l2_target_soc`. NULL is the global
--   tier alone: the run and depot tiers of the same resolver were skipped. Pair 95 of experiment 08262943
--   (`dcfc_target_soc_day` 90 against 85, busy_day in the operator's world) was complete, valid and one world, and every
--   atom of the 85% arm equalled the 90% arm's: 336.3 unmet car-hours in both (db/checks/0398 §1(a)).
--   Three consequences, the last the sharpest:
--     - Every pair of any experiment on these dials was identical. The verdict's `no_effect` branch ("byte-identical on
--       every atom: the dial changes nothing in this world") would have concluded the experiment at its first look.
--     - A winner could not have been enacted either. `ottoq_promote_dial_experiment` promotes at DEPOT scope, which the
--       cap also skipped. The promotion ledger would have recorded `enacted`, and a recert, for a value nothing read.
--     - Nothing in the verdict could tell a dial that was read and changed nothing from a dial that was never read.
--   A census of every `ottoq_policy_get` call outside comments found 179 keys read, 13 of them only at the global tier.
--   The three charge-target dials are the only ones of the 13 an experiment has named. The others say why in their own
--   source, or are switches of the harness itself:
--     - `ottoq_default_target_soc` "takes no run id on purpose";
--     - the depot's night window;
--     - `allow_concurrent_runs` and the runner switches;
--     - the retired twin start's `run_start_deployed_fraction`.
--   They are left as they are.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) `ottoq_target_soc_cap(stall_type, at, sim_run_id)` is the same CASE, read through the resolver's run, depot and
--       global tiers. The two-argument form delegates with the run in scope (`ottoq.ottoq_active_sim_run_id()`, which
--       every tick pins to its run). Outside a run it passes NULL, which reads the global value, as before.
--   (b) The four callers that hold their run pass it:
--         - the session's start (`twin.ottoq_sim_start_charge_session`);
--         - its every-tick stop target (`twin.ottoq_sim_advance_charge_sessions`);
--         - the booking's stop target (`ottoq.ottoq_record_enacted_booking`);
--         - the duration evidence (`ottoq_capture_charge_duration`, `NEW.sim_run_id`).
--       The depot cards, the visit charge plan and the L2 proposer hold no run, and read the one in scope.
--   (c) THE READ WITNESS. When `ottoq_policy_get` returns a run-scoped value, it adds `<run>:<key>` to the transaction's
--       `ottoq.run_scope_reads` setting.
--         - The dial pair clears that setting before each arm's first tick and reads it after the last.
--         - The ledger gains `dial_read_a` and `dial_read_b`: whether the control's and the treatment's own value of the
--           dial was read at all while the arm ran. They are NULL for pairs before this file.
--         - The boot fingerprint and the arm's scoring run outside that window, so only the engine's reads count.
--   (d) THE VERDICT names an unread dial.
--         - A counted pair in which neither arm read its own value gives the outcome `dial_not_read`. It is terminal, and
--           comes ahead of every look. The arms cannot differ because of the dial, so an identical pair there says
--           nothing about it, and the window's remaining pairs would repeat it.
--         - `no_effect` now means the dial was read and the arms were identical.
--         - The verdict carries `dial_reads` (witnessed, unread, unmeasured).
--       The runner concludes a terminal verdict through the promoter, which records a verdict other than a win as
--       `concluded`, so an unread dial ends its experiment with its reason in the promotion ledger.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart TRUE ═══════════════════════════════════════════════════════════════════
--
--   No run or depot scope holds a value of the three dials outside the two arms of pair 95 (P2 measures it). So every
--   certification arm and every operator run reads the global value it read before, and the witness writes only a
--   setting. The arms of experiment 08262943 change. The dial floor moves, so pair 95 (whose arms could not read their
--   dial) no longer counts, and the experiment starts again from its first seed.

BEGIN;

-- ── P0: no pair in flight (0513's one probe): this file replaces the dial pair and the resolver every arm reads ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0533 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: what this file relies on, as measured ──
DO $premises$
DECLARE v_cap text; v_n int; v_def text; r record;
BEGIN
  IF to_regprocedure('public.ottoq_target_soc_cap(text,timestamp with time zone,uuid)') IS NOT NULL THEN
    RAISE EXCEPTION '0533 P2: the three-argument cap already exists';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'ottoq_dial_pair_ledger' AND column_name IN ('dial_read_a', 'dial_read_b')) THEN
    RAISE EXCEPTION '0533 P2: the ledger already carries a read witness';
  END IF;
  -- the cap reads its three dials at the global tier and nothing else
  v_cap := regexp_replace(pg_get_functiondef('public.ottoq_target_soc_cap(text,timestamp with time zone)'::regprocedure), '--[^\n]*', '', 'g');
  v_n := (SELECT count(*) FROM regexp_matches(v_cap, 'ottoq_policy_get\(NULL,', 'g'));
  IF v_n <> 3 OR v_cap ~ 'ottoq_policy_get\((?!NULL,)' THEN
    RAISE EXCEPTION '0533 P2: the cap reads % dial(s) at the global tier, or another tier, not the three measured', v_n;
  END IF;
  -- its seven callers call it once each, and no other function does
  FOR r IN SELECT p.oid::regprocedure::text AS sig,
                  (SELECT count(*) FROM regexp_matches(regexp_replace(p.prosrc, '--[^\n]*', '', 'g'), 'ottoq_target_soc_cap\(', 'g')) AS n
             FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
            WHERE ns.nspname IN ('public', 'ottoq', 'twin') AND p.proname <> 'ottoq_target_soc_cap'
              AND p.prosrc ~ 'ottoq_target_soc_cap\(' LOOP
    IF r.n <> 1 THEN RAISE EXCEPTION '0533 P2: % calls the cap % times, not once', r.sig, r.n; END IF;
  END LOOP;
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
       WHERE ns.nspname IN ('public', 'ottoq', 'twin') AND p.proname <> 'ottoq_target_soc_cap'
         AND p.prosrc ~ 'ottoq_target_soc_cap\(') <> 7 THEN
    RAISE EXCEPTION '0533 P2: the cap does not have the seven callers measured';
  END IF;
  -- no run or depot scope holds a value of the three dials, but the two arms of pair 95: the certification arms and
  -- the operator's runs read the global value before and after this file
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_params pp
              WHERE pp.param_key IN ('dcfc_target_soc_day', 'dcfc_target_soc_night', 'l2_target_soc')
                AND pp.scope_type <> 'global'
                AND NOT (pp.scope_type = 'run' AND pp.scope_id IN (SELECT l.run_a FROM public.ottoq_dial_pair_ledger l WHERE l.pair_id = 95
                                                                    UNION ALL
                                                                    SELECT l.run_b FROM public.ottoq_dial_pair_ledger l WHERE l.pair_id = 95))) THEN
    RAISE EXCEPTION '0533 P2: a run or depot scope other than pair 95''s arms sets a charge-target dial; forces_recert FALSE would not hold';
  END IF;
  -- the resolver returns the run tier first, in one statement this file extends
  v_def := pg_get_functiondef('public.ottoq_policy_get(uuid,text,numeric)'::regprocedure);
  IF position(E'   WHERE scope_type=''run'' AND scope_id=p_sim_run_id AND param_key=p_param_key;\n  IF v IS NOT NULL THEN RETURN v; END IF;' IN v_def) = 0
     OR position('DECLARE v numeric; v_depot uuid;' IN v_def) = 0 THEN
    RAISE EXCEPTION '0533 P2: the resolver''s run tier is not as measured';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0533_pre', 'function', f.sch, f.obj, pg_get_functiondef(f.sig::regprocedure), md5(pg_get_functiondef(f.sig::regprocedure))
  FROM (VALUES ('public', 'ottoq_target_soc_cap',               'public.ottoq_target_soc_cap(text,timestamp with time zone)'),
               ('public', 'ottoq_policy_get',                   'public.ottoq_policy_get(uuid,text,numeric)'),
               ('twin',   'ottoq_sim_start_charge_session',     'twin.ottoq_sim_start_charge_session(uuid,uuid,uuid,numeric,timestamp with time zone)'),
               ('twin',   'ottoq_sim_advance_charge_sessions',  'twin.ottoq_sim_advance_charge_sessions(uuid,timestamp with time zone)'),
               ('ottoq',  'ottoq_record_enacted_booking',       'ottoq.ottoq_record_enacted_booking(uuid,uuid,uuid,timestamp with time zone,uuid,timestamp with time zone,timestamp with time zone,text,text)'),
               ('public', 'ottoq_capture_charge_duration',      'public.ottoq_capture_charge_duration()'),
               ('public', 'ottoq_dial_pair',                    'public.ottoq_dial_pair(uuid,bigint,integer)'),
               ('public', 'ottoq_dial_experiment_verdict',      'public.ottoq_dial_experiment_verdict(uuid)')) AS f(sch, obj, sig);

-- ── (a) the cap, through the resolver's three tiers ──
CREATE FUNCTION public.ottoq_target_soc_cap(p_stall_type text, p_at timestamp with time zone, p_sim_run_id uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  -- The depot's ceiling for one plug at one moment. Distinct from
  -- ottoq_default_target_soc() (how full "full" is when nobody says otherwise) and
  -- from ottoq_topoff_threshold_soc() (how empty earns an offer), both fleet-wide on purpose.
  -- 0533 (G258): read through the resolver's run, depot and global tiers. It read the global tier alone, so a dial
  -- experiment's arm (run scope) and a promoted winner (depot scope) were never read.
  SELECT CASE
    WHEN p_stall_type = 'dcfc' AND NOT public.ottoq_is_depot_night(p_at)
      THEN public.ottoq_policy_get(p_sim_run_id, 'dcfc_target_soc_day',    90)
    WHEN p_stall_type = 'dcfc'
      THEN public.ottoq_policy_get(p_sim_run_id, 'dcfc_target_soc_night', 100)
    ELSE public.ottoq_policy_get(p_sim_run_id, 'l2_target_soc',           100)
  END;
$function$;

GRANT EXECUTE ON FUNCTION public.ottoq_target_soc_cap(text, timestamp with time zone, uuid) TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.ottoq_target_soc_cap(text, timestamp with time zone, uuid) IS
  '0533 (G258). The depot''s ceiling for one plug at one moment (dcfc day, dcfc night, l2), read through ottoq_policy_get''s '
  'run, depot and global tiers. The session start, its every-tick advance, the booking''s stop target and the duration '
  'evidence pass their run; NULL reads the global value.';

CREATE OR REPLACE FUNCTION public.ottoq_target_soc_cap(p_stall_type text, p_at timestamp with time zone)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  -- 0533 (G258): the ceiling at the run in scope, which every tick pins to its run (ottoq_sim_advance_tick). It read
  -- the global value only. Outside a run the run is NULL and this reads the global value, as it always did.
  SELECT public.ottoq_target_soc_cap(p_stall_type, p_at, ottoq.ottoq_active_sim_run_id());
$function$;

-- ── (b) the four callers that hold their run pass it ──
DO $callers$
DECLARE
  v_def text; n int; r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('twin.ottoq_sim_start_charge_session(uuid,uuid,uuid,numeric,timestamp with time zone)',
       'public.ottoq_target_soc_cap(v_stall.stall_type::TEXT, COALESCE(p_sim_clock_now, NOW()))',
       'public.ottoq_target_soc_cap(v_stall.stall_type::TEXT, COALESCE(p_sim_clock_now, NOW()), p_sim_run_id)'),
      ('twin.ottoq_sim_advance_charge_sessions(uuid,timestamp with time zone)',
       'public.ottoq_target_soc_cap(v_session.stall_type::TEXT, v_session.started_at)',
       'public.ottoq_target_soc_cap(v_session.stall_type::TEXT, v_session.started_at, p_sim_run_id)'),
      ('ottoq.ottoq_record_enacted_booking(uuid,uuid,uuid,timestamp with time zone,uuid,timestamp with time zone,timestamp with time zone,text,text)',
       'public.ottoq_target_soc_cap(v_ctype, v_from)',
       'public.ottoq_target_soc_cap(v_ctype, v_from, p_sim_run_id)'),
      ('public.ottoq_capture_charge_duration()',
       'public.ottoq_target_soc_cap(v_stype, NEW.started_at)',
       'public.ottoq_target_soc_cap(v_stype, NEW.started_at, NEW.sim_run_id)')) AS t(sig, old, new) LOOP
    v_def := pg_get_functiondef(r.sig::regprocedure);
    n := (length(v_def) - length(replace(v_def, r.old, ''))) / length(r.old);
    IF n <> 1 THEN RAISE EXCEPTION '0533 (b): the cap call in % matched % times, not once', r.sig, n; END IF;
    EXECUTE replace(v_def, r.old, r.new);
  END LOOP;
END $callers$;

-- ── (c) the read witness: the resolver notes each run-scoped value it returns ──
DO $witness$
DECLARE
  v_def text; n int;
  v_old1 text := 'DECLARE v numeric; v_depot uuid;';
  v_new1 text := 'DECLARE v numeric; v_depot uuid; v_seen text;';
  v_old2 text := E'   WHERE scope_type=''run'' AND scope_id=p_sim_run_id AND param_key=p_param_key;\n  IF v IS NOT NULL THEN RETURN v; END IF;';
  v_new2 text := $n$   WHERE scope_type='run' AND scope_id=p_sim_run_id AND param_key=p_param_key;
  IF v IS NOT NULL THEN
    -- 0533 (G258): the read witness. A dial pair asks, after each arm, whether the arm read its own run-scoped value of
    -- the dial at all: a dial nothing reads at run scope cannot make two arms differ. One entry per run and key, in a
    -- transaction-local setting, so it costs nothing outside the run tier and leaves with the transaction.
    v_seen := COALESCE(current_setting('ottoq.run_scope_reads', true), '');
    IF strpos(v_seen, ',' || p_sim_run_id::text || ':' || p_param_key || ',') = 0 THEN
      PERFORM set_config('ottoq.run_scope_reads',
                         CASE WHEN v_seen = '' THEN ',' ELSE v_seen END || p_sim_run_id::text || ':' || p_param_key || ',', true);
    END IF;
    RETURN v;
  END IF;$n$;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_policy_get(uuid,text,numeric)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, v_old1, ''))) / length(v_old1);
  IF n <> 1 THEN RAISE EXCEPTION '0533 (c): the declaration matched % times, not once', n; END IF;
  n := (length(v_def) - length(replace(v_def, v_old2, ''))) / length(v_old2);
  IF n <> 1 THEN RAISE EXCEPTION '0533 (c): the run tier matched % times, not once', n; END IF;
  EXECUTE replace(replace(v_def, v_old1, v_new1), v_old2, v_new2);
END $witness$;

ALTER TABLE public.ottoq_dial_pair_ledger
  ADD COLUMN dial_read_a boolean,
  ADD COLUMN dial_read_b boolean;

COMMENT ON COLUMN public.ottoq_dial_pair_ledger.dial_read_a IS
  '0533 (G258). Whether the control arm read its own run-scoped value of the experiment''s dial at least once between its '
  'first and last tick (ottoq_policy_get''s read witness). NULL: the pair ran before 0533 and nothing witnessed it.';
COMMENT ON COLUMN public.ottoq_dial_pair_ledger.dial_read_b IS
  '0533 (G258). As dial_read_a, for the treatment arm. A pair where both are false cannot differ because of the dial, '
  'and the verdict names it dial_not_read.';

-- ── (c, continued) the dial pair clears the witness before each arm's ticks and records it after them ──
DO $pair$
DECLARE
  v_def text; v_new text; n int; i int;
  p text[][] := ARRAY[
    ARRAY[E'  v_pair bigint; v_vstatus text;\n',
          E'  v_pair bigint; v_vstatus text;\n  v_reads boolean[] := ''{}'';   -- 0533 (G258): whether each arm read its own value of the dial\n'],
    ARRAY[E'    v_t0 := clock_timestamp();\n    LOOP\n',
          E'    -- 0533 (G258): the read witness covers the engine''s ticks alone -- cleared here, after the boot fingerprint, and\n'
          || E'    -- read after the last tick, before the arm is scored\n'
          || E'    PERFORM set_config(''ottoq.run_scope_reads'', '''', true);\n'
          || E'    v_t0 := clock_timestamp();\n    LOOP\n'],
    ARRAY[E'      PERFORM public.ottoq_sim_advance_tick(v_run);\n    END LOOP;\n',
          E'      PERFORM public.ottoq_sim_advance_tick(v_run);\n    END LOOP;\n'
          || E'    v_reads := v_reads || (strpos(COALESCE(current_setting(''ottoq.run_scope_reads'', true), ''''),\n'
          || E'                                  '','' || v_run::text || '':'' || x.param_key || '','') > 0);\n'],
    ARRAY[E'     differs, moved, metrics_a, metrics_b, delta, wall_s)\n',
          E'     differs, moved, metrics_a, metrics_b, delta, wall_s, dial_read_a, dial_read_b)\n'],
    ARRAY[E'          COALESCE((v_m[1]->>''wall_s'')::numeric, 0) + COALESCE((v_m[2]->>''wall_s'')::numeric, 0))\n  RETURNING pair_id INTO v_pair;',
          E'          COALESCE((v_m[1]->>''wall_s'')::numeric, 0) + COALESCE((v_m[2]->>''wall_s'')::numeric, 0),\n'
          || E'          v_reads[1], v_reads[2])\n  RETURNING pair_id INTO v_pair;'],
    ARRAY[E'''both_paid_shield'', v_paid, ''moved'', v_moved)::text',
          E'''both_paid_shield'', v_paid, ''moved'', v_moved,\n'
          || E'                                               ''dial_read'', jsonb_build_object(''control'', v_reads[1], ''treatment'', v_reads[2]))::text'],
    ARRAY[E'    ''both_paid_shield'', v_paid, ''differs'', v_differs, ''moved'', v_moved,\n',
          E'    ''both_paid_shield'', v_paid, ''differs'', v_differs, ''moved'', v_moved,\n'
          || E'    ''dial_read'', jsonb_build_object(''control'', v_reads[1], ''treatment'', v_reads[2]),\n']];
BEGIN
  v_def := pg_get_functiondef('public.ottoq_dial_pair(uuid,bigint,integer)'::regprocedure);
  v_new := v_def;
  FOR i IN 1 .. array_length(p, 1) LOOP
    n := (length(v_new) - length(replace(v_new, p[i][1], ''))) / length(p[i][1]);
    IF n <> 1 THEN RAISE EXCEPTION '0533 (c): dial pair patch % matched % times, not once', i, n; END IF;
    v_new := replace(v_new, p[i][1], p[i][2]);
  END LOOP;
  EXECUTE v_new;
END $pair$;

-- ── (d) the verdict names an unread dial ──
DO $verdict$
DECLARE
  v_def text; v_new text; n int; i int;
  p text[][] := ARRAY[
    ARRAY[E'  v_outcome text; v_terminal boolean := true; v_why text;\n',
          E'  v_outcome text; v_terminal boolean := true; v_why text;\n'
          || E'  v_unread int := 0; v_witnessed int := 0; v_unmeasured int := 0;   -- 0533 (G258): the arms'' read witness\n'],
    ARRAY[E'    FROM public.ottoq_dial_counted_pairs(p_experiment_id, v_floor) c;\n',
          E'    FROM public.ottoq_dial_counted_pairs(p_experiment_id, v_floor) c;\n\n'
          || E'  -- 0533 (G258): whether each counted pair''s arms READ their own value of the dial. Neither arm reading it means\n'
          || E'  -- the arms cannot differ because of it; NULL is a pair from before the witness.\n'
          || E'  SELECT count(*) FILTER (WHERE l.dial_read_a IS FALSE AND l.dial_read_b IS FALSE),\n'
          || E'         count(*) FILTER (WHERE l.dial_read_a AND l.dial_read_b),\n'
          || E'         count(*) FILTER (WHERE l.dial_read_a IS NULL OR l.dial_read_b IS NULL)\n'
          || E'    INTO v_unread, v_witnessed, v_unmeasured\n'
          || E'    FROM public.ottoq_dial_counted_pairs(p_experiment_id, v_floor) c\n'
          || E'    JOIN public.ottoq_dial_pair_ledger l ON l.pair_id = c.pair_id;\n'],
    ARRAY[E'  ELSIF v_look IS NULL THEN\n    v_outcome := ''collecting''; v_terminal := false;\n',
          E'  ELSIF v_unread > 0 THEN\n'
          || E'    -- 0533 (G258): ahead of every look. A pair whose arms never read the dial cannot say what the dial does.\n'
          || E'    v_outcome := ''dial_not_read'';\n'
          || E'    v_why := format(''in %s of %s counted pair(s) neither arm read its own value of %s while it ran, so the arms could not differ because of it: '
          || E'either nothing reads the dial at run scope (G258: the charge-target cap read only the global value) or nothing that reads it ran in this world. '
          || E'An identical pair here is not evidence of no effect'', v_unread, v_counted, x.param_key);\n'
          || E'  ELSIF v_look IS NULL THEN\n    v_outcome := ''collecting''; v_terminal := false;\n'],
    ARRAY[E'    v_why := format(''both arms of each of the first %s counted pairs are byte-identical on every atom: the dial changes nothing in this world'', v_look);',
          E'    v_why := format(''both arms of each of the first %s counted pairs are byte-identical on every atom: the dial changes nothing in this world '
          || E'(read by both arms in %s of %s counted pairs; %s ran before 0533 could witness a read)'', v_look, v_witnessed, v_counted, v_unmeasured);'],
    ARRAY[E'    ''look_pairs'', v_pairs);',
          E'    ''dial_reads'', jsonb_build_object(''witnessed'', v_witnessed, ''unread'', v_unread, ''unmeasured'', v_unmeasured),   -- 0533 (G258)\n'
          || E'    ''look_pairs'', v_pairs);']];
BEGIN
  v_def := pg_get_functiondef('public.ottoq_dial_experiment_verdict(uuid)'::regprocedure);
  v_new := v_def;
  FOR i IN 1 .. array_length(p, 1) LOOP
    n := (length(v_new) - length(replace(v_new, p[i][1], ''))) / length(p[i][1]);
    IF n <> 1 THEN RAISE EXCEPTION '0533 (d): verdict patch % matched % times, not once', i, n; END IF;
    v_new := replace(v_new, p[i][1], p[i][2]);
  END LOOP;
  EXECUTE v_new;
END $verdict$;

DO $verify$
DECLARE v_two text; v_three text; v_get text; v_pair text; v_verdict text; r record;
BEGIN
  -- V1 (read with comments stripped: a call a comment swallowed would still be found in the raw text)
  v_two     := regexp_replace(pg_get_functiondef('public.ottoq_target_soc_cap(text,timestamp with time zone)'::regprocedure), '--[^\n]*', '', 'g');
  v_three   := regexp_replace(pg_get_functiondef('public.ottoq_target_soc_cap(text,timestamp with time zone,uuid)'::regprocedure), '--[^\n]*', '', 'g');
  v_get     := regexp_replace(pg_get_functiondef('public.ottoq_policy_get(uuid,text,numeric)'::regprocedure), '--[^\n]*', '', 'g');
  v_pair    := regexp_replace(pg_get_functiondef('public.ottoq_dial_pair(uuid,bigint,integer)'::regprocedure), '--[^\n]*', '', 'g');
  v_verdict := regexp_replace(pg_get_functiondef('public.ottoq_dial_experiment_verdict(uuid)'::regprocedure), '--[^\n]*', '', 'g');
  -- the cap reads no tier by NULL any more; the two-argument form reads the run in scope
  IF v_two ~ 'ottoq_policy_get\(' OR v_three ~ 'ottoq_policy_get\(NULL'
     OR position('public.ottoq_target_soc_cap(p_stall_type, p_at, ottoq.ottoq_active_sim_run_id())' IN v_two) = 0
     OR (SELECT count(*) FROM regexp_matches(v_three, 'ottoq_policy_get\(p_sim_run_id,', 'g')) <> 3 THEN
    RAISE EXCEPTION '0533 V1: the cap is not as intended';
  END IF;
  -- the four callers pass their run; the other three read the run in scope
  FOR r IN SELECT * FROM (VALUES
      ('twin.ottoq_sim_start_charge_session(uuid,uuid,uuid,numeric,timestamp with time zone)', 'COALESCE(p_sim_clock_now, NOW()), p_sim_run_id)'),
      ('twin.ottoq_sim_advance_charge_sessions(uuid,timestamp with time zone)', 'v_session.started_at, p_sim_run_id)'),
      ('ottoq.ottoq_record_enacted_booking(uuid,uuid,uuid,timestamp with time zone,uuid,timestamp with time zone,timestamp with time zone,text,text)', 'v_from, p_sim_run_id)'),
      ('public.ottoq_capture_charge_duration()', 'NEW.started_at, NEW.sim_run_id)')) AS t(sig, call) LOOP
    IF position('public.ottoq_target_soc_cap(' IN regexp_replace(pg_get_functiondef(r.sig::regprocedure), '--[^\n]*', '', 'g')) = 0
       OR position(r.call IN regexp_replace(pg_get_functiondef(r.sig::regprocedure), '--[^\n]*', '', 'g')) = 0 THEN
      RAISE EXCEPTION '0533 V1: % does not pass its run to the cap', r.sig;
    END IF;
  END LOOP;
  -- the witness is written at the run tier, cleared before an arm's ticks, read after them, and ledgered
  IF position('PERFORM set_config(''ottoq.run_scope_reads'',' IN v_get) = 0
     OR position('PERFORM set_config(''ottoq.run_scope_reads'', '''', true);' IN v_pair) = 0
     OR position('PERFORM set_config(''ottoq.run_scope_reads'', '''', true);' IN v_pair)
          < position('v_boot := public.ottoq_boot_state_fingerprint' IN v_pair)
     OR position('PERFORM set_config(''ottoq.run_scope_reads'', '''', true);' IN v_pair)
          > position('PERFORM public.ottoq_sim_advance_tick(v_run);' IN v_pair)
     OR position('v_reads := v_reads ||' IN v_pair) < position('PERFORM public.ottoq_sim_advance_tick(v_run);' IN v_pair)
     OR position('v_reads := v_reads ||' IN v_pair) > position('v_h := public.ottoq_ab_arm_atoms' IN v_pair)
     OR position('wall_s, dial_read_a, dial_read_b)' IN v_pair) = 0
     OR position('v_reads[1], v_reads[2])' IN v_pair) = 0 THEN
    RAISE EXCEPTION '0533 V1: the witness is not written, cleared, read or ledgered as intended';
  END IF;
  -- the verdict names an unread dial before any look
  IF position('v_outcome := ''dial_not_read'';' IN v_verdict) = 0
     OR position('ELSIF v_unread > 0 THEN' IN v_verdict) > position('ELSIF v_look IS NULL THEN' IN v_verdict)
     OR position('''dial_reads''' IN v_verdict) = 0 THEN
    RAISE EXCEPTION '0533 V1: the verdict does not name an unread dial as intended';
  END IF;
END $verify$;

-- This file's own classification goes in before V3 (0523's rule).
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0533_the_charge_target_an_arm_is_given_is_the_one_it_charges_to', false, true,
  'G258: ottoq_target_soc_cap reads the run in scope (run, depot, global) instead of the global value alone, the four '
  'callers holding a run pass it, the resolver witnesses run-scoped reads, the dial pair ledgers whether each arm read its '
  'dial, and the verdict names an unread dial. No run or depot scope held a charge-target value outside pair 95''s arms, '
  'so certification arms and operator runs read what they read before; experiment 08262943''s arms change.', now())
ON CONFLICT (name) DO NOTHING;

-- V3, rolled back.
--   (a) The cap at each tier, on pair 95's own arms, which hold dcfc_target_soc_day at run scope (90 control, 85 treatment):
--       - 85 for the treatment's run and 90 for the control's at 10 AM CT;
--       - 90 with no run;
--       - 100 at 3 AM CT (the arms set only the day value);
--       - 100 for an L2 plug;
--       - the two-argument form reads 85 with the treatment's run pinned, and 90 with 'none'.
--   (b) The witness: a global read and a run read with no run-scoped row leave it empty. Two reads of one run-scoped
--       value, then a read of the other arm's through the cap, leave exactly one entry each, in order.
--   (c) The verdict: a planted experiment with one counted pair whose arms did not read the dial is `dial_not_read`,
--       terminal. The same pair witnessed is `collecting`, with the witness counted.
--   The dial pair itself runs 20 minutes and is this file's check (db/checks/0399 §1): a pair of 08262943 after the apply.
DO $v3$
DECLARE
  v_msg text; v_a uuid; v_b uuid; v_day timestamptz := '2026-09-01 15:00:00+00'; v_night timestamptz := '2026-09-01 08:00:00+00';
  c numeric[]; w1 text; w2 text; v_x uuid; v_pair bigint; v1 jsonb; v2 jsonb;
BEGIN
  BEGIN
    SELECT run_a, run_b INTO v_a, v_b FROM public.ottoq_dial_pair_ledger WHERE pair_id = 95;
    IF v_a IS NULL OR v_b IS NULL THEN RAISE EXCEPTION '0533 V3 FAILED: pair 95 is not in the ledger'; END IF;

    -- (a) the tiers
    c := ARRAY[public.ottoq_target_soc_cap('dcfc', v_day, v_b), public.ottoq_target_soc_cap('dcfc', v_day, v_a),
               public.ottoq_target_soc_cap('dcfc', v_day, NULL), public.ottoq_target_soc_cap('dcfc', v_night, v_b),
               public.ottoq_target_soc_cap('l2', v_day, v_b)];
    PERFORM set_config('ottoq.sim_run_id', v_b::text, true);
    c := c || public.ottoq_target_soc_cap('dcfc', v_day);
    PERFORM set_config('ottoq.sim_run_id', 'none', true);
    c := c || public.ottoq_target_soc_cap('dcfc', v_day);
    IF c IS DISTINCT FROM ARRAY[85, 90, 90, 100, 100, 85, 90]::numeric[] THEN
      RAISE EXCEPTION '0533 V3 FAILED (a): treatment, control, no run, night, l2, pinned, none read %, not {85,90,90,100,100,85,90}', c;
    END IF;

    -- (b) the witness
    PERFORM set_config('ottoq.run_scope_reads', '', true);
    PERFORM public.ottoq_policy_get(NULL, 'dcfc_target_soc_day', 90);
    PERFORM public.ottoq_policy_get(v_b, 'dcfc_target_soc_night', 100);
    w1 := current_setting('ottoq.run_scope_reads', true);
    PERFORM public.ottoq_policy_get(v_b, 'dcfc_target_soc_day', 90);
    PERFORM public.ottoq_policy_get(v_b, 'dcfc_target_soc_day', 90);
    PERFORM public.ottoq_target_soc_cap('dcfc', v_day, v_a);
    w2 := current_setting('ottoq.run_scope_reads', true);
    IF COALESCE(w1, '') <> '' OR w2 IS DISTINCT FROM (',' || v_b || ':dcfc_target_soc_day,' || v_a || ':dcfc_target_soc_day,') THEN
      RAISE EXCEPTION '0533 V3 FAILED (b): the witness read % after reads with no run-scoped row, and % after the run-scoped reads', w1, w2;
    END IF;

    -- (c) the verdict, on a planted experiment and one counted pair
    INSERT INTO public.ottoq_dial_experiments (created_by, depot_id, param_key, control_value, treatment_value, scenario, ticks,
                                               sim_start, primary_metric, primary_better, hypothesis, sim_min_per_tick)
    VALUES ('0533_v3', '11111111-1111-1111-1111-111111111111', 'l2_target_soc', 100, 95, 'busy_day', 90,
            '2026-09-01 13:00:00+00', 'unmet_demand_car_hours', 'lower', '0533 V3 plant', 6)
    RETURNING experiment_id INTO v_x;
    INSERT INTO public.ottoq_dial_pair_ledger (experiment_id, seed, engine_hash, ran_at, run_a, run_b, ab_group_id, complete,
                                               world_identical, both_paid_shield, differs, moved, metrics_a, metrics_b, delta,
                                               wall_s, dial_read_a, dial_read_b)
    VALUES (v_x, 533, '0533_v3', public.ottoq_dial_pair_floor() + interval '1 second', v_a, v_b, gen_random_uuid(), true, true, true,
            false, '[]'::jsonb, '{"unmet_demand_car_hours": 336.3}'::jsonb, '{"unmet_demand_car_hours": 336.3}'::jsonb, '{}'::jsonb,
            0, false, false)
    RETURNING pair_id INTO v_pair;
    v1 := public.ottoq_dial_experiment_verdict(v_x);
    UPDATE public.ottoq_dial_pair_ledger SET dial_read_a = true, dial_read_b = true WHERE pair_id = v_pair;
    v2 := public.ottoq_dial_experiment_verdict(v_x);
    IF v1->>'outcome' IS DISTINCT FROM 'dial_not_read' OR NOT COALESCE((v1->>'terminal')::boolean, false)
       OR (v1->'dial_reads'->>'unread')::int IS DISTINCT FROM 1
       OR v2->>'outcome' IS DISTINCT FROM 'collecting' OR COALESCE((v2->>'terminal')::boolean, true)
       OR (v2->'dial_reads'->>'witnessed')::int IS DISTINCT FROM 1 THEN
      RAISE EXCEPTION '0533 V3 FAILED (c): unread: % (terminal %, reads %); witnessed: % (terminal %, reads %)',
        v1->>'outcome', v1->>'terminal', v1->'dial_reads', v2->>'outcome', v2->>'terminal', v2->'dial_reads';
    END IF;

    RAISE EXCEPTION '0533 V3 PASSED: the cap reads % across treatment, control, no run, night, l2, pinned and none; the witness reads % after two arms'' reads; an unread pair is % (terminal), the same pair witnessed is %: %',
      c, w2, v1->>'outcome', v2->>'outcome', v1->>'why';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0533 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0533 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: EXECUTE the eight `definition`s in ottoq_schema_snapshots WHERE label = '0533_pre' as they are; then
--   DROP FUNCTION public.ottoq_target_soc_cap(text, timestamp with time zone, uuid);
--   ALTER TABLE public.ottoq_dial_pair_ledger DROP COLUMN dial_read_a, DROP COLUMN dial_read_b.
COMMIT;
