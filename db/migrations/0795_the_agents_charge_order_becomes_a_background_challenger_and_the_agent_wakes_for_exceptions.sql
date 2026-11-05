-- migration-version: PENDING
-- migration-name:    the_agents_charge_order_becomes_a_background_challenger_and_the_agent_wakes_for_exceptions
--
-- 0795  **The agent's charge order becomes a background challenger: checked and graded as before, never standing; and
--        the agent is woken for exceptions, not for the routine moments an order could change the line.**
--
-- ══ §0 WHY (Chase, 2026-11-05) ═════════════════════════════════════════════════════════════════════════════════════
--
--   The research wing's replays of every graded decision at the twin depot (db/checks/0478, 0479; G511, G512) found that
--   the agent's per-tick charge orders, when the kernel took them, mostly moved one owner's cars up the line and
--   another's down: of 32 taken, 5 were good for every owner in hindsight, 22 traded one owner for another and 5 hurt
--   every owner; a rule that lets no owner lose takes none of the 370. Since 0784's owner guard went on (2026-10-25) the
--   kernel has taken 0 of them. Recommended in conversation on 2026-11-05: take the AI off the minute-by-minute charge
--   line and keep it where it helps. Chase: "Okay I agree with you on all fronts. Begin building and let's make sure that
--   AI + Agentic assistance is still a huge tool for us in the OTTO-Q tech stack. Even if it isn't in every loop, maybe
--   it is in the background or knows when to be called for exceptions or input".
--
-- ══ §1 WHAT CHANGES ═════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) One dial, a person's (rule 10): agent_charge_order_shadow (0..1, default 0).
--   (b) public.ottoq_agent_charge_order_record: with the dial at 1, an order the kernel's check would take is recorded
--       with status 'shadow' instead of 'accepted' or 'partial'. Everything else is as before: the check rolls the line
--       forward in the same futures, the snapshot is kept, the order is graded in hindsight. ottoq_agent_charge_order_live
--       reads 'accepted' and 'partial' only, so a shadow order never stands and the kernel's own order (0642, 0781)
--       seats every car. An order the check refuses is still 'refused' with its reason; a malformed one 'rejected'.
--   (c) The orders table's status check admits 'shadow'.
--   (d) public.ottoq_charge_order_grade_compute: a shadow order is graded as the check's take (taken = true: right_take,
--       neutral_take or wrong_take in hindsight, as an order the check took always was), while the forecast errors and
--       the fidelity read the side the depot actually followed, which for a shadow order is the kernel's. For every
--       other status the two are the same thing, so every grade of an order that is not shadow is computed exactly as
--       before (the hindsight code md5 changes, as for any change to the grader).
--   (e) public.ottoq_agent_charge_queue_board: the board's check block says 'shadow': true with the dial on, beside
--       0784's 'owner_guard', so the agent's own record shows what it was told.
--   (f) public.ottoq_agent_charge_order_usage: counts the run's shadow orders ('orders_shadow'), once it has one, so a
--       run without one reads as before, key for key (the board carries the usage).
--   (g) public.ottoq_agent_wake: the two reasons 0769 added because they are "the two moments an order changes what the
--       kernel does" (charger_free, due_in_line) wake the agent only while its order can stand. With the dial at 1 they
--       are still counted in the fingerprint and do not wake it; 'order_moments_wake' says which. Every other reason is
--       unchanged: a charger fault or repair, contention onset or relief, an emergency, a car newly past its contract
--       wait, a demand-response call, a scout's finding, the first consult and the heartbeat.
--
--   With agent_wake_enabled also at 1 (0705's gate, a person's dial, set in the same sitting as this file), a pass with
--   no reason is solver-only (edge v29+): no model call, the solver on the standing objective. On the twin depot's last
--   long run (763734d4, 2026-10-25, 419 passes) the gate found no reason on 319 passes and only the two order moments on
--   93 more, so the agent would have been consulted on 7 passes plus a heartbeat every 30 sim-minutes, instead of 419.
--
-- ══ §2 WHAT IT DOES NOT CHANGE ═════════════════════════════════════════════════════════════════════════════════════
--
--   No car's order, charge, target or service (rule 9): the kernel's own line already seats every car whenever no agent
--   order stands, which since 2026-10-25 is every tick (the owner guard took 0 of 145 orders on 763734d4 and 8c0b2e04).
--   The agent's other levers are untouched: the solver objective, its directives (checked against rule 9 by
--   _shared/agent_rule_nine.ts), whitelisted operational moves and the human approval queue. No edge function changes:
--   edge v31 counts an order as taken only when the receipt says accepted or partial (_shared/agent_charge_order.ts,
--   _shared/agent_pass_evidence.ts), so a shadow order is not an enacted action on the decision row or the pass record.
--   Rule 14: a challenger that never stands cannot make one owner's car wait for another's; its grades say, owner by owner
--   in the lab (lab/research/p1_referee_owner_futures/), whether a fair version of it would ever have helped.
--
-- ══ §3 CHECKS ════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: not applied; 0784 applied; the five bodies are the ones read on 2026-11-05 from production
--   (md5 of prosrc, equal in the research lab built from production's export); the dial is not catalogued; the status
--   check is the one read. Each anchor matches once. V1: each patched body less its replacements is its pre-image. V2:
--   comment-stripped, the record function sets 'shadow' only inside the check's take branch and only under the dial;
--   ottoq_agent_charge_order_live still reads accepted and partial only; the grader's forecast and fidelity read the side
--   that stood. Executed end to end in the research lab on a replica of production's engine (lab/research/
--   p1_agent_challenger/test_0795.py): at the default every function answers as before; with the dial an order the check
--   takes is recorded 'shadow', never stands, and the tick seats cars exactly as without it; the grade of a shadow order
--   reads the kernel's side for its forecast; the wake gate stops waking for the two order moments and still counts them.
--
-- ══ §4 RULES AND LINEAGE ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--   Rule 10: the dial is a person's (agent_writable false), switched on at the twin depot under Chase's name. Rule 12:
--   built behind a dial and switched on, not queued for a test. forces_recert FALSE: a certification arm is never armed
--   (ottoq_agentic_arm refuses cert_harness), so no atom reads an agent order, the board or the wake gate.
--   forces_dial_restart FALSE: an ab_harness arm runs in one transaction and the agent never reaches it (0615 §1).
--
-- ROLLBACK: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0795_pre';
--   ALTER TABLE public.ottoq_agent_charge_orders DROP CONSTRAINT ottoq_agent_charge_orders_status_check,
--     ADD CONSTRAINT ottoq_agent_charge_orders_status_check CHECK (status = ANY (ARRAY['accepted','partial','rejected','refused']))
--     (only once no row is 'shadow'; the table is append-only);
--   DELETE FROM public.ottoq_policy_params WHERE param_key = 'agent_charge_order_shadow';
--   DELETE FROM public.ottoq_policy_param_catalog WHERE param_key = 'agent_charge_order_shadow';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0795_the_agents_charge_order_becomes_a_background_challenger_and_the_agent_wakes_for_exceptions'.
--   Turning the dial to 0 at the depot restores 0620's door without a rollback.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0795 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: not applied; 0784 in; the bodies as read; the dial new; the status check as read ──
DO $premises$
DECLARE r record;
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0795_the_agents_charge_order_becomes_a_background_challenger_and_the_agent_wakes_for_exceptions') THEN
    RAISE EXCEPTION '0795 P1: already applied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0784_the_check_takes_an_agents_order_only_when_no_owner_is_worse_off') THEN
    RAISE EXCEPTION '0795 P1: 0784 is not applied';
  END IF;
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_agent_charge_order_record(uuid,bigint,text,text,jsonb)',          '8406ec1de4689d35ad606e1e15f9f628'),
      ('public.ottoq_agent_charge_order_usage(uuid,integer)',                          '9151ba25aa55bec3933b7eb8fc510891'),
      ('public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)',    '53c59c15758a7b9e1c09e2cd9518f0d9'),
      ('public.ottoq_agent_wake(uuid)',                                                '353f108cb90369892c18a72537d2619b'),
      ('public.ottoq_charge_order_grade_compute(bigint,numeric)',                      'aac0190c09b0fce7546ca987acb8e8a6')
    ) AS t(fn, m)
  LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(r.fn)) IS DISTINCT FROM r.m THEN
      RAISE EXCEPTION '0795 P1: % is not the body read (md5 %)', r.fn, left(r.m, 8);
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'agent_charge_order_shadow') THEN
    RAISE EXCEPTION '0795 P1: agent_charge_order_shadow is already catalogued';
  END IF;
  IF (SELECT pg_get_constraintdef(oid) FROM pg_constraint
       WHERE conrelid = 'public.ottoq_agent_charge_orders'::regclass AND conname = 'ottoq_agent_charge_orders_status_check')
     IS DISTINCT FROM 'CHECK ((status = ANY (ARRAY[''accepted''::text, ''partial''::text, ''rejected''::text, ''refused''::text])))' THEN
    RAISE EXCEPTION '0795 P1: the orders'' status check is not the one read';
  END IF;
