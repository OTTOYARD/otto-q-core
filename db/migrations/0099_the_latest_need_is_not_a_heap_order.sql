-- migration-version: 20260830003000
-- migration-name:    the_latest_need_is_not_a_heap_order
-- 0099 -- the V5 cursor sweep, part 1: the `ORDER BY vn.created_at DESC LIMIT 1` family.
--
-- Twelve "give me the vehicle's LATEST need" cursors across ten functions order by
-- created_at -- a WALL-clock column whose values TIE for every row inserted in the same
-- transaction -- and take LIMIT 1. On a tie the pick is heap order: which need wins (and with
-- it target_soc, urgency, atoms) differs run to run. This is the disease family behind the
-- residual divergence of determinism pairs 4/5 (db/checks/0046), and the same class 0054/0067
-- fixed elsewhere before the decide-path rewrite regrew it.
--
-- THE TIEBREAK: `visit_key` = '<vehicle uuid>:<sim timestamp>' -- run-STABLE (fleet id + sim
-- clock; never a per-run random uuid, which would still differ across same-seed arms) and
-- sim-domain. Appended AFTER created_at, so behavior is unchanged except exactly at ties,
-- which now close deterministically. Idiom precedent: ottoq_rider_flag_indepot_sweep already
-- orders `n.created_at DESC, n.visit_key DESC`.
--
-- SITES (each function pinned; per-function occurrence counts verified before replace):
--   ottoq.ottoq_arrival_disposition        1   ottoq.ottoq_record_enacted_booking   2
--   ottoq.ottoq_decide_wash_triage         1   ottoq.ottoq_reoptimize_reservation_book 1
--   ottoq.ottoq_plan_opportunistic_charges 1   ottoq.ottoq_reserve_inbound_bays     1
--   public.ottoq_decide_tick               2   ottoq.ottoq_readmit_reopened_needs   1 (alias n)
--   ottoq.ottoq_book_appointment           1 (NULLS LAST form)
--   ottoq.ottoq_readmit_resumed_visits     1 (alias n)
--
-- Known remaining after this sweep (still open in 0046): score-only ORDER BYs without an id
-- tiebreak outside this family, and the wall-domain proposal TTLs. Re-run the pair after this;
-- bisect again if it still diverges.

DO $do$
DECLARE
  r RECORD; v_oid oid; v_src text; v_new text; v_cnt int;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('ottoq',  'ottoq_arrival_disposition',        '1406066b158ecad548c3b6151d906477',
       'vn.created_at DESC LIMIT',            'vn.created_at DESC, vn.visit_key DESC LIMIT', 1),
      ('ottoq',  'ottoq_decide_wash_triage',         '6a020db1f1edf2e56c4759f4459f6185',
       'vn.created_at DESC LIMIT',            'vn.created_at DESC, vn.visit_key DESC LIMIT', 1),
      ('ottoq',  'ottoq_plan_opportunistic_charges', 'ebb064854c582b4e771005c1c91c411e',
       'vn.created_at DESC LIMIT',            'vn.created_at DESC, vn.visit_key DESC LIMIT', 1),
      ('ottoq',  'ottoq_record_enacted_booking',     '30174e9fa152498bbf0f04a60da811be',
       'vn.created_at DESC LIMIT',            'vn.created_at DESC, vn.visit_key DESC LIMIT', 2),
      ('ottoq',  'ottoq_reoptimize_reservation_book','cf6016b206a15730c675888d2ac11bc4',
       'vn.created_at DESC LIMIT',            'vn.created_at DESC, vn.visit_key DESC LIMIT', 1),
      ('ottoq',  'ottoq_reserve_inbound_bays',       '04c9c84c35afd693c7c648d9c6273ad5',
       'vn.created_at DESC LIMIT',            'vn.created_at DESC, vn.visit_key DESC LIMIT', 1),
      ('public', 'ottoq_decide_tick',                '079754ea35eea8bcb9ee050dca8db855',
       'vn.created_at DESC LIMIT',            'vn.created_at DESC, vn.visit_key DESC LIMIT', 2),
      ('ottoq',  'ottoq_book_appointment',           'efd61574fcb40390a48cd5546cd89e6c',
       'vn.created_at DESC NULLS LAST LIMIT', 'vn.created_at DESC NULLS LAST, vn.visit_key DESC LIMIT', 1),
      ('ottoq',  'ottoq_readmit_reopened_needs',     'bb690df4227b39e6d066f7ca0610faf2',
       'n.created_at DESC LIMIT',             'n.created_at DESC, n.visit_key DESC LIMIT', 1),
      ('ottoq',  'ottoq_readmit_resumed_visits',     'a91d7b80403af540e670427b8278cd70',
       'n.created_at DESC LIMIT',             'n.created_at DESC, n.visit_key DESC LIMIT', 1)
    ) AS t(sch, fn, pin, old_a, new_a, n_expect)
  LOOP
    SELECT p.oid INTO STRICT v_oid
      FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
     WHERE ns.nspname = r.sch AND p.proname = r.fn AND p.prokind='f';
    v_src := pg_get_functiondef(v_oid);

    IF md5(v_src) <> r.pin THEN
      RAISE EXCEPTION '0099 abort: %.% drifted from pinned pre-image (md5 %)', r.sch, r.fn, md5(v_src);
    END IF;

    v_cnt := (length(v_src) - length(replace(v_src, r.old_a, ''))) / length(r.old_a);
    IF v_cnt <> r.n_expect THEN
      RAISE EXCEPTION '0099 abort: %.% anchor found % times, expected %', r.sch, r.fn, v_cnt, r.n_expect;
    END IF;

    v_new := replace(v_src, r.old_a, r.new_a);
    EXECUTE v_new;

    v_src := pg_get_functiondef(v_oid);
    v_cnt := (length(v_src) - length(replace(v_src, 'visit_key DESC LIMIT', ''))) / length('visit_key DESC LIMIT');
    IF v_cnt < r.n_expect THEN
      RAISE EXCEPTION '0099 abort: %.% patch did not survive (% of % sites)', r.sch, r.fn, v_cnt, r.n_expect;
    END IF;

    RAISE NOTICE '0099: %.% -- % site(s) closed', r.sch, r.fn, r.n_expect;
  END LOOP;

  RAISE NOTICE '0099 applied: the latest need is picked by sim-stable key, never heap order.';
END
$do$;
