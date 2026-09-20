-- migration-version: PENDING
-- migration-name:    a_proposers_hit_rate_is_deleted_by_the_next_run_that_starts
--
-- 0364  WHETHER A PROPOSAL WAS ENACTED IS RECORDED ONLY IN A TABLE THE NEXT
--       DEMO RUN DELETES. CAPTURE IT INTO EVIDENCE.
--
-- Fixes G72. Follows 0340's pattern exactly -- an append-only, `class='evidence'`
-- ledger with NO foreign key to `ottoq_sim_runs`, filled by an error-swallowing
-- capture trigger -- because that pattern was built for this problem and rule 5
-- says extend it rather than invent a second one.
--
-- ══ 1. WHY THIS IS NOT HYGIENE ═════════════════════════════════════════════
--
-- `ottoq_external_proposals` is registered `class='engine'`, so
-- `ottoq_purge_prior_runs` deletes it when the next demo run starts. Measured
-- tonight, twice: starting one run reported **940,266 rows purged**, and starting
-- the next **265,533**. Disposition -- `enacted` / `refused` / `superseded` /
-- `proposer_abstained` -- lives only there.
--
-- So **CLAUDE.md rule 6 cannot be satisfied across runs.** Rule 6 requires every
-- cuOpt sentence to be ledger-backed and forbids unquantified claims *in both
-- directions*. `ottoq_model_call_ledger` (0340) durably answers how many times a
-- provider was CALLED and how many proposals it RETURNED. Nothing durably answers
-- **how many were enacted**, which is the only number that says whether a
-- proposer is any good.
--
-- The cost is not theoretical, it is the shape of this whole session. Every
-- comparison tonight had to be hand-captured into a scratchpad or a check-file
-- comment moments before a purge, because the numbers would otherwise be gone:
-- `0256` records its baseline as a **comment rather than a query** for exactly
-- this reason. And the A/B now running has the same hazard built in -- Arm B's
-- `ottoq_start_demo_run` will delete Arm A's dispositions, so Arm A must be
-- captured by hand first or the experiment loses its own control group.
--
-- **This file is what makes that unnecessary, for this A/B and every future one.**
--
-- ══ 2. WHAT IT RECORDS THAT THE WORKING TABLE CANNOT ═══════════════════════
--
--   * **`proposer_rank` resolved AT CAPTURE TIME.** `ottoq_proposer_precedence` is
--     mutable declared data; if a rank changes next month, a ledger that joined to
--     it live would silently rewrite history and every past hit-rate would move.
--     The rank that actually applied is frozen into the row. This matters now:
--     0362's guard makes rank decide which proposals survive, so a hit rate is
--     only interpretable beside the rank in force when it was measured.
--   * **`abstained` as a boolean column.** `0361` made abstentions distinguishable
--     by reason string; this makes them countable without parsing prose. Any
--     refusal tally that does not exclude them is rigged against a proposer that
--     honestly declines -- CP-SAT abstains 9 to 11 of ~13-16 rows per fire BY
--     DESIGN, cuOpt barely abstains, so the difference is not a detail.
--   * **`promotion_count` and `promoted_from`.** 0358/0359's ranked-candidate
--     rescue is invisible in any outcome count that only reads the final stall.
--   * **`stall_id` as finally disposed**, so a promoted proposal's real target is
--     recorded rather than the one originally proposed.
--
-- ══ 3. THE THREE THINGS THAT MAKE IT EVIDENCE RATHER THAN MORE WORKING DATA ═
--
--   (a) **No foreign key to `ottoq_sim_runs` or to `ottoq_external_proposals`**,
--       deliberately. Both parents are purged. `ottoq_check_run_scope_registry`
--       check (b) requires an FK for `engine`/`stamp` only, and an enforcing FK on
--       evidence could only block the purge or, as CASCADE, erase exactly what
--       check (c) forbids erasing. `sim_run_id` and `proposal_id` are kept as
--       durable historical keys. This is 0340's reasoning, unchanged.
--   (b) **Append-only**, guarded by a trigger with a named session override. A
--       ledger that can be quietly edited proves nothing.
--   (c) **The capture trigger swallows its own errors.** It fires on the
--       disposition path, which runs inside `decide_tick`; APPLYING.md is explicit
--       that a failure there must never abort the tick, because a rolled-back tick
--       reads as "succeeded" in cron and produces zero stall assignments. A
--       missing evidence row is a gap; a rolled-back tick is an outage.
--
-- ══ 4. NO BACKFILL, AND THAT IS DELIBERATE ═════════════════════════════════
--
-- 0340 backfilled 515 surviving NVIDIA calls, and could, because
-- `cuopt_invocation_log` still held them. Here the honest choice is the opposite:
-- the only dispositions still alive belong to the **A/B arm currently running**,
-- and backfilling them would write `source_kind='backfill'` rows for a run whose
-- live trigger is about to start capturing the same ground. Mixed provenance on
-- the one run the experiment depends on is worse than starting clean.
--
-- So this ledger begins empty and records forward. **Its first rows will be Arm
-- B's**, which is the correct place for it to start earning its keep. Arm A's
-- numbers are hand-captured, and `0256`'s comment convention stands for them.
--
-- ══ 5. CLASSIFICATION ══════════════════════════════════════════════════════
--
-- `forces_recert: FALSE`, and the grounds are asserted rather than assumed by P5:
-- the fourteen-atom verdict's proposals atom is `ottoq_hash_proposals`, which
-- digests `ottoq_external_proposals` and cannot see a new table. Nothing about
-- engine behaviour changes -- the trigger only reads what the disposer already
-- wrote and copies it sideways.
--
-- **APPLY BETWEEN A/B ARMS, NOT DURING ONE.** A trigger added mid-arm would give
-- one arm partial capture and the other full, which is a confound inside the
-- instrument measuring the confound.
--
-- ══════════════════════════════════════════════════════════════════════════════