END $premises$;

-- ── the pre-images ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0795_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_agent_charge_order_record(uuid,bigint,text,text,jsonb)'::regprocedure,
                 'public.ottoq_agent_charge_order_usage(uuid,integer)'::regprocedure,
                 'public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)'::regprocedure,
                 'public.ottoq_agent_wake(uuid)'::regprocedure,
                 'public.ottoq_charge_order_grade_compute(bigint,numeric)'::regprocedure);

-- ── (a) the dial ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('agent_charge_order_shadow',
        '0795: 1 = the agent''s charge order is a background challenger. An order the kernel''s check would take is '
        'recorded ''shadow'' and never stands: the kernel''s own order seats every car. It is checked, kept and graded in '
        'hindsight exactly as before, so the research wing can say whether the agent ever finds a better order, owner by '
        'owner. With it at 1 the wake gate no longer wakes the agent for the two moments an order could change the line '
        '(a charger free with a car waiting, a car due in the line''s head); it still counts them, and every exception '
        'still wakes it. 0 = 0620''s door (and 0784''s guard). A person''s dial, never the agent''s (rule 10).',
        0, 0, 1, 'public.ottoq_agent_charge_order_record, public.ottoq_charge_order_grade_compute, '
                 'public.ottoq_agent_charge_queue_board, public.ottoq_agent_charge_order_usage, public.ottoq_agent_wake',
        false);

