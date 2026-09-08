-- migration-version: PENDING
-- migration-name:    provenance_asks_the_depot_not_the_run_id
-- ---------------------------------------------------------------------------
-- 0228 — G16. The state-change triggers decide whether an event is production
--        or twin by asking whether a run id happened to be set. They should
--        ask the depot, which is what 0073 already decided for the SDR emitter
--        and never propagated here.
--
-- forces_recert: FALSE, provable rather than asserted — and the proof is
-- narrower than 0224's, deliberately. P1 isolates the `h_evt` EXPRESSION out of
-- the live `ottoq_determinism_pair` and asserts that it names neither
-- `data_source` nor `depot_id`. Read from the catalog while drafting, h_evt
-- hashes exactly three things — event_type, entity_id (blanked for
-- ocpp_session / service_detail_record / sim_run) and sim_clock_at — scoped by
-- sim_run_id. Neither column this migration writes is among them.
--
-- Narrower than 0224's because a whole-function grep for `depot_id` returns
-- TRUE on this function for reasons that have nothing to do with h_evt: it
-- carries `p_depot` and the 0175 scenario guard. An assertion that fails for
-- the wrong reason is no better than one that passes for the wrong reason, and
-- the first draft of P1 did both — it looked for a function called
-- `ottoq_hash_events`, which does not exist. Found by dry-running P1 read-only
-- before applying; recorded here rather than quietly corrected.
--
-- THE DEFECT (db/checks/0131, G16). Both state-change triggers write
--
--     p_data_source := CASE WHEN v_run IS NULL THEN 'production' ELSE 'twin' END
--
-- at four sites. During certification, `ottoq_sim_stop_and_reset` leaves the
-- run-id GUC unset and the next arm's FIRST act is a fleet reset, before
-- `sim_start_run` points the GUC at the new run. So the reset's own writes see
-- v_run NULL and are stamped `production` — work the harness did, on a
-- sim-feed depot, asserting it came from the real world, under an HMAC
-- signature that attests to the lie as firmly as it would to the truth.
--
-- Measured: **116 extra `vehicle.state_changed` events on arm A's run per
-- pair**, and 27,460 such rows live today, of which **27,440 come from the
-- vehicles trigger**.
--
-- WHY THIS FIX AND NOT THE TWO 0131 COSTED. 0131 offered FIX 1 (a
-- transaction-local GUC telling the triggers to stay silent during a reset)
-- and FIX 2 (re-point the reset so its events land in the new run's scope). It
-- also wrote down FIX 1's hazard before anyone implemented it: the flag would
-- be read by the triggers on EVERY write to `vehicles` and `stalls`,
-- production included, so a flag left set silences the entire state-change
-- stream for the rest of the transaction — silently, because an absent event
-- has no signature to fail. A strictly worse failure than the one being fixed.
-- And FIX 2 moves `h_evt` on every column, which is legitimate but expensive.
--
-- There is a third, and it is not new — it is 0073's, unpropagated. 0073 found
-- the SDR emitter deriving `data_source` from whether a run id was passed, and
-- fixed it by reading the thing that actually knows:
--
--     CASE WHEN d.feed_mode = 'external' THEN 'production' ELSE 'twin' END
--
-- The state-change triggers were never given the same treatment. Applying it
-- here needs no suppression flag, so FIX 1's hazard does not exist; and it
-- changes no event's run scope, so FIX 2's canon movement does not happen.
--
-- BLAST RADIUS, MEASURED, over all 1,823,428 state-change events:
--
--     depot feed_mode   null-run 'production'   with a run
--     external                             0             1
--     sim                                 20       674,889
--     (no depot recorded)             27,440     1,121,078
--
-- Every row with a run is already `twin` and stays `twin`. The rows that change
-- are exactly the null-run ones on a non-external depot — G16's rows, and
-- nothing else. The one `external` row carries a run and is discussed in P2.
--
-- PART B, AND WHY IT IS IN THE SAME FILE. That third line of the table — 27,440
-- events with NO DEPOT AT ALL — is the vehicles trigger, which passes
-- `p_fleet_operator_id` and never `p_depot_id`. So "what happened at the
-- flagship depot" is unanswerable from the event stream for vehicle events,
-- which is a provenance hole in its own right. This migration has to resolve
-- the vehicle's depot anyway in order to read its feed mode; recording what it
-- found costs nothing, and NOT recording it would mean editing this exact
-- argument list while leaving the hole open. It is hash-neutral for the same
-- reason Part A is, and A3 asserts it separately so the two are not entangled.
--
-- COST. One `depots` lookup per emitted event, on a five-row table by primary
-- key, inside a trigger that is already calling `ottoq_record_event` — a write.
-- The lookup happens only when an event is actually emitted: both triggers
-- return early on pure-timestamp churn (the 0015 filter), which is 80.9% of
-- vehicle updates.
--
-- THE REWRITE WAS DIFFED AGAINST THE LIVE BODIES, STATEMENT BY STATEMENT.
-- Unlike 0223/0224/0225, which patch by anchored substitution, this file
-- retypes two whole function bodies — so a dropped line would be a live defect
-- on every write to `vehicles` and `stalls`, and no assertion in this file
-- would notice, because the assertions check what was ADDED.
--
-- So before applying: both bodies were read from `pg_proc.prosrc`, comments
-- and indentation stripped from each side, and diffed. The complete set of
-- differences, 2026-09-08 14:58 UTC:
--
--   stalls    + v_data_source TEXT;
--             + the feed_mode SELECT and its COALESCE fallback
--             ~ p_data_source, at both call sites
--
--   vehicles  + v_depot UUID; + v_data_source TEXT;
--             + v_depot := COALESCE(NEW.current_depot_id, NEW.home_depot_id);
--             + the feed_mode SELECT and its COALESCE fallback
--             + p_depot_id := v_depot, at both call sites   (Part B)
--             ~ p_data_source, at both call sites           (Part A)
--
-- Nothing else. And because that diff strips comments, the 0015 block in the
-- vehicles trigger was checked separately and survives verbatim — its banner,
-- the 56,544-of-69,917 measurement, the 80.9%, the `current_soc` caveat and
-- the fold-forward note. That block explains why 80.9% of vehicle updates emit
-- no event; losing it would cost the next reader a day.
--
-- WHAT THIS DOES NOT FIX, restated from 0131 because it stays true: the 27,460
-- rows already written. They are signed and the signature covers the mislabel.
-- Re-labelling invalidates the signature; deleting is a deletion from an audit
-- ledger. That is Chase's call and belongs on the founder list, not here.
-- ---------------------------------------------------------------------------

DO $mig$
DECLARE
  v_veh      text;
  v_stl      text;
  v_pin_veh  constant text := '9ccac3646177a01a141f9c9cc3f39ba7';
  v_pin_stl  constant text := '84d622c64695d639091df84f099c96cc';
  v_pair     text;
  v_evt      text;
  v_n        int;
  v_old      constant text := $a$CASE WHEN v_run IS NULL THEN 'production' ELSE 'twin' END$a$;
  v_new      constant text := $a$v_data_source$a$;
BEGIN
  ------------------------------------------------------------------ P- ------
  IF EXISTS (SELECT 1 FROM pg_stat_activity
              WHERE query ILIKE '%ottoq_determinism_pair%' AND state='active'
                AND pid <> pg_backend_pid()) THEN
    RAISE EXCEPTION '0228 P-: a determinism pair is active right now';
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname ~ '^r[0-9]+_' AND active) THEN
    RAISE EXCEPTION '0228 P-: certification jobs are still scheduled (%)',
      (SELECT string_agg(jobname, ', ') FROM cron.job
        WHERE jobname ~ '^r[0-9]+_' AND active);
  END IF;

  ------------------------------------------------------------------ P0 ------
  SELECT pg_get_functiondef(p.oid) INTO v_veh FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_vehicles_state_change';
  SELECT pg_get_functiondef(p.oid) INTO v_stl FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_stalls_state_change';
  IF md5(v_veh) <> v_pin_veh THEN
    RAISE EXCEPTION '0228 P0: vehicles trigger is %, expected %', md5(v_veh), v_pin_veh;
  END IF;
  IF md5(v_stl) <> v_pin_stl THEN
    RAISE EXCEPTION '0228 P0: stalls trigger is %, expected %', md5(v_stl), v_pin_stl;
  END IF;
  IF (length(v_veh) - length(replace(v_veh, v_old, ''))) / length(v_old) <> 2 THEN
    RAISE EXCEPTION '0228 P0: expected the run-id CASE exactly twice in the '
                    'vehicles trigger (INSERT and UPDATE), found %',
      (length(v_veh) - length(replace(v_veh, v_old, ''))) / length(v_old);
  END IF;
  IF (length(v_stl) - length(replace(v_stl, v_old, ''))) / length(v_old) <> 2 THEN
    RAISE EXCEPTION '0228 P0: expected the run-id CASE exactly twice in the '
                    'stalls trigger, found %',
      (length(v_stl) - length(replace(v_stl, v_old, ''))) / length(v_old);
  END IF;

  ------------------------------------------------------------------ P1 ------
  -- forces_recert FALSE, proven on the h_evt EXPRESSION rather than on the
  -- whole function.
  --
  -- The first draft of this block looked for a function called
  -- `ottoq_hash_events`, fell back to grepping the whole body of
  -- ottoq_determinism_pair for `data_source`, and this file's header then
  -- claimed it asserted `depot_id` too. Three things wrong with that, all
  -- found by dry-running it read-only before applying:
  --
  --   * there is no ottoq_hash_events -- h_evt is computed inline;
  --   * the header's depot_id claim was simply untrue, P1 never checked it;
  --   * and a whole-body grep for `depot_id` returns TRUE anyway, because
  --     ottoq_determinism_pair carries `p_depot` and the 0175 scenario guard.
  --     It would have failed for a reason that has nothing to do with h_evt.
  --
  -- So the assertion is narrowed to the fragment that actually computes the
  -- atom. Read from the live catalog, 2026-09-08 14:42 UTC, h_evt hashes
  -- exactly three things -- event_type, entity_id (blanked for ocpp_session /
  -- service_detail_record / sim_run) and sim_clock_at -- scoped by sim_run_id.
  -- Neither column this migration writes appears in it.
  SELECT pg_get_functiondef(p.oid) INTO v_pair FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_determinism_pair';
  IF v_pair IS NULL THEN
    RAISE EXCEPTION '0228 P1: ottoq_determinism_pair not found; forces_recert '
                    'FALSE must be proven against the live verdict, not assumed';
  END IF;

  v_evt := substring(v_pair from position($e$'h_evt',$e$ in v_pair)
                     for  position($e$'h_bkg',$e$ in v_pair)
                        - position($e$'h_evt',$e$ in v_pair));
  IF v_evt IS NULL OR length(v_evt) < 100 THEN
    RAISE EXCEPTION '0228 P1: could not isolate the h_evt expression (got % '
                    'chars). Do not fall back to grepping the whole function: '
                    'it carries p_depot and would answer about the wrong thing.',
                    COALESCE(length(v_evt), 0);
  END IF;

  IF v_evt ~* '\mdata_source\M' THEN
    RAISE EXCEPTION '0228 P1: the h_evt expression reads data_source, so Part A '
                    'DOES move a canon and forces_recert is wrong: %', v_evt;
  END IF;
  IF v_evt ~* '\mdepot_id\M' THEN
    RAISE EXCEPTION '0228 P1: the h_evt expression reads depot_id, so Part B '
                    'DOES move a canon and forces_recert is wrong: %', v_evt;
  END IF;
  -- And the positive half: the fragment isolated must be the real one. An
  -- empty or mis-sliced substring would satisfy both checks above by saying
  -- nothing, which is the failure mode of every negative assertion.
  IF v_evt NOT LIKE '%event_type%' OR v_evt NOT LIKE '%sim_clock_at%'
     OR v_evt NOT LIKE '%ottoq_events%' THEN
    RAISE EXCEPTION '0228 P1: the isolated fragment does not look like h_evt '
                    '(no event_type / sim_clock_at / ottoq_events). The two '
                    'checks above would have passed on nothing.';
  END IF;

  ------------------------------------------------------------------ P2 ------
  -- The one 'external' state-change event carries a run id. Under the old rule
  -- it was 'twin'; under the new one it becomes 'production'. That is the
  -- correct answer -- an external-feed depot is the real world whatever the
  -- twin is doing -- but it must not be a surprise, so it is counted here and
  -- refused if it is more than a handful.
  SELECT count(*) INTO v_n
    FROM public.ottoq_events e JOIN public.depots d ON d.id = e.depot_id
   WHERE e.event_type IN ('vehicle.state_changed','vehicle.created',
                          'stall.state_changed','stall.created')
     AND d.feed_mode = 'external' AND e.sim_run_id IS NOT NULL;
  IF v_n > 10 THEN
    RAISE EXCEPTION '0228 P2: % state-change events sit on an external-feed '
                    'depot WITH a sim run id. The new rule labels them '
                    'production where the old rule said twin, and at this '
                    'volume that is a decision, not a rounding: stop and '
                    'establish why the twin is running against an external '
                    'feed.', v_n;
  END IF;
  RAISE NOTICE '0228 P2: % external-feed state-change events carry a run id '
               '(they flip twin -> production, which is the correct answer)', v_n;

  ------------------------------------------------- part A + B, vehicles -----
  CREATE OR REPLACE FUNCTION public.ottoq_vehicles_state_change()
  RETURNS trigger
  LANGUAGE plpgsql
  SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
  AS $function$
  DECLARE
    v_payload      JSONB;
    v_diff         JSONB;
    v_actor_type   TEXT := COALESCE(NULLIF(current_setting('ottoq.actor_type', TRUE), ''), 'unknown');
    v_actor_id     TEXT := NULLIF(current_setting('ottoq.actor_id', TRUE), '');
    v_event_type   TEXT;
    v_run          UUID;
    v_depot        UUID;
    v_data_source  TEXT;
  BEGIN
    v_run := ottoq.ottoq_active_sim_run_id();

    -- 0228 (G16). Provenance is a property of the FEED, not of whether a run id
    -- happened to be set. The certification harness resets the fleet before
    -- sim_start_run points the GUC at the new run, so the old rule stamped 116
    -- events a pair 'production' about work the twin did. 0073 settled this for
    -- the SDR emitter -- feed_mode 'external' is the real world, everything else
    -- is the twin -- and this is that decision, propagated.
    --
    -- current_depot_id first, home_depot_id as the fallback: a deployed vehicle
    -- has no current depot and still belongs to one. If neither is set there is
    -- nothing to ask, and the old run-id rule is the honest default.
    v_depot := COALESCE(NEW.current_depot_id, NEW.home_depot_id);
    SELECT CASE WHEN d.feed_mode = 'external' THEN 'production' ELSE 'twin' END
      INTO v_data_source
      FROM public.depots d WHERE d.id = v_depot;
    v_data_source := COALESCE(
      v_data_source,
      CASE WHEN v_run IS NULL THEN 'production' ELSE 'twin' END);

    IF TG_OP = 'INSERT' THEN
      v_event_type := 'vehicle.created';
      v_payload := jsonb_build_object('new', to_jsonb(NEW));
      PERFORM ottoq_record_event(
        p_actor_type        := v_actor_type,
        p_actor_id          := v_actor_id,
        p_event_type        := v_event_type,
        p_entity_type       := 'vehicle',
        p_entity_id         := NEW.id,
        p_depot_id          := v_depot,   -- 0228 part B: was never passed
        p_fleet_operator_id := NEW.fleet_operator_id,
        p_payload           := v_payload,
        p_new_state         := to_jsonb(NEW),
        p_ingest_source     := 'trigger',
        p_data_source       := v_data_source,
        p_sim_run_id        := v_run
      );
      RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
      IF to_jsonb(OLD) = to_jsonb(NEW) THEN
        RETURN NEW;
      END IF;
      v_diff := ottoq_jsonb_diff(to_jsonb(OLD), to_jsonb(NEW));
      -- ══════════════════════════ 0015 ══════════════════════════
      -- Skip pure-timestamp churn: only clock columns moved, no state change.
      -- `last_state_change` ADDED. It is the timestamp OF a state change, and the twin
      -- stamps it on rows whose state did not move -- which is why 56,544 of 69,917
      -- `vehicle.state_changed` rows (80.9%) carried a diff of nothing but these three
      -- clock keys. An event asserting a state change in which nothing changed state is
      -- information-free, and dropping it cannot affect ottoq_event_new_state()'s
      -- fold-forward reconstruction, which only ever reads non-clock diff keys.
      -- `current_soc` is deliberately NOT in this list: SOC is real signal.
      IF NOT EXISTS (
        SELECT 1 FROM jsonb_object_keys(v_diff) AS k
         WHERE k <> ALL (ARRAY['updated_at','current_soc_updated_at','last_state_change'])
      ) THEN
        RETURN NEW;
      END IF;
      v_event_type := 'vehicle.state_changed';
      v_payload := jsonb_build_object('diff', v_diff);
      PERFORM ottoq_record_event(
        p_actor_type        := v_actor_type,
        p_actor_id          := v_actor_id,
        p_event_type        := v_event_type,
        p_entity_type       := 'vehicle',
        p_entity_id         := NEW.id,
        p_depot_id          := v_depot,   -- 0228 part B: was never passed
        p_fleet_operator_id := NEW.fleet_operator_id,
        p_payload           := v_payload,
        p_new_state         := to_jsonb(NEW),
        p_ingest_source     := 'trigger',
        p_data_source       := v_data_source,
        p_sim_run_id        := v_run
      );
      RETURN NEW;
    END IF;
    RETURN NEW;
  END;
  $function$;

  --------------------------------------------------- part A, stalls --------
  CREATE OR REPLACE FUNCTION public.ottoq_stalls_state_change()
  RETURNS trigger
  LANGUAGE plpgsql
  SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
  AS $function$
  DECLARE
    v_payload      JSONB;
    v_diff         JSONB;
    v_actor_type   TEXT := COALESCE(NULLIF(current_setting('ottoq.actor_type', TRUE), ''), 'unknown');
    v_actor_id     TEXT := NULLIF(current_setting('ottoq.actor_id', TRUE), '');
    v_event_type   TEXT;
    v_run          UUID;
    v_data_source  TEXT;
  BEGIN
    v_run := ottoq.ottoq_active_sim_run_id();

    -- 0228 (G16). See the vehicles trigger. A stall always carries its depot,
    -- so there is no COALESCE chain to walk -- but the same fallback is kept
    -- for the case where the depot row is missing, because a trigger that
    -- cannot answer should say what it used to say rather than say NULL.
    SELECT CASE WHEN d.feed_mode = 'external' THEN 'production' ELSE 'twin' END
      INTO v_data_source
      FROM public.depots d WHERE d.id = NEW.depot_id;
    v_data_source := COALESCE(
      v_data_source,
      CASE WHEN v_run IS NULL THEN 'production' ELSE 'twin' END);

    IF TG_OP = 'INSERT' THEN
      v_event_type := 'stall.created';
      PERFORM ottoq_record_event(
        p_actor_type    := v_actor_type,
        p_actor_id      := v_actor_id,
        p_event_type    := v_event_type,
        p_entity_type   := 'stall',
        p_entity_id     := NEW.id,
        p_depot_id      := NEW.depot_id,
        p_payload       := jsonb_build_object('new', to_jsonb(NEW)),
        p_new_state     := to_jsonb(NEW),
        p_ingest_source := 'trigger',
        p_data_source   := v_data_source,
        p_sim_run_id    := v_run
      );
      RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
      IF to_jsonb(OLD) = to_jsonb(NEW) THEN RETURN NEW; END IF;
      v_diff := ottoq_jsonb_diff(to_jsonb(OLD), to_jsonb(NEW));
      IF NOT EXISTS (
        SELECT 1 FROM jsonb_object_keys(v_diff) AS k
         WHERE k <> ALL (ARRAY['updated_at','reservation_expires_at','reserved_at'])
      ) THEN
        RETURN NEW;
      END IF;
      v_event_type := 'stall.state_changed';
      v_payload := jsonb_build_object('diff', v_diff);
      PERFORM ottoq_record_event(
        p_actor_type     := v_actor_type,
        p_actor_id       := v_actor_id,
        p_event_type     := v_event_type,
        p_entity_type    := 'stall',
        p_entity_id      := NEW.id,
        p_depot_id       := NEW.depot_id,
        p_payload        := v_payload,
        p_new_state      := to_jsonb(NEW),
        p_ingest_source  := 'trigger',
        p_data_source    := v_data_source,
        p_sim_run_id     := v_run
      );
      RETURN NEW;
    END IF;
    RETURN NEW;
  END;
  $function$;

  ------------------------------------------------------------------ A1 ------
  SELECT pg_get_functiondef(p.oid) INTO v_veh FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_vehicles_state_change';
  SELECT pg_get_functiondef(p.oid) INTO v_stl FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_stalls_state_change';

  -- The run-id CASE must survive EXACTLY ONCE in each body -- as the fallback,
  -- not as the rule. Zero would mean the fallback was lost; two would mean a
  -- call site was never converted.
  FOREACH v_pair IN ARRAY ARRAY[v_veh, v_stl] LOOP
    v_n := (length(v_pair) - length(replace(v_pair, v_old, ''))) / length(v_old);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0228 A1: the run-id CASE appears % times where 1 (the '
                      'fallback) was expected', v_n;
    END IF;
  END LOOP;
  IF (length(v_veh) - length(replace(v_veh, 'p_data_source       := v_data_source', ''))) = 0
     OR (length(v_stl) - length(replace(v_stl, 'p_data_source   := v_data_source', ''))) = 0 THEN
    RAISE EXCEPTION '0228 A1: a trigger is not passing v_data_source';
  END IF;
  IF v_veh NOT LIKE '%feed_mode%' OR v_stl NOT LIKE '%feed_mode%' THEN
    RAISE EXCEPTION '0228 A1: a trigger does not read depots.feed_mode';
  END IF;

  ------------------------------------------------------------------ A2 ------
  -- Part A, asserted on the RULE rather than by writing a probe row.
  --
  -- The first draft of this block did an UPDATE on `vehicles` inside a plpgsql
  -- BEGIN...END and its comment said "rolled back". It would not have been: a
  -- BEGIN...END with no EXCEPTION clause is not a subtransaction, so the write
  -- would have committed with the migration. A migration that writes to the
  -- fleet table to prove a point about labelling is a worse idea than the
  -- labelling defect, and the comment asserting otherwise is exactly the kind
  -- of thing this project keeps finding in other people's code.
  --
  -- So the rule is evaluated directly, against the live depot rows, with no
  -- write anywhere. Both directions, because either alone is satisfiable by a
  -- constant.
  IF (SELECT CASE WHEN d.feed_mode = 'external' THEN 'production' ELSE 'twin' END
        FROM public.depots d WHERE d.id = '11111111-1111-1111-1111-111111111111')
     IS DISTINCT FROM 'twin' THEN
    RAISE EXCEPTION '0228 A2: the flagship depot (feed_mode sim) does not map '
                    'to twin under the new rule';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.depots WHERE feed_mode = 'external') THEN
    RAISE EXCEPTION '0228 A2: no external-feed depot exists, so the rule''s '
                    'production branch is untested and this assertion would be '
                    'vacuous. Do not weaken it -- establish why the depot is gone.';
  END IF;
  IF (SELECT CASE WHEN d.feed_mode = 'external' THEN 'production' ELSE 'twin' END
        FROM public.depots d WHERE d.feed_mode = 'external' ORDER BY d.id LIMIT 1)
     IS DISTINCT FROM 'production' THEN
    RAISE EXCEPTION '0228 A2: an external-feed depot does not map to production';
  END IF;

  SELECT string_agg(DISTINCT format('%s -> %s', d.feed_mode,
           CASE WHEN d.feed_mode = 'external' THEN 'production' ELSE 'twin' END), ', ')
    INTO v_pair FROM public.depots d;
  RAISE NOTICE '0228 A2: the label each feed mode now produces: %', v_pair;

  ------------------------------------------------------------------ A3 ------
  -- Part B, asserted separately from Part A so the two are not entangled: the
  -- vehicles trigger now passes a depot where it passed none.
  IF v_veh NOT LIKE '%p_depot_id          := v_depot%' THEN
    RAISE EXCEPTION '0228 A3: the vehicles trigger still passes no depot id';
  END IF;
  IF (length(v_veh) - length(replace(v_veh, 'p_depot_id          := v_depot', '')))
     / length('p_depot_id          := v_depot') <> 2 THEN
    RAISE EXCEPTION '0228 A3: expected the depot passed at both sites (INSERT '
                    'and UPDATE) in the vehicles trigger';
  END IF;

  RAISE NOTICE '0228 applied: vehicles % -> %, stalls % -> %',
               v_pin_veh, md5(v_veh), v_pin_stl, md5(v_stl);
END $mig$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('provenance_asks_the_depot_not_the_run_id', false,
        'G16 / db/checks/0131. The state-change triggers derive data_source '
        'from depots.feed_mode (0073''s rule, propagated) instead of from '
        'whether a run id happened to be set, which stamped 116 events a pair '
        'production about work the twin did. The vehicles trigger also now '
        'passes p_depot_id, which it never has -- 27,440 vehicle events carry '
        'no depot at all. Hash-neutral: P1 isolates the h_evt expression out '
        'of the live verdict function and asserts it names neither column.',
        now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;