-- P0/P1. No certification scheduled or in flight.
DO $inflight$
DECLARE v_jobs text; v_pairs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0364 P0: certification jobs are still scheduled (%)', v_jobs;
  END IF;

  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0364 P1: % certification pair(s) are active', v_pairs;
  END IF;

  RAISE NOTICE '0364 P0/P1: no certification scheduled, no pair running';
END $inflight$;

-- P2. The table must not already exist, so a re-run refuses rather than partially
-- rebuilding a ledger.
DO $fresh$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
              WHERE n.nspname = 'public' AND c.relname = 'ottoq_proposal_disposition_ledger') THEN
    RAISE EXCEPTION '0364 P2: ottoq_proposal_disposition_ledger already exists -- '
                    'this file has already been applied';
  END IF;
  RAISE NOTICE '0364 P2: table does not exist yet';
END $fresh$;

-- P3. THE PREMISE. If ottoq_external_proposals were NOT class='engine' this file
-- would be solving a problem that does not exist, and the honest response would be
-- to withdraw it rather than add a table.
DO $premise$
DECLARE v_engine int;
BEGIN
  SELECT count(*) INTO v_engine FROM public.ottoq_run_scope_registry
   WHERE table_name = 'ottoq_external_proposals' AND class = 'engine';
  IF v_engine = 0 THEN
    RAISE EXCEPTION '0364 P3: ottoq_external_proposals is not registered class=engine, '
                    'so it is not purged and this ledger has no reason to exist -- '
                    'withdraw the file rather than applying it';
  END IF;
  RAISE NOTICE '0364 P3: premise holds -- the working table is purged (class=engine)';
END $premise$;

-- P4. The columns the capture trigger reads must all exist. A trigger referencing
-- a renamed column fails at RUNTIME, inside a swallowed handler, so it would go
-- silently unrecorded -- the exact failure mode this file exists to end.
DO $cols$
DECLARE v_missing text;
BEGIN
  SELECT string_agg(c, ', ') INTO v_missing
    FROM unnest(ARRAY['sim_run_id','depot_id','proposal_id','action_context','entity_type',
                      'entity_id','proposal','source','status','disposition_reason',
                      'created_at','disposed_at','disposed_tick']) AS c
   WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema = 'public'
                        AND table_name = 'ottoq_external_proposals'
                        AND column_name = c);
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION '0364 P4: ottoq_external_proposals is missing column(s) the capture '
                    'trigger reads: %', v_missing;
  END IF;
  RAISE NOTICE '0364 P4: every column the trigger reads exists';