-- ── (c) the status check admits 'shadow' ──
ALTER TABLE public.ottoq_agent_charge_orders
  DROP CONSTRAINT ottoq_agent_charge_orders_status_check,
  ADD CONSTRAINT ottoq_agent_charge_orders_status_check
    CHECK (status = ANY (ARRAY['accepted'::text, 'partial'::text, 'rejected'::text, 'refused'::text, 'shadow'::text]));

-- ── (b), (d)-(g): the anchored replacements ──
CREATE TEMP TABLE _0795_patch (seq int, fn regprocedure, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0795_patch VALUES
  -- (b) the record: an order the check takes is 'shadow' under the dial
  (1, 'public.ottoq_agent_charge_order_record(uuid,bigint,text,text,jsonb)'::regprocedure,
   $o1$    IF NOT COALESCE((v_verdict ->> 'take')::boolean, false) THEN
      v_status := 'refused';
    END IF;
  END IF;$o1$,
   $n1$    IF NOT COALESCE((v_verdict ->> 'take')::boolean, false) THEN
      v_status := 'refused';
    -- 0795: with agent_charge_order_shadow at 1 the agent's order is a background challenger: an order the check takes
    -- is recorded 'shadow' and never stands (ottoq_agent_charge_order_live reads accepted and partial only), so the
    -- kernel's own order seats every car; it is checked, kept and graded exactly as before
    ELSIF COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_shadow', 0), 0) >= 1 THEN
      v_status := 'shadow';
    END IF;
  END IF;$n1$),
  -- (d) the grader: a shadow order is the check's take; forecast and fidelity read the side that stood
  (2, 'public.ottoq_charge_order_grade_compute(bigint,numeric)'::regprocedure,
   $o2$  v_exp jsonb; v_hind jsonb; v_reason text; v_taken boolean; v_decision boolean; v_outcome text; v_hc int;$o2$,
   $n2$  v_exp jsonb; v_hind jsonb; v_reason text; v_taken boolean; v_decision boolean; v_outcome text; v_hc int;
  v_stood boolean;   -- 0795$n2$),
  (3, 'public.ottoq_charge_order_grade_compute(bigint,numeric)'::regprocedure,
   $o3$  v_taken := COALESCE(o.status IN ('accepted', 'partial'), false);$o3$,
   $n3$  v_taken := COALESCE(o.status IN ('accepted', 'partial'), false);
  -- 0795: a 'shadow' order is one the check took and agent_charge_order_shadow held back: it is graded as the check's
  -- take, and the forecast and fidelity read the side the depot followed (v_stood), which for it is the kernel's. For
  -- every other status the two are the same.
  v_stood := v_taken;
  v_taken := v_taken OR COALESCE(o.status = 'shadow', false);$n3$),
  (4, 'public.ottoq_charge_order_grade_compute(bigint,numeric)'::regprocedure,
   $o4$  g.forecast := public.ottoq_charge_order_forecast_errors(s.state, v_real, CASE WHEN v_taken THEN ea ELSE ek END);
  g.fidelity := public.ottoq_charge_order_fidelity(CASE WHEN v_taken THEN ha ELSE hk END, v_real);$o4$,
   $n4$  g.forecast := public.ottoq_charge_order_forecast_errors(s.state, v_real, CASE WHEN v_stood THEN ea ELSE ek END);
  g.fidelity := public.ottoq_charge_order_fidelity(CASE WHEN v_stood THEN ha ELSE hk END, v_real);$n4$),
  -- (e) the board says the order is a challenger
  (5, 'public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)'::regprocedure,
   $o5$      || CASE WHEN COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_owner_guard', 0), 0) >= 1
              THEN jsonb_build_object('owner_guard', true) ELSE '{}'::jsonb END,$o5$,
   $n5$      || CASE WHEN COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_owner_guard', 0), 0) >= 1
              THEN jsonb_build_object('owner_guard', true) ELSE '{}'::jsonb END
      -- 0795: and, with agent_charge_order_shadow on, that an order it takes is kept as a challenger and never stands
      || CASE WHEN COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_shadow', 0), 0) >= 1
              THEN jsonb_build_object('shadow', true) ELSE '{}'::jsonb END,$n5$),
  -- (f) the usage counts the shadow orders, once there is one (a run without one reads as before, key for key)
  (6, 'public.ottoq_agent_charge_order_usage(uuid,integer)'::regprocedure,
   $o6$        FROM (SELECT * FROM o ORDER BY o.order_id DESC LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 20), 200))) o), '[]'::jsonb))$o6$,
   $n6$        FROM (SELECT * FROM o ORDER BY o.order_id DESC LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 20), 200))) o), '[]'::jsonb))
    -- 0795: the orders the check took that agent_charge_order_shadow held back; none of them stood
    || COALESCE((SELECT jsonb_build_object('orders_shadow', count(*)) FROM o WHERE o.status = 'shadow' HAVING count(*) > 0),
                '{}'::jsonb)$n6$),
  -- (g) the wake gate: the two order moments wake the agent only while its order can stand
  (7, 'public.ottoq_agent_wake(uuid)'::regprocedure,
   $o7$  v_free     integer; v_due integer;                   --: 0769 (G488)$o7$,
   $n7$  v_free     integer; v_due integer;                   --: 0769 (G488)
  v_moments  boolean;                                  --: 0795$n7$),
  (8, 'public.ottoq_agent_wake(uuid)'::regprocedure,
   $o8$    IF v_free > 0 AND v_waiting > 0 THEN v_reasons := array_append(v_reasons, 'charger_free'::text); END IF;
    IF v_due > 0 THEN v_reasons := array_append(v_reasons, 'due_in_line'::text); END IF;$o8$,
   $n8$    --: 0795: only while the agent's order can stand. With agent_charge_order_shadow at 1 the order is a background
    --: challenger that changes nothing at these moments, so they are counted (the fingerprint) and do not wake it.
    v_moments := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_shadow', 0), 0) < 1;
    IF v_moments AND v_free > 0 AND v_waiting > 0 THEN v_reasons := array_append(v_reasons, 'charger_free'::text); END IF;
    IF v_moments AND v_due > 0 THEN v_reasons := array_append(v_reasons, 'due_in_line'::text); END IF;$n8$),
  (9, 'public.ottoq_agent_wake(uuid)'::regprocedure,
   $o9$    'standing_objective', v_objective,$o9$,
   $n9$    'order_moments_wake', v_moments,                    --: 0795
    'standing_objective', v_objective,$n9$);

