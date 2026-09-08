-- migration-version: PENDING
-- migration-name:    h_sdr_may_now_fail_a_pair
--
-- ---------------------------------------------------------------------------
-- 0219 — h_sdr may now fail a pair.
--
-- 0217 added h_sdr measured-not-judged, on the rule 0206 set and 0217 closed for
-- h_rcl: an atom is enforced only after a flagship round shows the arms agree on
-- it. 0218 corrected the hash itself (it was including payload_hash, which is
-- computed over a payload containing leg_id and therefore could never agree).
--
-- This file promotes h_sdr into v_equal.
--
-- THE GATE IS CHECKED BY THE MIGRATION, NOT BY ME. P1 below reads the most
-- recent pair per flagship column out of ottoq_sim_runs and refuses to apply
-- unless ALL SIX columns have a post-0218 pair whose two arms agree on h_sdr.
-- I am writing this file before round 25 has finished, deliberately, so the
-- decision to enforce is made by the evidence rather than by my reading of it.
-- If a column disagrees, this migration aborts and says which — and that is a
-- defect to chase, not a gate to lower.
--
-- WHY THE 314159/12t COLUMN NEEDS A SECOND PAIR. Round 25's first pair ran at
-- 08:25, BEFORE 0218, so the h_sdr stored in its verdict is the contaminated
-- one (0df9a909 / 65ec044e). Recomputing ottoq_hash_sdrs over those two arms
-- today gives aad2d1be on both, but the stored verdict is a point-in-time
-- record and P1 reads what was stored, not what recomputes. That column must be
-- re-run after 0218 before this file can apply. Deliberate: an atom should be
-- promoted on evidence a pair actually recorded.
--
-- forces_recert: FALSE. Enforcing an atom that already agrees changes no canon;
-- it changes what a future disagreement costs.
-- ---------------------------------------------------------------------------

BEGIN;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0219_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_determinism_pair';

-- P1. THE GATE, READ FROM THE PAIRS THEMSELVES ------------------------------
DO $gate$
DECLARE
  r record; v_cols int := 0; v_bad text := ''; v_missing text := '';
BEGIN
  FOR r IN
    WITH pairs AS (
      SELECT DISTINCT ON (started_at) started_at, (validation_notes::jsonb) AS j
        FROM public.ottoq_sim_runs
       WHERE run_by = 'cert_harness'
         AND depot_id = '11111111-1111-1111-1111-111111111111'
         AND validation_notes IS NOT NULL
         AND jsonb_typeof((validation_notes::jsonb)->'arm_a') = 'object'
         AND started_at >= '2026-09-08 08:43:04+00'::timestamptz   -- 0218 applied
       ORDER BY started_at, sim_run_id
    ), keyed AS (
      SELECT (j->>'seed')::bigint AS seed, (j->>'ticks')::int AS ticks,
             j->>'scenario' AS scen, started_at,
             j->'arm_a'->>'h_sdr' AS a, j->'arm_b'->>'h_sdr' AS b,
             row_number() OVER (PARTITION BY (j->>'seed'), (j->>'ticks'), (j->>'scenario')
                                ORDER BY started_at DESC) AS rn
        FROM pairs
    )
    SELECT * FROM keyed WHERE rn = 1
  LOOP
    v_cols := v_cols + 1;
    IF r.a IS NULL OR r.b IS NULL THEN
      v_missing := v_missing || format(' %s/%st/%s(null)', r.seed, r.ticks, r.scen);
    ELSIF r.a IS DISTINCT FROM r.b THEN
      v_bad := v_bad || format(' %s/%st/%s(%s vs %s)', r.seed, r.ticks, r.scen,
                               left(r.a,8), left(r.b,8));
    END IF;
  END LOOP;

  IF v_cols < 6 THEN
    RAISE EXCEPTION '0219 P1: only % flagship column(s) have a post-0218 pair; all six must, '
                    'or the gate is being met by absence rather than by evidence', v_cols;
  END IF;
  IF v_missing <> '' THEN
    RAISE EXCEPTION '0219 P1: column(s) carry no h_sdr at all:%', v_missing;
  END IF;
  IF v_bad <> '' THEN
    RAISE EXCEPTION '0219 P1: the arms DISAGREE on h_sdr for:%  — that is a defect to chase, '
                    'not a gate to lower', v_bad;
  END IF;
  RAISE NOTICE '0219 P1: % flagship columns, every one with a post-0218 pair whose arms agree on h_sdr', v_cols;
END $gate$;

-- P2. AND THE BODY IS THE ONE 0217/0218 LEFT -------------------------------
DO $pre$
DECLARE v_def text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair';
  IF position($$'h_sdr', public.ottoq_hash_sdrs(v_run)$$ in v_def) = 0 THEN
    RAISE EXCEPTION '0219 P2: the arm object does not carry h_sdr — apply 0217 first';
  END IF;
  IF position($$(v_arms[1]->>'h_sdr')$$ in v_def) <> 0 THEN
    RAISE EXCEPTION '0219 P2: h_sdr is already enforced; nothing to do';
  END IF;
  IF position($$AND (v_arms[1]->>'h_rcl') = (v_arms[2]->>'h_rcl')$$ in v_def) = 0 THEN
    RAISE EXCEPTION '0219 P2: h_rcl is not enforced — the body is not the one 0217 left';
  END IF;
  IF position('d.payload_hash' in (SELECT pg_get_functiondef(q.oid) FROM pg_proc q
              JOIN pg_namespace m ON m.oid=q.pronamespace
              WHERE m.nspname='public' AND q.proname='ottoq_hash_sdrs')) <> 0 THEN
    RAISE EXCEPTION '0219 P2: ottoq_hash_sdrs still hashes payload_hash — apply 0218 first';
  END IF;
  RAISE NOTICE '0219 P2: h_sdr present and unenforced, h_rcl enforced, 0218 in place';
