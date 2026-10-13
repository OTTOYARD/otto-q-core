-- migration-version: 20261013184608
-- migration-name:    the_feed_agents_propose_the_twins_world_and_a_person_promotes_it
--
-- 0716  **The feed agents propose the twin's world; a person promotes it.** Every operator Start fires seven Nemotron
--        "feed agents" (edge-functions/ottoq-feed-agents), one per twin feed plan, and each may write a new ACTIVE
--        version of its plan and retire the old one. That is the one per-run LLM swarm OTTO-Q already has, and it
--        rewrites the research wing's world with no person in the loop. Rule 10: hypotheses and world changes are the
--        research wing's, "reviewed and shipped as a certified change". From this file an agent's plan lands as a
--        DRAFT, and only ottoq_feed_plan_promote, under a person's name, makes a version active. (The study's AG-6 /
--        TF-2; G431.)
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Measured 2026-10-13 (read-only). charger_fault_repair, the twin's charger fault plan, has four versions: v1, the
--   sourced dossier (base_session_fault_p 0.05, authored_by dossier_v1, 2026-07-09), then three written by the agent
--   (authored_by nemotron-3-ultra): v2 0.06 on 09-27, v3 0.065 on 09-30, v4 0.055 on 10-10, ACTIVE now. Each rationale
--   fits the twin's OWN realized fault rate ("over 975 sessions the realized fault rate is 0.0728", "realized 0.071 over
--   493 sessions", "realized 0.0519") -- a rate the twin drew from the plan being judged. The world is being tuned to its
--   own sampling noise, with no outside data, and every later run reads the newest active version unpinned, research,
--   A/B and certification runs included. No function writes ottoq_feed_plans: the edge function inserts the new version
--   with status 'active' and then updates the old one to 'superseded', both through the service role.
--
-- ══ §2 WHAT THIS CHANGES ════════════════════════════════════════════════════════════════════════════════════════
--
--   a. Trigger ottoq_feed_plans_person_promotes (BEFORE INSERT OR UPDATE on public.ottoq_feed_plans). Outside a
--      promotion (the transaction-local setting ottoq.feed_plan_promote, set only by the function in b):
--        - a new row asking to be 'active' is written as 'draft' instead (an agent's proposal is kept, not refused);
--        - a change to an active row's status, plan or method is refused (an active plan is changed only by promotion).
--      A draft may still be written and edited freely; nothing about drafts reaches a run.
--   b. public.ottoq_feed_plan_promote(p_plan_id uuid, p_by text, p_reason text): refuses a name the agent predicate
--      knows, any 'nemotron%' name, and the version's own author when that author is not a person; activates the version
--      (a draft, or a superseded one -- so a revert to the sourced v1 is one call), retires the var's active one, and
--      records the promotion in c. Service role only.
--   c. public.ottoq_feed_plan_promotions: append-only evidence (class 'evidence', no foreign key), one row per
--      promotion: which version, which it replaced, by whom, why.
--   The edge function changes beside this file (v2 of ottoq-feed-agents): it writes 'draft', never retires a plan, and
--   records on the run the plan it actually ran on.
--
--   NOT changed: v4 stays active. Whether the twin's charger faults go back to the sourced 0.05 is a person's call,
--   and with this file it is one line: SELECT public.ottoq_feed_plan_promote('ef4eac4a-d017-42ce-9b98-99112df8dcd7',
--   '<name>', '<why>'). ottoq_evidence_regimes admits only the charge clock's model today, so the fault model's regime
--   is not recorded here; that is a follow-up, named in G431.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════════════════════════════════
--
--   No plan's content changes, and the active versions are the same before and after. What changes is who may change
--   them next.
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   DROP TRIGGER ottoq_feed_plans_person_promotes ON public.ottoq_feed_plans (a person's step; this file never drops).

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0716 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

DO $premises$
BEGIN
  PERFORM set_config('ottoq.feed_plans_active_0716',
    (SELECT COALESCE(string_agg(var_key || ':' || version, ',' ORDER BY var_key), '') FROM public.ottoq_feed_plans
      WHERE status = 'active'), true);
  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.ottoq_feed_plans'::regclass AND NOT tgisinternal) THEN
    RAISE EXCEPTION '0716 P1: ottoq_feed_plans already has a trigger';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.ottoq_feed_plans'::regclass AND contype = 'c'
                    AND pg_get_constraintdef(oid) LIKE '%''draft''%') THEN
    RAISE EXCEPTION '0716 P1: ottoq_feed_plans does not admit status draft';
  END IF;
  IF to_regclass('public.ottoq_feed_plan_promotions') IS NOT NULL THEN
    RAISE EXCEPTION '0716 P1: already applied';
  END IF;
  --: no database function writes the table (the edge function is the one writer)
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname IN ('public', 'twin', 'ottoq') AND p.prokind = 'f'
                AND pg_get_functiondef(p.oid) ~* '(insert\s+into|update)\s+(public\.)?ottoq_feed_plans\M') THEN
    RAISE EXCEPTION '0716 P1: a database function writes ottoq_feed_plans; read it before guarding the table';
  END IF;