DO $patch$
DECLARE f regprocedure; p record; v_def text; n int;
BEGIN
  FOR f IN SELECT DISTINCT x.fn FROM _0795_patch x LOOP
    v_def := pg_get_functiondef(f);
    FOR p IN SELECT * FROM _0795_patch x WHERE x.fn = f ORDER BY x.seq LOOP
      n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
      IF n <> 1 THEN
        RAISE EXCEPTION '0795: anchor % matches % times in %, not 1', p.seq, n, f;
      END IF;
      v_def := replace(v_def, p.c_old, p.c_new);
    END LOOP;
    EXECUTE v_def;
    IF pg_get_functiondef(f) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0795: % is not stored as patched', f;
    END IF;
  END LOOP;
END $patch$;

-- ── V1: each patched body less its replacements is its pre-image ──
DO $v1$
DECLARE f regprocedure; p record; v_body text;
BEGIN
  FOR f IN SELECT DISTINCT x.fn FROM _0795_patch x LOOP
    v_body := pg_get_functiondef(f);
    FOR p IN SELECT * FROM _0795_patch x WHERE x.fn = f ORDER BY x.seq DESC LOOP
      v_body := replace(v_body, p.c_new, p.c_old);
    END LOOP;
    IF md5(v_body) IS DISTINCT FROM (SELECT s.def_md5 FROM public.ottoq_schema_snapshots s
                                      WHERE s.label = '0795_pre'
                                        AND s.object_name = (SELECT pp.proname FROM pg_proc pp WHERE pp.oid = f)) THEN
      RAISE EXCEPTION '0795 V1: % less its replacements is not its pre-image', f;
    END IF;
  END LOOP;