END $cols$;

-- P5. THE forces_recert:FALSE GROUNDS. The proposals atom must not be able to see
-- this table. If ottoq_hash_proposals ever named it, the classification would be
-- wrong and every canon streak silently invalid (the G28 class).
DO $hash$
DECLARE v_names int;
BEGIN
  SELECT count(*) INTO v_names
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_hash_proposals'
     AND position('ottoq_proposal_disposition_ledger' in p.prosrc) > 0;
  IF v_names > 0 THEN
    RAISE EXCEPTION '0364 P5: ottoq_hash_proposals references the new ledger -- '
                    'reclassify forces_recert TRUE before applying';
  END IF;
  RAISE NOTICE '0364 P5: the proposals atom cannot see the new ledger';
END $hash$;

-- ══ 1. the ledger ════════════════════════════════════════════════════════════
CREATE TABLE public.ottoq_proposal_disposition_ledger (
  disposition_id    bigserial PRIMARY KEY,
  --: Durable historical keys. NO FOREIGN KEYS, deliberately: both
  --: ottoq_sim_runs and ottoq_external_proposals are purged, and an enforcing FK
  --: on evidence can only block the purge or, as CASCADE, erase what
  --: ottoq_check_run_scope_registry check (c) forbids erasing.
  sim_run_id        uuid,
  proposal_id       uuid,
  depot_id          uuid,
  action_context    text,
  entity_type       text,
  entity_id         uuid,
  source            text NOT NULL,
  --: The rank that APPLIED, frozen at capture. ottoq_proposer_precedence is
  --: mutable declared data; joining to it live would rewrite every past hit rate
  --: the next time a rank changed. NULL = the source was unlisted, which is
  --: itself the fact worth keeping.
  proposer_rank     integer,
  status            text NOT NULL,
  disposition_reason text,
  --: Countable rather than parsed from prose. 0361 made abstentions
  --: distinguishable by reason; this makes them excludable from a refusal tally
  --: without reading strings.
  abstained         boolean NOT NULL DEFAULT false,
  --: 0358/0359's ranked-candidate rescue, invisible to any count that reads only
  --: the final stall.
  promotion_count   integer,
  promoted_from     uuid,
  --: As finally disposed, so a promoted proposal records its real target.
  stall_id          uuid,
  requested_kw      numeric,
  --: WALL domain, matching the columns they are copied from.
  proposal_created_at timestamptz,
  disposed_at       timestamptz,
  disposed_tick     bigint,
  captured_at       timestamptz NOT NULL DEFAULT now(),
  --: 'live' = the trigger wrote it as it happened. A reader must be able to tell
  --: live capture from any later reconstruction.
  source_kind       text NOT NULL DEFAULT 'live'
);

COMMENT ON TABLE public.ottoq_proposal_disposition_ledger IS
'0364, fixing G72. One row per DISPOSED external proposal, and the only record of proposal outcome that outlives its run. ottoq_external_proposals is class=engine, so ottoq_purge_prior_runs deletes it when the next demo run starts -- measured at 940,266 and 265,533 rows purged on two consecutive starts tonight -- which means a proposer''s ENACTMENT RATE was not answerable across runs at all. ottoq_model_call_ledger (0340) durably answers calls made and proposals returned; this answers what became of them, which is the only number that says whether a proposer is any good, and CLAUDE.md rule 6 forbids unquantified claims in BOTH directions. Registered class=evidence with NO foreign key to ottoq_sim_runs or ottoq_external_proposals: check (b) requires an FK for engine/stamp only, and an enforcing FK on evidence can only block the purge or, as CASCADE, erase what check (c) forbids erasing. THREE COLUMNS EXIST FOR REASONS THAT ARE NOT OBVIOUS: proposer_rank is resolved AT CAPTURE and frozen, because ottoq_proposer_precedence is mutable and a live join would rewrite every historical hit rate the next time a rank changed -- which matters now that 0362''s guard makes rank decide survival; abstained is a boolean so a refusal tally can exclude abstentions without parsing prose, and it must, because CP-SAT abstains 9-11 rows of ~13-16 per fire BY DESIGN while cuOpt barely abstains; promotion_count / promoted_from record 0358/0359''s candidate rescue, which is invisible to any count reading only the final stall. Append-only (override: ottoq.disposition_ledger_unlock=on). Filled by an ERROR-SWALLOWING trigger because it fires on the disposition path inside decide_tick and a failure there must never abort a tick -- a missing evidence row is a gap, a rolled-back tick is an outage. Deliberately NOT backfilled: the only live dispositions belonged to a running A/B arm, and mixed provenance on the one run an experiment depends on is worse than starting clean.';