END $premises$;

CREATE TABLE public.ottoq_feed_plan_promotions (
  promotion_id   bigserial PRIMARY KEY,
  --: durable keys, NO foreign keys (0340/0364)
  plan_id        uuid NOT NULL,
  var_key        text NOT NULL,
  version        integer NOT NULL,
  replaced_plan  uuid,
  replaced_ver   integer,
  promoted_by    text NOT NULL CHECK (length(btrim(promoted_by)) >= 2),
  reason         text NOT NULL CHECK (length(btrim(reason)) >= 10),
  authored_by    text,
  promoted_at    timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.ottoq_feed_plan_promotions IS
'0716. One row per promotion of a twin feed plan version to active, by a person (rule 10: the research wing''s world '
'changes are reviewed and shipped by a person). Append-only evidence, no foreign key.';

CREATE FUNCTION public.ottoq_feed_plan_promotions_append_only() RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'public', 'pg_temp' AS $fn$
BEGIN
  IF COALESCE(current_setting('ottoq.feed_plan_promotions_unlock', true), '') = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION 'ottoq_feed_plan_promotions is append-only evidence (0716)' USING ERRCODE = '42501';
END $fn$;
CREATE TRIGGER ottoq_feed_plan_promotions_append_only BEFORE UPDATE OR DELETE OR TRUNCATE
  ON public.ottoq_feed_plan_promotions FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_feed_plan_promotions_append_only();
ALTER TABLE public.ottoq_feed_plan_promotions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ottoq_feed_plan_promotions FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON public.ottoq_feed_plan_promotions TO service_role;
GRANT USAGE ON SEQUENCE public.ottoq_feed_plan_promotions_promotion_id_seq TO service_role;
CREATE POLICY ottoq_feed_plan_promotions_service ON public.ottoq_feed_plan_promotions FOR ALL TO service_role
  USING (true) WITH CHECK (true);

INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public', 'ottoq_feed_plan_promotions', 'plan_id', 'evidence',
        '0716: who made which twin feed plan version active, and why. Evidence: outlives every run; no foreign key.');

CREATE FUNCTION public.ottoq_feed_plans_person_promotes() RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'public', 'pg_temp' AS $fn$
BEGIN
  IF COALESCE(current_setting('ottoq.feed_plan_promote', true), '') = 'on' THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.status = 'active' THEN
      --: an agent's (or anyone's) new version outside a promotion is a proposal, kept as a draft
      NEW.status := 'draft';
      NEW.rationale := COALESCE(NEW.rationale, '') || ' [0716: written as a draft; a person promotes it]';
    END IF;
    RETURN NEW;
  END IF;
  --: UPDATE
  IF OLD.status = 'active' AND (NEW.status IS DISTINCT FROM OLD.status OR NEW.plan IS DISTINCT FROM OLD.plan
                                OR NEW.method IS DISTINCT FROM OLD.method OR NEW.version IS DISTINCT FROM OLD.version
                                OR NEW.var_key IS DISTINCT FROM OLD.var_key) THEN
    RAISE EXCEPTION 'ottoq_feed_plans: an active plan (% v%) changes only by ottoq_feed_plan_promote, under a person''s name (0716, rule 10)',
      OLD.var_key, OLD.version USING ERRCODE = '42501';
  END IF;
  IF NEW.status = 'active' AND OLD.status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'ottoq_feed_plans: % v% becomes active only by ottoq_feed_plan_promote (0716, rule 10)',
      OLD.var_key, OLD.version USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END $fn$;
CREATE TRIGGER ottoq_feed_plans_person_promotes BEFORE INSERT OR UPDATE ON public.ottoq_feed_plans
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_feed_plans_person_promotes();