END $v1$;

-- ── V2: what reads 'shadow', comment-stripped ──
DO $v2$
DECLARE v_rec text; v_live text; v_grade text;
BEGIN
  SELECT regexp_replace(prosrc, '--[^\n]*', '', 'g') INTO v_rec
    FROM pg_proc WHERE oid = 'public.ottoq_agent_charge_order_record(uuid,bigint,text,text,jsonb)'::regprocedure;
  IF (length(v_rec) - length(replace(v_rec, '''shadow''', ''))) / length('''shadow''') <> 1
     OR v_rec !~ 'v_status := ''refused'';\s*ELSIF COALESCE\(public\.ottoq_policy_get\(p_sim_run_id, ''agent_charge_order_shadow'', 0\), 0\) >= 1 THEN\s*v_status := ''shadow'';\s*END IF;' THEN
    RAISE EXCEPTION '0795 V2: the record does not set shadow only in the take branch under the dial';
  END IF;
  SELECT regexp_replace(prosrc, '--[^\n]*', '', 'g') INTO v_live
    FROM pg_proc WHERE oid = 'public.ottoq_agent_charge_order_live(uuid,bigint)'::regprocedure;
  IF v_live !~ 'x\.status IN \(''accepted'', ''partial''\)' OR v_live ~ 'shadow' THEN
    RAISE EXCEPTION '0795 V2: the live order no longer reads accepted and partial only';
  END IF;
  SELECT regexp_replace(prosrc, '--[^\n]*', '', 'g') INTO v_grade
    FROM pg_proc WHERE oid = 'public.ottoq_charge_order_grade_compute(bigint,numeric)'::regprocedure;
  IF v_grade !~ 'forecast_errors\(s\.state, v_real, CASE WHEN v_stood THEN ea ELSE ek END\)'
     OR v_grade !~ 'fidelity\(CASE WHEN v_stood THEN ha ELSE hk END, v_real\)'
     OR v_grade ~ 'CASE WHEN v_taken THEN e?h?a ELSE' THEN
    RAISE EXCEPTION '0795 V2: the grader''s forecast and fidelity do not read the side that stood';
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0795_the_agents_charge_order_becomes_a_background_challenger_and_the_agent_wakes_for_exceptions', false, false,
        'Dial agent_charge_order_shadow (default 0). At 1 an agent charge order the check takes is recorded ''shadow'' '
        'and never stands; it is checked, kept and graded as before (graded as the check''s take, its forecast and '
        'fidelity on the kernel''s side, which the depot followed); the board says so; usage counts them; and the wake '
        'gate stops waking the agent for the two moments an order could change the line. Chase, 2026-11-05, on taking '
        'the AI off the minute-by-minute charge line (G511, G512). No certification arm is armed and no ab_harness arm '
        'reaches the agent, so FALSE/FALSE.',
        now());

COMMIT;
