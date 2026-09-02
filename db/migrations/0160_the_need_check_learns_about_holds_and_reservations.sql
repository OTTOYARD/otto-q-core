-- =====================================================================
-- 0160  The need check learns about holds and reservations
--       INSTRUMENT. Harness only; forces_recert = false.
--       SUPERSEDED IN PART BY 0160r - see that file. This one anchored on
--       a line that occurs twice and broke check 12; both are kept in the
--       repo because the mistake is the lesson.
-- =====================================================================
-- Found in real time by running the 0159 three-mode A/B on grid-starve:
-- mode 2 (deadline_aware) failed charge_point_matches_the_asset_need while
-- modes 0 and 1 passed. Two instrument gaps, same family as 0154 and 0157 -
-- the check did not know facts the engine acts on:
--
--   (a) A mode-2 HOLD is a legitimate reason to end up off the wanted type.
--       The rationale records held_for_wanted='slow_point_misses_due_at',
--       but the check only accepted power_downgrade='true'.
--   (b) A point of the wanted type RESERVED FOR ANOTHER VEHICLE is not
--       available to this one - the proposer excludes it via (reserved_by IS
--       NULL OR reserved_by = me OR reservation expired) - yet the check
--       counted it as "a point of the wanted type was free", making a correct
--       assignment look like a violation. This is the first time the
--       reservation mechanism is represented in any assertion (GAP 4 in
--       db/checks/0076).
-- =====================================================================

DO $patch$
DECLARE v_src text; v_before text; v_after text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_grid_assert';

  v_before := '           OR COALESCE(d.enacted_action->''rationale''->>''power_downgrade'',''false'') = ''true''';
  v_after  := v_before || chr(10)
           || '           OR COALESCE(d.enacted_action->''rationale''->>''held_for_wanted'',''-'') <> ''-''  /* 0160 */';
  IF position(v_before IN v_src) = 0 THEN RAISE EXCEPTION '0160/a: power_downgrade clause not found'; END IF;
  v_src := replace(v_src, v_before, v_after);

  -- DEFECT, kept for the record: this anchor occurs TWICE (check 5 and check
  -- 12). replace() rewrote both and check 12 lost its FROM-clause alias.
  -- 0160r strips both copies and re-inserts one on a unique anchor.
  v_before := '                             AND s2.ocpp_charger_id IS NOT NULL';
  v_after  := v_before || chr(10)
           || '                             AND (s2.reserved_by IS NULL OR s2.reserved_by = d.entity_id'
           || ' OR s2.reservation_expires_at <= d.sim_clock)  /* 0160 */';
  IF position(v_before IN v_src) = 0 THEN RAISE EXCEPTION '0160/b: wanted-type stall predicate not found'; END IF;
  v_src := replace(v_src, v_before, v_after);

  EXECUTE v_src;
END $patch$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('the_need_check_learns_about_holds_and_reservations', false,
        'Harness: charge_point_matches_the_asset_need now accepts a declared deadline hold (0159) as an explanation for landing off the wanted type, and stops counting a point reserved for another vehicle as free. First representation of the reservation mechanism in any assertion. See 0160r for the anchor repair.',
        now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