CREATE INDEX ottoq_proposal_disposition_ledger_source_idx
  ON public.ottoq_proposal_disposition_ledger (source, disposed_at DESC);
CREATE INDEX ottoq_proposal_disposition_ledger_run_idx
  ON public.ottoq_proposal_disposition_ledger (sim_run_id) WHERE sim_run_id IS NOT NULL;
CREATE INDEX ottoq_proposal_disposition_ledger_status_idx
  ON public.ottoq_proposal_disposition_ledger (status, source);

-- ══ 2. append-only ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_proposal_disposition_ledger_append_only()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
BEGIN
  IF COALESCE(current_setting('ottoq.disposition_ledger_unlock', true), '') = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION
    'ottoq_proposal_disposition_ledger is append-only: % refused. Set '
    'ottoq.disposition_ledger_unlock=on in the session to override, and say why in a migration.',
    TG_OP
    USING ERRCODE = '42501';
END $fn$;

CREATE TRIGGER ottoq_proposal_disposition_ledger_append_only_trg
  BEFORE UPDATE OR DELETE ON public.ottoq_proposal_disposition_ledger
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_proposal_disposition_ledger_append_only();

-- ══ 3. the capture trigger ═══════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_capture_proposal_disposition()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  --: Only a transition INTO a terminal status is an outcome. A pending row that
  --: is rewritten by promotion (0358) is not a disposition and must not be
  --: counted as one.
  IF NEW.status IS NOT DISTINCT FROM OLD.status
     OR NEW.status = 'pending' THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.ottoq_proposal_disposition_ledger
    (sim_run_id, proposal_id, depot_id, action_context, entity_type, entity_id,
     source, proposer_rank, status, disposition_reason, abstained,
     promotion_count, promoted_from, stall_id, requested_kw,
     proposal_created_at, disposed_at, disposed_tick, source_kind)
  VALUES
    (NEW.sim_run_id, NEW.proposal_id, NEW.depot_id, NEW.action_context,
     NEW.entity_type, NEW.entity_id, NEW.source,
     --: frozen at capture, on purpose -- see the table comment
     (SELECT pp.rank FROM public.ottoq_proposer_precedence pp WHERE pp.source = NEW.source),
     NEW.status, NEW.disposition_reason,
     COALESCE(NEW.proposal->>'abstain', '') IN ('true','t','1'),
     NULLIF(NEW.proposal->>'promotion_count','')::integer,
     NULLIF(NEW.proposal->>'promoted_from','')::uuid,
     NULLIF(NEW.proposal->>'stall_id','')::uuid,
     CASE WHEN (NEW.proposal->>'requested_kw') ~ '^[0-9]+(\.[0-9]+)?$'
          THEN (NEW.proposal->>'requested_kw')::numeric END,
     NEW.created_at, NEW.disposed_at, NEW.disposed_tick, 'live');

  RETURN NEW;

--: SWALLOWED ON PURPOSE. This fires on the disposition path, which runs inside
--: decide_tick. APPLYING.md: a failure there must never abort the tick, because a
--: rolled-back tick reads as "succeeded" in cron and produces zero stall
--: assignments. A missing evidence row is a gap; a rolled-back tick is an outage.
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '0364 capture_proposal_disposition: % %', SQLSTATE, SQLERRM;
  RETURN NEW;
END $fn$;

COMMENT ON FUNCTION public.ottoq_capture_proposal_disposition() IS
'0364 (G72). Copies a proposal''s terminal disposition into ottoq_proposal_disposition_ledger, which is class=evidence and survives ottoq_purge_prior_runs. Fires only on a transition INTO a terminal status: a pending row rewritten by 0358''s candidate promotion is not a disposition and must not be counted as one. Resolves proposer_rank at capture and freezes it, because ottoq_proposer_precedence is mutable and a live join would rewrite history. Errors are swallowed and warned: it runs on the disposition path inside decide_tick, and a failure there must never abort a tick.';

