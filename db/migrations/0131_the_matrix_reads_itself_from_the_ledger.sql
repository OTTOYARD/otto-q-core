-- migration-version: 20260831020000
-- migration-name:    the_matrix_reads_itself_from_the_ledger
-- 0131 -- the certification matrix stops being a hand-typed comment block.
--
-- WHY. db/checks/0046 §3 carried a "STANDING CANON" list of per-column hashes, typed by hand.
-- 0128, 0129 and 0130 each moved behaviour, and by round 3 several of those hashes were simply
-- wrong while still being labelled standing -- caught only because a human happened to re-read
-- them. That is the exact failure mode the company rule exists to prevent ("no number ships
-- without a run ID"): a number that cannot be regenerated from its evidence is a number nobody
-- should trust, including us. Every hash in the matrix already lives in
-- ottoq_sim_runs.validation_notes, stamped by the pair harness on both arm rows. So the matrix
-- is a QUERY, not a comment.
--
-- WHAT GREEN MEANS -- and why the bar is raised here (the round-3 lesson, paid for in pairs).
-- The old rule (0046 operating rule 2) was: after a behaviour change the first pair may fork
-- on the fingerprint alone, and then THE CONFIRM PAIR MUST PASS. One pass = green. Pair 74
-- falsified that. On 424242/24t the lineage ran fail (P72), fail (P73), PASS (P74) -- and the
-- column was not fixed at all; the pass was a two-state coin landing favourably, and the very
-- next investigation found the live carrier (0130). A single passing pair is evidence; it is
-- not proof.
-- So `green` here requires TWO consecutive most-recent passing pairs whose stream hashes AND
-- fingerprint are identical to each other. Two passes in a row on the same canon cannot be
-- explained by one coin flip, and the arms of the second pair boot from the first pair's
-- leftovers, so it also re-proves world purity. P74 alone does not clear this bar; P75+P76 do.
-- `consecutive_passes` is exposed so the matrix shows the DEPTH of evidence, not just a flag.
--
-- This function is pure read -- STABLE, no writes, called by nothing in the decide path. It is
-- the substrate for the standing CI determinism gate (brief C6/C7) and for the cert record.

CREATE OR REPLACE FUNCTION public.ottoq_cert_matrix(p_since timestamptz DEFAULT now() - interval '30 days')
RETURNS TABLE (
  seed          bigint,
  ticks         int,
  scenario      text,
  pairs_seen    int,
  consecutive_passes int,
  green         boolean,
  last_pair_at  timestamptz,
  canon_fp      text,
  canon_cmd     text,
  canon_dec     text,
  canon_evt     text,
  canon_bkg     text,
  last_run_a    uuid,
  last_run_b    uuid,
  history       text
)
LANGUAGE sql
STABLE
SET search_path TO 'public', 'ottoq', 'twin', 'extensions'
AS $function$
WITH pair AS (
  -- One row per pair: the harness stamps both arm rows with the same started_at and the
  -- same verdict document, so DISTINCT ON collapses the arms without inventing a key.
  SELECT DISTINCT ON (r.started_at)
         r.started_at                            AS t0,
         (r.validation_status = 'passed')        AS ok,
         (r.validation_notes::jsonb)             AS j
    FROM public.ottoq_sim_runs r
   WHERE r.run_by = 'cert_harness'
     AND r.started_at >= p_since
     AND r.validation_status IS NOT NULL
     AND r.validation_notes IS NOT NULL
     AND jsonb_typeof((r.validation_notes::jsonb) -> 'arm_a') = 'object'
   ORDER BY r.started_at, r.sim_run_id
), col AS (
  SELECT p.t0, p.ok,
         (p.j->>'seed')::bigint                    AS c_seed,
         COALESCE((p.j->>'ticks')::int, -1)        AS c_ticks,
         COALESCE(p.j->>'scenario', '?')           AS c_scen,
         p.j->'arm_a'->>'fp'                       AS c_fp,
         p.j->'arm_a'->>'h_cmd'                    AS c_cmd,
         p.j->'arm_a'->>'h_dec'                    AS c_dec,
         p.j->'arm_a'->>'h_evt'                    AS c_evt,
         p.j->'arm_a'->>'h_bkg'                    AS c_bkg,
         (p.j->'arm_a'->>'run')::uuid              AS c_run_a,
         (p.j->'arm_b'->>'run')::uuid              AS c_run_b
    FROM pair p
), ranked AS (
  SELECT c.*, row_number() OVER (PARTITION BY c.c_seed, c.c_ticks, c.c_scen
                                 ORDER BY c.t0 DESC, c.c_run_a DESC) AS rn
    FROM col c
), canon AS (
  -- The reference canon is the MOST RECENT pair's. Confirmation means the pairs before it
  -- agree with it exactly; a pass on different hashes is a new equilibrium, not a confirmation.
  SELECT rk.c_seed, rk.c_ticks, rk.c_scen, rk.c_fp, rk.c_cmd, rk.c_dec, rk.c_evt, rk.c_bkg
    FROM ranked rk WHERE rk.rn = 1
), marked AS (
  SELECT r.c_seed, r.c_ticks, r.c_scen, r.rn,
         (r.ok
          AND r.c_fp  IS NOT DISTINCT FROM k.c_fp
          AND r.c_cmd IS NOT DISTINCT FROM k.c_cmd
          AND r.c_dec IS NOT DISTINCT FROM k.c_dec
          AND r.c_evt IS NOT DISTINCT FROM k.c_evt
          AND r.c_bkg IS NOT DISTINCT FROM k.c_bkg) AS on_canon
    FROM ranked r
    JOIN canon k ON k.c_seed = r.c_seed AND k.c_ticks = r.c_ticks AND k.c_scen = r.c_scen
), streak AS (
  SELECT x.c_seed, x.c_ticks, x.c_scen,
         count(*) FILTER (WHERE x.unbroken)::int AS n_pass
    FROM (
      SELECT m.c_seed, m.c_ticks, m.c_scen,
             bool_and(m.on_canon) OVER (PARTITION BY m.c_seed, m.c_ticks, m.c_scen
                                        ORDER BY m.rn
                                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS unbroken
        FROM marked m
    ) x
   GROUP BY x.c_seed, x.c_ticks, x.c_scen
), hist AS (
  SELECT c.c_seed, c.c_ticks, c.c_scen,
         string_agg(CASE WHEN c.ok THEN 'P' ELSE 'f' END, '' ORDER BY c.t0) AS h_hist,
         count(*)::int AS n_pairs
    FROM col c GROUP BY c.c_seed, c.c_ticks, c.c_scen
)
SELECT h.c_seed, h.c_ticks, h.c_scen, h.n_pairs,
       COALESCE(s.n_pass, 0),
       (COALESCE(s.n_pass, 0) >= 2),
       l.t0, l.c_fp, l.c_cmd, l.c_dec, l.c_evt, l.c_bkg, l.c_run_a, l.c_run_b,
       h.h_hist
  FROM hist h
  JOIN streak s ON s.c_seed = h.c_seed AND s.c_ticks = h.c_ticks AND s.c_scen = h.c_scen
  JOIN ranked l ON l.c_seed = h.c_seed AND l.c_ticks = h.c_ticks
               AND l.c_scen = h.c_scen AND l.rn = 1
 ORDER BY h.c_ticks DESC, h.c_scen, h.c_seed;
$function$;

COMMENT ON FUNCTION public.ottoq_cert_matrix(timestamptz) IS
'The determinism certification matrix, derived from ottoq_sim_runs.validation_notes -- never hand-typed. green = the two most recent pairs both passed on an IDENTICAL canon (0131: one passing pair is a coin landing favourably; pair 74 proved it). history reads oldest-first, P=pass f=fork.';
