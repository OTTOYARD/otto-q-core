-- 0142: a migration classifies itself
--
-- 0141 changed a function's security context and a table's RLS. It moves no canon and
-- strengthens no verdict, so it should not have forced re-certification. It did, because it
-- did not add its own row to ottoq_cert_lineage and absence means "forces". The floor jumped
-- from 08-31 23:12 to 09-01 01:00 and all six columns went stale, including four that were
-- legitimately green fifteen minutes earlier.
--
-- The default behaved exactly as designed -- it cost a re-run rather than granting a false
-- green, which is the direction that safe defaults are supposed to fail in. But it was wrong
-- on the merits, and the reason is a convention 0140 established and then did not enforce:
--
--   EVERY MIGRATION CLASSIFIES ITSELF. A migration that changes the engine, the fingerprint,
--   or the pair verdict says nothing and inherits forces_recert = true. A migration that
--   changes only readers, permissions, comments, or data claims its exemption in the same
--   file that makes the change.
--
-- This file corrects 0141's omission and records the convention in the register itself, so
-- the next person to read the table sees the rule alongside the rows.

BEGIN;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
  ('the_floor_reads_the_ledger_for_every_caller', false,
   '0141: made ottoq_cert_recert_floor SECURITY DEFINER so every caller reads the same '
   'floor, and enabled RLS on this register. Security context and permissions only -- no '
   'engine, no fingerprint, no verdict, no scheduling behaviour. Exempt.'),
  ('a_migration_classifies_itself', false,
   '0142: this migration. Inserts two rows into this register and nothing else. Exempt.')
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = now();

-- Prove the correction landed where it was aimed: the floor must fall back to 0137, and the
-- four columns certified after 0137 must be green again. If the floor does not move, the
-- exemption did not match a real migration name and this file did nothing.
DO $chk$
DECLARE v_floor timestamptz; v_green int; v_stale int; v_expect timestamptz;
BEGIN
  SELECT make_timestamptz(substr(version,1,4)::int, substr(version,5,2)::int,
                          substr(version,7,2)::int, substr(version,9,2)::int,
                          substr(version,11,2)::int, substr(version,13,2)::numeric, 'UTC')
    INTO v_expect
    FROM supabase_migrations.schema_migrations
   WHERE name = 'the_fingerprint_stops_hashing_a_write_timestamp';

  IF v_expect IS NULL THEN
    RAISE EXCEPTION '0142: 0137 is not in the migration ledger; cannot verify the floor';
  END IF;

  v_floor := public.ottoq_cert_recert_floor();
  IF v_floor <> v_expect THEN
    RAISE EXCEPTION '0142: floor is % but 0137 is at % -- an unclassified migration is still '
                    'holding the floor up', v_floor, v_expect;
  END IF;

  SELECT count(*) FILTER (WHERE green), count(*) FILTER (WHERE stale)
    INTO v_green, v_stale FROM public.ottoq_cert_matrix();
  IF v_green = 0 THEN
    RAISE EXCEPTION '0142: floor is correct at % but no column recovered', v_floor;
  END IF;
  RAISE NOTICE '0142: floor back to %, % green, % stale.', v_floor, v_green, v_stale;
END
$chk$;

COMMIT;
