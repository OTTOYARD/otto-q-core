-- migration-version: 20261112140612
-- migration-name:    0818_the_twin_snapshot_names_the_post_of_a_cabin_stop
--
-- 0818  **The twin snapshot names the post of a cabin stop.**
--
-- WHY. 0817 sends a parked car with an interior deep clean and no charge to do to a free fast-charger post, where it
-- stands, not plugged in, for the arm's program. The engine marks the stop on the visit's atom (cabin_stop_stall_id).
-- public.ottoq_twin_snapshot publishes a fixed list of each atom's fields, and the mark is not one of them. So a
-- renderer reads the car as charge_complete_holding with a stall, which is every car that has just finished a charge,
-- and cannot tell that this one was SENT to its post. The twin drew such a car in staging (ottoyarddepot-sim,
-- TwinMotionDriver.mapState), with no arm at work.
--
-- WHAT THIS DOES. One field more in each published atom: cabin_stop_stall_id, the twin stall of the stop while the
-- stop is open, null otherwise. A read. Nothing in the engine reads the snapshot (its one caller is the coverage
-- check public.ottoq_t4_coverage).
--
-- P0 nothing in flight. P1 the body this file was written against (md5 of prosrc 6fb49a2e85e89538961caf31791b5f54).
-- P2 once. V1 the patched body with its patch reversed is its pre-image. V2 the anchor matched once.
--
-- CLASSIFICATION. forces_recert FALSE, forces_dial_restart FALSE: a published read gains one key, null on every atom
-- with no stop, and no engine function reads it. Applied with a run live: the function is replaced whole, and the
-- next read of it carries the key.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0818_pre'; DELETE FROM
--   public.ottoq_cert_lineage WHERE name LIKE '0818_%'.

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $pre$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0818 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_twin_snapshot(uuid)'::regprocedure)
       IS DISTINCT FROM '6fb49a2e85e89538961caf31791b5f54' THEN
    RAISE EXCEPTION '0818 P1: public.ottoq_twin_snapshot is not the body this file was written against';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name LIKE '0818_%') THEN
    RAISE EXCEPTION '0818 P2: already applied';
  END IF;
END $pre$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0818_pre', 'function', 'public', 'ottoq_twin_snapshot',
       pg_get_functiondef('public.ottoq_twin_snapshot(uuid)'::regprocedure),
       md5(pg_get_functiondef('public.ottoq_twin_snapshot(uuid)'::regprocedure));

DO $patch$
DECLARE
  c_old constant text := $o$                       'robot_stall_id', a.value->>'robot_stall_id')$o$;
  c_new constant text := $n$                       'robot_stall_id', a.value->>'robot_stall_id',
                       -- 0818: the fast-charger post a car was sent to for a cabin stop (0817), while the stop is open
                       'cabin_stop_stall_id', a.value->>'cabin_stop_stall_id')$n$;
  v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_twin_snapshot(uuid)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0818 V2: the anchor matches % times, not 1', n; END IF;
  v_def := replace(v_def, c_old, c_new);
  EXECUTE v_def;
  IF md5(replace(pg_get_functiondef('public.ottoq_twin_snapshot(uuid)'::regprocedure), c_new, c_old))
       IS DISTINCT FROM (SELECT s.def_md5 FROM public.ottoq_schema_snapshots s WHERE s.label = '0818_pre') THEN
    RAISE EXCEPTION '0818 V1: the patched body with its patch reversed is not its pre-image';
  END IF;
END $patch$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0818_the_twin_snapshot_names_the_post_of_a_cabin_stop', false, false,
        'public.ottoq_twin_snapshot publishes one more field of each visit atom: cabin_stop_stall_id, the post of an open '
        'cabin stop (0817), null otherwise. A read; no engine function reads the snapshot. The twin draws the car on its '
        'post with the cleaning arm at work.',
        now());

COMMIT;

-- APPLIED 2026-11-12 at 14:06:12 UTC (8:06 AM CT), ledger 20261112140612, through apply_migration, on the first send,
--   with demo run 56d8465f live (a read function, replaced whole). The text sent was this file from BEGIN to COMMIT.
--   Stored after the apply, md5(prosrc) 0636303b7ced86b967b277e9b2cccc55. The snapshot of the live run read back as
--   before, with the new key.