CREATE FUNCTION public.ottoq_feed_plan_promote(p_plan_id uuid, p_by text, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_new public.ottoq_feed_plans; v_old public.ottoq_feed_plans; v_by text := btrim(COALESCE(p_by, ''));
BEGIN
  IF length(v_by) < 2 OR length(btrim(COALESCE(p_reason, ''))) < 10 THEN
    RAISE EXCEPTION 'ottoq_feed_plan_promote: a person''s name and a reason (10+ characters) are required' USING ERRCODE = '22023';
  END IF;
  IF public.ottoq_is_agent_actor(v_by) OR v_by ILIKE 'nemotron%' OR v_by ILIKE '%agent%' OR v_by ILIKE 'ottocommand%' THEN
    RAISE EXCEPTION 'ottoq_feed_plan_promote: % is an agent; a person promotes a feed plan (0716, rule 10)', v_by
      USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_new FROM public.ottoq_feed_plans WHERE plan_id = p_plan_id FOR UPDATE;
  IF v_new.plan_id IS NULL THEN
    RAISE EXCEPTION 'ottoq_feed_plan_promote: no plan %', p_plan_id USING ERRCODE = '22023';
  END IF;
  IF v_new.status = 'active' THEN
    RETURN jsonb_build_object('ok', true, 'already_active', true, 'var_key', v_new.var_key, 'version', v_new.version);
  END IF;
  IF v_by = v_new.authored_by AND (v_new.authored_by ILIKE 'nemotron%' OR public.ottoq_is_agent_actor(v_new.authored_by)) THEN
    RAISE EXCEPTION 'ottoq_feed_plan_promote: the author of % v% cannot promote it', v_new.var_key, v_new.version
      USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_old FROM public.ottoq_feed_plans
   WHERE var_key = v_new.var_key AND status = 'active' ORDER BY version DESC LIMIT 1 FOR UPDATE;

  PERFORM set_config('ottoq.feed_plan_promote', 'on', true);
  UPDATE public.ottoq_feed_plans SET status = 'superseded'
   WHERE var_key = v_new.var_key AND status = 'active';
  UPDATE public.ottoq_feed_plans SET status = 'active' WHERE plan_id = v_new.plan_id;
  PERFORM set_config('ottoq.feed_plan_promote', 'off', true);

  INSERT INTO public.ottoq_feed_plan_promotions (plan_id, var_key, version, replaced_plan, replaced_ver, promoted_by,
                                                 reason, authored_by)
  VALUES (v_new.plan_id, v_new.var_key, v_new.version, v_old.plan_id, v_old.version, v_by, btrim(p_reason),
          v_new.authored_by);
  RETURN jsonb_build_object('ok', true, 'var_key', v_new.var_key, 'version', v_new.version,
                            'replaced_version', v_old.version, 'promoted_by', v_by);
END $fn$;
REVOKE ALL ON FUNCTION public.ottoq_feed_plan_promote(uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_feed_plan_promote(uuid, text, text) TO service_role;

DO $v$
DECLARE v_active_after text;
BEGIN
  --: V1 the active versions are unchanged by this file
  SELECT COALESCE(string_agg(var_key || ':' || version, ',' ORDER BY var_key), '') INTO v_active_after
    FROM public.ottoq_feed_plans WHERE status = 'active';
  IF v_active_after IS DISTINCT FROM current_setting('ottoq.feed_plans_active_0716', true) THEN
    RAISE EXCEPTION '0716 V1 FAILED: the active plans moved: % -> %', current_setting('ottoq.feed_plans_active_0716', true), v_active_after;
  END IF;
  --: V2 outside a promotion, an active insert lands as a draft and an active plan cannot be retired (rolled back)
  BEGIN
    INSERT INTO public.ottoq_feed_plans (plan_id, var_key, version, status, method, plan, provenance, authored_by, rationale)
    VALUES ('00000000-0000-0000-0000-000000000716', '__0716_probe', 1, 'active', 'probe', '{}'::jsonb, '{}'::jsonb,
            'nemotron-3-ultra', 'probe');
    IF (SELECT status FROM public.ottoq_feed_plans WHERE plan_id = '00000000-0000-0000-0000-000000000716') <> 'draft' THEN
      RAISE EXCEPTION '0716 V2 FAILED: an active insert outside a promotion was not made a draft';
    END IF;
    BEGIN
      UPDATE public.ottoq_feed_plans SET status = 'superseded'
       WHERE status = 'active' AND var_key = (SELECT min(var_key) FROM public.ottoq_feed_plans WHERE status = 'active');
      RAISE EXCEPTION '0716 V2 FAILED: an active plan was retired outside a promotion';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    BEGIN
      PERFORM public.ottoq_feed_plan_promote('00000000-0000-0000-0000-000000000716', 'nemotron-3-ultra', 'a probe reason');
      RAISE EXCEPTION '0716 V2 FAILED: an agent promoted a plan';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    RAISE EXCEPTION USING ERRCODE = 'P0716', MESSAGE = 'rollback';
  EXCEPTION WHEN SQLSTATE 'P0716' THEN NULL;
  END;
  IF EXISTS (SELECT 1 FROM public.ottoq_feed_plans WHERE var_key = '__0716_probe') THEN
    RAISE EXCEPTION '0716 V2 FAILED: the probe row survived';
  END IF;
  --: V3 grants
  IF has_function_privilege('anon', 'public.ottoq_feed_plan_promote(uuid,text,text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.ottoq_feed_plan_promote(uuid,text,text)', 'EXECUTE') THEN
    RAISE EXCEPTION '0716 V3 FAILED: a signed-in user can promote';
  END IF;
  RAISE NOTICE '0716 V1-V3 PASSED (active: %)', v_active_after;
END $v$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0716_the_feed_agents_propose_the_twins_world_and_a_person_promotes_it', false, false,
  'G431, the study''s AG-6 / TF-2: the per-run feed agents wrote ACTIVE twin feed plans (charger_fault_repair v2-v4, '
  'fitted to the twin''s own realized fault rate). A new version now lands as a draft and only a person promotes '
  '(ottoq_feed_plan_promote, recorded in ottoq_feed_plan_promotions). No active plan changes: FALSE/FALSE.',
  now());

COMMIT;