END $pre$;

-- 1. THE PROMOTION (catalog-derived rewrite) --------------------------------
-- The anchor is the WHOLE LINE, trailing comment included, and that is not
-- fussiness. Line 117 of the live definition reads
--
--   ·········AND·(v_arms[1]->>'h_rcl')·=·(v_arms[2]->>'h_rcl')···--·0217:·the·gate·0206·set·is·met
--
-- (9 leading spaces, 3 before the comment; measured, not assumed). Anchoring on
-- the expression alone and inserting a newline after it would push 0217's
-- provenance comment onto the END of the new h_sdr line — valid SQL, and a
-- false record: the line that says "0217: the gate 0206 set is met" would be
-- the line 0219 added. In a repo whose whole discipline is that the committed
-- record is the product, that is not cosmetic.
DO $rw$
DECLARE
  v_def text;
  v_old text := $f$AND (v_arms[1]->>'h_rcl') = (v_arms[2]->>'h_rcl')   -- 0217: the gate 0206 set is met$f$;
  v_new text := $f$AND (v_arms[1]->>'h_rcl') = (v_arms[2]->>'h_rcl')   -- 0217: the gate 0206 set is met
         AND (v_arms[1]->>'h_sdr') = (v_arms[2]->>'h_sdr')   -- 0219: the settlement record may now fail a pair$f$;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair';
  IF (length(v_def)-length(replace(v_def, v_old, '')))/length(v_old) <> 1 THEN
    RAISE EXCEPTION '0219: the h_rcl line (expression AND its 0217 comment) is not exactly '
                    'once in the catalog definition — re-measure the line before editing this anchor';
  END IF;
  EXECUTE replace(v_def, v_old, v_new);
  RAISE NOTICE '0219: ottoq_determinism_pair rewritten from its own catalog definition';
END $rw$;

-- A1. IT IS ENFORCED, AND NOTHING ELSE MOVED --------------------------------
-- Whitespace-insensitive on purpose. The v_equal chain is aligned by hand --
-- `(v_arms[1]->>'fp')    =` has four spaces, `h_cal')  =` has two, the rest one
-- -- so a literal match on a single space silently fails on two atoms and this
-- assertion would abort a correct migration. Strip the whitespace and compare.
DO $a1$
DECLARE v_def text; v_flat text; v_n int := 0; a text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair';
  v_flat := regexp_replace(v_def, '\s+', '', 'g');

  IF position($$(v_arms[1]->>'h_sdr')=(v_arms[2]->>'h_sdr')$$ in v_flat) = 0 THEN
    RAISE EXCEPTION '0219 A1: h_sdr is not enforced in the installed body';
  END IF;

  FOREACH a IN ARRAY ARRAY['fp','h_cmd','h_dec','h_evt','h_bkg','h_nrg',
                           'h_prop','h_defr','h_cal','h_rule','h_rcl','h_sdr'] LOOP
    IF position(format($$(v_arms[1]->>'%s')=(v_arms[2]->>'%s')$$, a, a) in v_flat) > 0 THEN
      v_n := v_n + 1;
    ELSE
      RAISE WARNING '0219 A1: atom % is NOT enforced', a;
    END IF;
  END LOOP;

  IF v_n <> 12 THEN
    RAISE EXCEPTION '0219 A1: % of 12 atoms are enforced; the rewrite dropped one', v_n;
  END IF;

  --: the chain carries two more equalities that are NOT hash atoms and so are
  --: not in the list above: 'ticks' (both arms ran the same horizon) and
  --: 'endst', which is compared with -> rather than ->> because it is a jsonb
  --: object, not a text hash. The rewrite edits this chain, so assert they
  --: survived it rather than trusting a string replace. "Twelve atoms" means
  --: twelve NAMED HASH atoms; the chain has fourteen equalities in total.
  IF position($$(v_arms[1]->>'ticks')=(v_arms[2]->>'ticks')$$ in v_flat) = 0 THEN
    RAISE EXCEPTION '0219 A1: the ticks equality is gone — the rewrite damaged the chain';
  END IF;
  IF position($$(v_arms[1]->'endst')=(v_arms[2]->'endst')$$ in v_flat) = 0 THEN
    RAISE EXCEPTION '0219 A1: the endst equality is gone — the rewrite damaged the chain';
  END IF;

  RAISE NOTICE '0219 A1: twelve hash atoms enforced with h_sdr among them, plus ticks and endst';
END $a1$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0219_h_sdr_may_now_fail_a_pair', FALSE,
        'h_sdr moves from measured to enforced, on the rule 0206 set: an atom is enforced only '
        'after a flagship round shows the arms agree. The gate is checked BY THE MIGRATION — P1 '
        'reads the most recent post-0218 pair per flagship column and refuses unless all six '
        'exist and agree, so the decision rests on what the pairs recorded rather than on '
        'anyone''s reading of them. Enforcing an atom that already agrees moves no canon; it '
        'changes what a future disagreement costs. Before 0216, 23 of 284 SDRs per arm bound to '
        'a different calendar claim inside a pair that passed thirteen atoms.',
        now());

COMMIT;