CREATE TRIGGER ottoq_capture_proposal_disposition_trg
  AFTER UPDATE OF status ON public.ottoq_external_proposals
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_capture_proposal_disposition();

-- ══ 4. registry ══════════════════════════════════════════════════════════════
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public', 'ottoq_proposal_disposition_ledger', 'sim_run_id', 'evidence',
        '0364 (G72): the durable record of what became of each external proposal. Evidence, not engine: '
        'CLAUDE.md rule 6 forbids unquantified proposer claims in BOTH directions, and enactment rate -- '
        'the only number that says whether a proposer is any good -- was previously readable only from '
        'ottoq_external_proposals, which is class=engine and deleted by the next demo run (940,266 and '
        '265,533 rows purged on two consecutive starts). Carries NO foreign key to ottoq_sim_runs or '
        'ottoq_external_proposals, deliberately: check (b) asks for one from engine/stamp only, and an '
        'enforcing FK on evidence could only block ottoq_purge_prior_runs or, as CASCADE, erase the '
        'history check (c) forbids erasing.');

-- ══ 5. the reader ════════════════════════════════════════════════════════════
-- A ledger nobody can query is a ledger nobody checks. This is the rule-6 answer
-- per proposer, and it EXCLUDES abstentions from the refusal tally -- which is the
-- whole point of carrying `abstained` as a column.
CREATE OR REPLACE VIEW public.ottoq_proposer_scorecard AS
SELECT d.source,
       d.proposer_rank,
       count(*)                                                    AS dispositions,
       count(*) FILTER (WHERE d.status = 'enacted')                AS enacted,
       count(*) FILTER (WHERE d.abstained)                         AS abstained,
       count(*) FILTER (WHERE d.status = 'refused' AND NOT d.abstained)
                                                                   AS refused_real,
       count(*) FILTER (WHERE d.status = 'superseded')              AS superseded,
       count(*) FILTER (WHERE d.status = 'expired')                 AS expired,
       count(*) FILTER (WHERE COALESCE(d.promotion_count, 0) > 0)   AS rescued_by_promotion,
       --: the honest hit rate: enacted over proposals the proposer actually STOOD
       --: BEHIND. An abstention is not a miss, and counting it as one is what
       --: rigs a comparison against a proposer that declines honestly.
       round(100.0 * count(*) FILTER (WHERE d.status = 'enacted')
             / NULLIF(count(*) FILTER (WHERE NOT d.abstained), 0), 2)
                                                                   AS enacted_pct_of_committed,
       count(DISTINCT d.sim_run_id)                                 AS runs,
       min(d.disposed_at)                                           AS first_disposed,
       max(d.disposed_at)                                           AS last_disposed
  FROM public.ottoq_proposal_disposition_ledger d
 GROUP BY d.source, d.proposer_rank;

COMMENT ON VIEW public.ottoq_proposer_scorecard IS
'0364. The rule-6 answer per proposer, across runs, from evidence that outlives them. enacted_pct_of_committed divides by proposals the proposer STOOD BEHIND -- abstentions excluded -- because an abstention is not a miss, and counting it as one is precisely what would rig a CP-SAT vs cuOpt comparison: CP-SAT abstains 9-11 of ~13-16 rows per fire by design while cuOpt barely abstains. Groups by proposer_rank as well as source because rank is frozen at capture and 0362''s guard makes rank decide which proposals survive to be judged, so a hit rate is only interpretable beside the rank that was in force.';

-- P6. POST-CHECK — every structural promise of this file, asserted.
DO $post$
DECLARE v_fk int; v_trg int; v_reg int; v_rows int; v_swallow boolean;
BEGIN
  --: (a) no foreign keys. An FK here would make the purge either fail or cascade,
  --: and cascading is the one thing an evidence table must never do.
  SELECT count(*) INTO v_fk
    FROM pg_constraint con JOIN pg_class c ON c.oid = con.conrelid
   WHERE c.relname = 'ottoq_proposal_disposition_ledger' AND con.contype = 'f';
  IF v_fk <> 0 THEN
    RAISE EXCEPTION '0364 P6a: the ledger has % foreign key(s); it must have none', v_fk;
  END IF;

  --: (b) both triggers present
  SELECT count(*) INTO v_trg FROM pg_trigger
   WHERE NOT tgisinternal
     AND tgname IN ('ottoq_proposal_disposition_ledger_append_only_trg',
                    'ottoq_capture_proposal_disposition_trg');
  IF v_trg <> 2 THEN
    RAISE EXCEPTION '0364 P6b: expected 2 triggers, found %', v_trg;
  END IF;

  --: (c) registered as evidence, and as nothing else -- a stray engine or stamp
  --: row added later would put the purge back in charge of it
  SELECT count(*) INTO v_reg FROM public.ottoq_run_scope_registry
   WHERE table_name = 'ottoq_proposal_disposition_ledger';
  IF v_reg <> 1 THEN
    RAISE EXCEPTION '0364 P6c: expected exactly 1 registry row, found %', v_reg;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry
                  WHERE table_name = 'ottoq_proposal_disposition_ledger'
                    AND class = 'evidence') THEN
    RAISE EXCEPTION '0364 P6c: the registry row is not class=evidence';
  END IF;

  --: (d) the capture function really swallows. 0340 asserts the same thing about
  --: its own triggers, and it is the difference between a gap and an outage.
  SELECT position('EXCEPTION WHEN OTHERS' in p.prosrc) > 0 INTO v_swallow
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_capture_proposal_disposition';
  IF NOT COALESCE(v_swallow, false) THEN
    RAISE EXCEPTION '0364 P6d: the capture function does not swallow errors -- it runs '
                    'on the tick path and would abort a tick';
  END IF;

  --: (e) starts empty, per section 4
  SELECT count(*) INTO v_rows FROM public.ottoq_proposal_disposition_ledger;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION '0364 P6e: the ledger is not empty (% rows) -- this file does not backfill', v_rows;
  END IF;

  RAISE NOTICE '0364 P6: no FKs, 2 triggers, 1 evidence registry row, capture swallows, ledger empty';
END $post$;

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0364_a_proposers_hit_rate_is_deleted_by_the_next_run_that_starts', false,
  'forces_recert FALSE and P5 asserts the grounds: the proposals atom is ottoq_hash_proposals, which '
  'digests ottoq_external_proposals and cannot see a new table; the capture trigger only copies what the '
  'disposer already wrote, so no engine behaviour changes. Fixes G72. ottoq_external_proposals is '
  'class=engine, so ottoq_purge_prior_runs deletes it when the next demo run starts -- 940,266 and '
  '265,533 rows purged on two consecutive starts tonight -- and disposition lived only there, so a '
  'proposer''s ENACTMENT RATE was not answerable across runs. ottoq_model_call_ledger (0340) durably '
  'answers calls made and proposals returned; this answers what became of them, and rule 6 forbids '
  'unquantified proposer claims in BOTH directions. Follows 0340 exactly -- append-only, class=evidence, '
  'NO FK to either purged parent, error-swallowing capture trigger -- because that pattern was built for '
  'this problem (rule 5). Three non-obvious columns: proposer_rank is FROZEN AT CAPTURE because '
  'ottoq_proposer_precedence is mutable and a live join would rewrite every historical hit rate, which '
  'matters now that 0362''s guard makes rank decide survival; abstained is a boolean so a refusal tally '
  'can exclude abstentions without parsing prose, and it must, because CP-SAT abstains 9-11 of ~13-16 '
  'rows per fire BY DESIGN while cuOpt barely abstains; promotion_count / promoted_from record '
  '0358/0359''s rescue, invisible to any count reading only the final stall. The capture fires only on a '
  'transition INTO a terminal status, so a pending row rewritten by promotion is not miscounted as a '
  'disposition. DELIBERATELY NOT BACKFILLED: the only live dispositions belonged to a running A/B arm, '
  'and mixed provenance on the run an experiment depends on is worse than starting clean -- its first '
  'rows will be Arm B''s. APPLY BETWEEN A/B ARMS, never during one: a trigger added mid-arm gives one arm '
  'partial capture and the other full, a confound inside the instrument measuring the confound.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;
