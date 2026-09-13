-- migration-version: 20260913233201
-- migration-name:    0273_the_uplink_is_written_by_the_same_transaction_as_the_downlink
--
-- 0273  THE UPLINK IS WRITTEN BY THE SAME TRANSACTION AS THE DOWNLINK
--
-- ---------------------------------------------------------------------------
-- THE FORGED HANDSHAKE, MEASURED
--
-- ottoq_vehicle_commands is the outbound channel: OTTO-Q tells an asset where
-- to go. 794,745 rows, 794,332 of them carrying a confirmation. Every one of
-- those confirmations was written by OTTO-Q or its twin:
--
--   otto_q_preflight            721,741
--   run_finalizer                25,704
--   otto_q_preflight_refusal     21,318
--   otto_q_preflight_supersede   19,431
--   twin_auto_tech                5,548
--   otto_q_preflight_error          590
--   (unconfirmed)                   413
--
-- Six names, all ours. The ack function's own default actor 'oem_fleet' and
-- the hardware bridge's 'robovac_bridge' appear ZERO times. The uplink is
-- written in the same transaction as the downlink.
--
-- That is not a bug in any one function -- for a twin it is the correct
-- behaviour, because the twin IS the asset. It is a MEASUREMENT problem, and a
-- serious one: no number anywhere in this system distinguishes
--
--     "the asset was told"     from     "we decided".
--
-- Every count of confirmed commands reads as evidence of a working two-way
-- link. None of it is. A demo that quotes 794,332 confirmations is quoting
-- OTTO-Q agreeing with itself 794,332 times.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS MIGRATION ADDS, AND WHAT IT DELIBERATELY DOES NOT
--
-- Three distinct facts, where today there is one:
--
--   ISSUED     OTTO-Q composed the command.            (exists: issued_at)
--   DELIVERED  it left OTTO-Q through an outbound      (new: delivered_at,
--              channel and something took it.           delivered_to)
--   ACKED      somebody said what happened to it.      (exists: confirmed_by)
--              WHO that somebody is, is the question    (new: the registry)
--              the ack column cannot answer alone.
--
--   * delivered_at / delivered_to are NULL on all 794,745 existing rows and
--     that is the true value: nothing has ever been delivered through a
--     counted channel. Nullable, no backfill, no table rewrite.
--
--   * ottoq_fleet_claim_commands() is the LEASE -- the mutating counterpart to
--     the read-only peek 0271 fixed. Claiming stamps delivery. Peeking does
--     not, and ottoq_fleet_pending_commands stays STABLE so a dashboard poll
--     can never manufacture a delivery.
--
--   * ottoq_command_actor_registry says what an ack actor NAME MEANS -- self
--     (OTTO-Q or its twin), operator (a human at an OTTOYARD console), or
--     external (the asset or its fleet backend). An unregistered name reads
--     'self': the fail-closed direction, because over-claiming an external
--     ack is exactly the error this migration exists to stop.
--
--   * ottoq_command_handshake publishes the split. Today it will read
--     acked_by_asset = 0 on every row, and that is the point: the number
--     becomes quotable instead of buried.
--
-- WHAT IT DOES NOT DO, said plainly rather than implied:
--
--   The actor string is SELF-DECLARED. ottoq_ack_vehicle_command takes
--   p_actor text DEFAULT 'oem_fleet' and writes it verbatim. EXECUTE on that
--   function is held by authenticated and service_role and was revoked from
--   anon by G2, so acking at all requires a signed-in role -- but nothing
--   proves the caller is the asset it claims to be. The registry tells you
--   what a name means; it does not authenticate the name. Closing that is an
--   authentication change (per-asset credentials on the ingest seam), not a
--   schema change, and it is out of this migration's scope. Recorded here so
--   the handshake view is never read as stronger than it is.
--
--   It also does not touch the twin. The twin confirming its own commands is
--   correct; it is the asset. What changes is that the view can now say so.
--
-- forces_recert = FALSE. h_cmd -- in all three producers -- is built from an
-- explicit six-column list (issued_at | vehicle_id | command_type | stall_id |
-- status | reason_code). delivered_at, delivered_to and the registry are
-- outside it, no engine function calls the new claim function, and the twin's
-- confirm path is unmodified. P4 checks the column list positively and A6
-- re-verifies the pair's prosrc pin.
-- ---------------------------------------------------------------------------

-- ===========================================================================
-- PRE-FLIGHT
-- ===========================================================================
DO $pre$
DECLARE v_n int; v_foreign int; v_conf bigint;
BEGIN
  -- P1: refuse to double-apply.
  SELECT count(*) INTO v_n FROM information_schema.columns
   WHERE table_schema='public' AND table_name='ottoq_vehicle_commands'
     AND column_name IN ('delivered_at','delivered_to');
  IF v_n <> 0 THEN RAISE EXCEPTION '0273 P1: delivery columns already exist (%)', v_n; END IF;
  IF to_regclass('public.ottoq_command_actor_registry') IS NOT NULL THEN
    RAISE EXCEPTION '0273 P1: ottoq_command_actor_registry already exists';
  END IF;
  IF to_regclass('public.ottoq_command_handshake') IS NOT NULL THEN
    RAISE EXCEPTION '0273 P1: ottoq_command_handshake already exists';
  END IF;

  -- P2: 0271 must be in place. This migration's production/twin split reads
  -- the column 0271 added; without it the handshake view would be blind to
  -- the only distinction that makes the numbers mean anything.
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='ottoq_vehicle_commands'
                    AND column_name='data_source') THEN
    RAISE EXCEPTION '0273 P2: ottoq_vehicle_commands.data_source is missing -- apply 0271 first';
  END IF;

  -- P3: THE CONVICTION. Not one confirmation in the table's whole life was
  -- written by an actor this migration would classify as anything but us.
  SELECT count(*) INTO v_foreign
    FROM (SELECT DISTINCT confirmed_by FROM public.ottoq_vehicle_commands
           WHERE confirmed_by IS NOT NULL) d
   WHERE d.confirmed_by NOT IN ('otto_q_preflight','otto_q_preflight_refusal',
                                'otto_q_preflight_supersede','otto_q_preflight_error',
                                'run_finalizer','twin_auto_tech','decide_tick');
  IF v_foreign <> 0 THEN
    RAISE EXCEPTION '0273 P3: % ack actors outside the known-internal set already exist; '
                    'read them and widen the registry seed before applying', v_foreign;
  END IF;
  SELECT count(*) INTO v_conf FROM public.ottoq_vehicle_commands WHERE confirmed_by IS NOT NULL;
  IF v_conf < 1000 THEN
    RAISE EXCEPTION '0273 P3: only % confirmations exist; the premise is not established', v_conf;
  END IF;
  RAISE NOTICE '0273 P3: % confirmations, 0 of them from outside OTTO-Q', v_conf;

  -- P4: the certified command hash names its columns, so new ones cannot
  -- enter it. Positive form: all three producers, or this assertion means
  -- nothing if a producer is renamed away.
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname IN ('ottoq_determinism_pair','ottoq_determinism_pair_replay','ottoq_ab_arm_atoms')
     AND p.prosrc ~ 'issued_at::text\|\|''\|''\|\|vehicle_id::text';
  IF v_n <> 3 THEN
    RAISE EXCEPTION '0273 P4: expected 3 h_cmd producers naming their columns explicitly, found %', v_n;
  END IF;
END $pre$;

-- ===========================================================================
-- THE CHANGE
-- ===========================================================================

-- (a) delivery, as two nullable facts. NULL is the true current value on every
--     existing row, so there is nothing to backfill and nothing to rewrite.
ALTER TABLE public.ottoq_vehicle_commands
  ADD COLUMN delivered_at timestamptz,
  ADD COLUMN delivered_to text;

COMMENT ON COLUMN public.ottoq_vehicle_commands.delivered_at IS
  '0273: when this command actually left OTTO-Q through an outbound channel. '
  'Written only by ottoq_fleet_claim_commands. NULL means never delivered -- '
  'which is the truth for every row issued before this migration.';
COMMENT ON COLUMN public.ottoq_vehicle_commands.delivered_to IS
  '0273: which channel or actor took delivery. Set once, with the first claim.';

-- (b) what an ack actor name means. Kept as data, not a CASE in a view, so
--     adding an OEM is a row and not a migration.
CREATE TABLE public.ottoq_command_actor_registry (
  actor         text PRIMARY KEY,
  kind          text NOT NULL CHECK (kind IN ('self','operator','external')),
  note          text,
  registered_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.ottoq_command_actor_registry IS
  '0273: classifies ottoq_vehicle_commands.confirmed_by. self = OTTO-Q or its '
  'twin acking its own command; operator = a human at an OTTOYARD console; '
  'external = the asset or its fleet backend. An UNREGISTERED name reads '
  '''self'' -- the fail-closed direction, because over-claiming an external '
  'ack is the error this table exists to prevent. Registration says what a '
  'name means; it does not authenticate the name.';

INSERT INTO public.ottoq_command_actor_registry (actor, kind, note) VALUES
  ('otto_q_preflight',           'self',     'the emitter accepting its own command pre-flight'),
  ('otto_q_preflight_refusal',   'self',     'the emitter refusing its own command pre-flight'),
  ('otto_q_preflight_supersede', 'self',     'the emitter superseding its own earlier command'),
  ('otto_q_preflight_error',     'self',     'the emitter closing a command after an error'),
  ('run_finalizer',              'self',     'run teardown expiring commands the run left open'),
  ('twin_auto_tech',             'self',     'the twin standing in for a technician'),
  ('decide_tick',                'self',     'the decide path, if it ever acks directly'),
  ('cockpit_recall',             'operator', 'a human recalling a vehicle from the OTTOYARD cockpit'),
  ('cockpit',                    'operator', 'a human at an OTTOYARD console'),
  ('oem_fleet',                  'external', 'an OEM fleet backend -- ottoq_ack_vehicle_command''s default actor'),
  ('robovac_bridge',             'external', 'the hardware-lab robot bridge'),
  ('vehicle',                    'external', 'the asset itself');

-- (c) the lease. The mutating counterpart to the read-only peek: claiming is
--     what makes a delivery true, and only claiming.
CREATE OR REPLACE FUNCTION public.ottoq_fleet_claim_commands(
  p_depot_id           uuid    DEFAULT NULL,
  p_fleet_operator_id  uuid    DEFAULT NULL,
  p_limit              integer DEFAULT 200,
  p_actor              text    DEFAULT NULL)
RETURNS TABLE(command_id uuid, vehicle_id uuid, vehicle_ref text, command_type text,
              payload jsonb, issued_at timestamptz, issued_by text, status text,
              delivered_at timestamptz, delivered_to text)
LANGUAGE plpgsql
VOLATILE SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
DECLARE v_actor text := COALESCE(NULLIF(p_actor,''), current_user);
BEGIN
  RETURN QUERY
  WITH picked AS (
    SELECT c.command_id AS cid
      FROM ottoq_vehicle_commands c
      JOIN vehicles v ON v.id = c.vehicle_id
     WHERE c.status = 'issued'
       AND c.data_source = 'production'          -- 0271's rule; a twin command is never delivered
       AND (p_depot_id IS NULL OR c.depot_id = p_depot_id)
       AND (p_fleet_operator_id IS NULL OR v.fleet_operator_id = p_fleet_operator_id)
     ORDER BY c.issued_at DESC
     LIMIT GREATEST(1, LEAST(p_limit, 1000))
    FOR UPDATE OF c SKIP LOCKED
  ), leased AS (
    UPDATE ottoq_vehicle_commands u
       SET delivered_at = COALESCE(u.delivered_at, now()),   -- first delivery wins;
           delivered_to = COALESCE(u.delivered_to, v_actor)  -- a re-poll is not a new one
      FROM picked
     WHERE u.command_id = picked.cid
    RETURNING u.command_id, u.vehicle_id, u.command_type, u.payload,
              u.issued_at, u.issued_by, u.status, u.delivered_at, u.delivered_to
  )
  SELECT l.command_id, l.vehicle_id, veh.display_name, l.command_type, l.payload,
         l.issued_at, l.issued_by, l.status, l.delivered_at, l.delivered_to
    FROM leased l JOIN vehicles veh ON veh.id = l.vehicle_id
   ORDER BY l.issued_at DESC;
END $fn$;

COMMENT ON FUNCTION public.ottoq_fleet_claim_commands(uuid,uuid,integer,text) IS
  '0273: the outbound LEASE. Returns the same production commands as '
  'ottoq_fleet_pending_commands and stamps delivered_at/delivered_to as it '
  'does. Poll with the peek; take with the claim. First delivery wins, so a '
  'retry does not overwrite when the command actually went out.';

REVOKE ALL ON FUNCTION public.ottoq_fleet_claim_commands(uuid,uuid,integer,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ottoq_fleet_claim_commands(uuid,uuid,integer,text)
  TO authenticated, service_role;

-- (d) the split, published.
CREATE OR REPLACE VIEW public.ottoq_command_handshake AS
SELECT c.data_source,
       count(*)                                                       AS issued_total,
       count(*) FILTER (WHERE c.delivered_at IS NOT NULL)              AS delivered,
       count(*) FILTER (WHERE c.confirmed_by IS NOT NULL)              AS acked,
       count(*) FILTER (WHERE c.confirmed_by IS NOT NULL
                          AND COALESCE(r.kind,'self') = 'self')        AS acked_by_us,
       count(*) FILTER (WHERE COALESCE(r.kind,'self') = 'operator')    AS acked_by_operator,
       count(*) FILTER (WHERE COALESCE(r.kind,'self') = 'external')    AS acked_by_asset,
       min(c.issued_at)                                                AS first_issued,
       max(c.issued_at)                                                AS last_issued
  FROM public.ottoq_vehicle_commands c
  LEFT JOIN public.ottoq_command_actor_registry r ON r.actor = c.confirmed_by
 GROUP BY c.data_source;

COMMENT ON VIEW public.ottoq_command_handshake IS
  '0273: separates "the asset was told" from "we decided". acked_by_us is '
  'OTTO-Q agreeing with itself; acked_by_asset is a real uplink. Quote both '
  'or neither. The actor name is self-declared -- see 0273''s header.';

GRANT SELECT ON public.ottoq_command_handshake TO authenticated, service_role;

-- ===========================================================================
-- POST
-- ===========================================================================
DO $post$
DECLARE
  v_n int; v_lab uuid; v_veh uuid; v_run uuid;
  v_c uuid; v_d1 timestamptz; v_d2 timestamptz; v_to text;
  v_ext_before bigint; v_ext_after bigint; v_kind text;
BEGIN
  -- A1: the registry is seeded and constrained in both directions.
  SELECT count(*) INTO v_n FROM public.ottoq_command_actor_registry;
  IF v_n <> 12 THEN RAISE EXCEPTION '0273 A1: registry holds % rows, expected 12', v_n; END IF;
  IF (SELECT count(DISTINCT kind) FROM public.ottoq_command_actor_registry) <> 3 THEN
    RAISE EXCEPTION '0273 A1: the registry does not use all three kinds -- a one-sided taxonomy classifies nothing';
  END IF;

  -- A2: the honest number, published. Nothing delivered, nothing acked by an
  -- asset, on any provenance.
  IF EXISTS (SELECT 1 FROM public.ottoq_command_handshake WHERE delivered <> 0) THEN
    RAISE EXCEPTION '0273 A2: something reads as delivered before anything has been claimed';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_command_handshake WHERE acked_by_asset <> 0) THEN
    RAISE EXCEPTION '0273 A2: an asset ack appeared out of nowhere -- the seed is wrong';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_command_handshake WHERE acked_by_us > 700000) THEN
    RAISE EXCEPTION '0273 A2: the twin row does not show the self-acks the header measured';
  END IF;

  -- A3: an UNREGISTERED actor reads 'self', not 'external'. The fail-closed
  -- direction, asserted rather than assumed.
  SELECT COALESCE(r.kind,'self') INTO v_kind
    FROM (SELECT 'some_actor_nobody_registered'::text AS a) x
    LEFT JOIN public.ottoq_command_actor_registry r ON r.actor = x.a;
  IF v_kind <> 'self' THEN
    RAISE EXCEPTION '0273 A3: an unregistered actor classifies as % -- it must fail closed to self', v_kind;
  END IF;

  -- A4: THE LIVE LEASE. Peek does not deliver; claim does; a second claim does
  -- not move the stamp.
  SELECT d.id INTO v_lab FROM public.depots d
   WHERE d.feed_mode='external' AND d.name NOT ILIKE '%retired%' ORDER BY d.id LIMIT 1;
  SELECT v.id INTO v_veh FROM public.vehicles v WHERE v.current_depot_id = v_lab ORDER BY v.id LIMIT 1;
  SELECT r.sim_run_id INTO v_run FROM public.ottoq_sim_runs r
   WHERE r.run_by='production_live' ORDER BY r.started_at DESC LIMIT 1;
  IF v_lab IS NULL OR v_veh IS NULL OR v_run IS NULL THEN
    RAISE EXCEPTION '0273 A4: need a real external depot, a vehicle at it, and a production run';
  END IF;

  INSERT INTO public.ottoq_vehicle_commands
    (sim_run_id, depot_id, vehicle_id, command_type, payload, issued_at, issued_by, status)
  VALUES (v_run, v_lab, v_veh, 'stage', '{"probe":"0273-A4"}'::jsonb, now(), 'migration_0273', 'issued')
  RETURNING command_id INTO v_c;

  PERFORM count(*) FROM public.ottoq_fleet_pending_commands(v_lab, NULL, 1000);
  SELECT delivered_at INTO v_d1 FROM public.ottoq_vehicle_commands WHERE command_id = v_c;
  IF v_d1 IS NOT NULL THEN
    RAISE EXCEPTION '0273 A4: the read-only peek manufactured a delivery';
  END IF;

  PERFORM count(*) FROM public.ottoq_fleet_claim_commands(v_lab, NULL, 1000, 'probe_transport');
  SELECT delivered_at, delivered_to INTO v_d1, v_to
    FROM public.ottoq_vehicle_commands WHERE command_id = v_c;
  IF v_d1 IS NULL OR v_to <> 'probe_transport' THEN
    RAISE EXCEPTION '0273 A4: the claim did not stamp delivery (at=%, to=%)', v_d1, v_to;
  END IF;

  PERFORM count(*) FROM public.ottoq_fleet_claim_commands(v_lab, NULL, 1000, 'a_later_transport');
  SELECT delivered_at, delivered_to INTO v_d2, v_to
    FROM public.ottoq_vehicle_commands WHERE command_id = v_c;
  IF v_d2 <> v_d1 OR v_to <> 'probe_transport' THEN
    RAISE EXCEPTION '0273 A4: a re-poll overwrote the moment the command actually went out';
  END IF;

  -- A5: and the split moves when a real external actor acks. confirmed_by is
  -- set directly rather than through ottoq_ack_vehicle_command, because that
  -- function emits a signed event and this probe row is about to be deleted;
  -- what is under test is the classification, not the ack RPC.
  SELECT acked_by_asset INTO v_ext_before
    FROM public.ottoq_command_handshake WHERE data_source='production';
  UPDATE public.ottoq_vehicle_commands
     SET status='executed', confirmed_at=now(), confirmed_by='oem_fleet', executed_at=now()
   WHERE command_id = v_c;
  SELECT acked_by_asset INTO v_ext_after
    FROM public.ottoq_command_handshake WHERE data_source='production';
  IF v_ext_after <> v_ext_before + 1 THEN
    RAISE EXCEPTION '0273 A5: an oem_fleet ack did not register as an asset ack (% -> %)',
                    v_ext_before, v_ext_after;
  END IF;

  DELETE FROM public.ottoq_vehicle_commands WHERE command_id = v_c;
  IF (SELECT count(*) FROM public.ottoq_vehicle_commands WHERE issued_by='migration_0273') <> 0 THEN
    RAISE EXCEPTION '0273: probe row survived cleanup';
  END IF;
  IF (SELECT acked_by_asset FROM public.ottoq_command_handshake WHERE data_source='production')
     <> v_ext_before THEN
    RAISE EXCEPTION '0273: the probe left the published number moved';
  END IF;

  -- A6: the certified path is untouched.
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair')
     IS DISTINCT FROM '8a35b8c874fed154cc216140faec0274' THEN
    RAISE EXCEPTION '0273 A6: ottoq_determinism_pair changed -- forces_recert is not FALSE';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
              WHERE n.nspname IN ('public','ottoq','twin')
                AND p.proname <> 'ottoq_fleet_claim_commands'
                AND p.prosrc ~ 'ottoq_fleet_claim_commands') THEN
    RAISE EXCEPTION '0273 A6: something already calls the claim function; it must have no engine caller';
  END IF;

  RAISE NOTICE '0273: A1-A6 passed. Delivery and acceptance are now separate facts, '
               'and the honest count of asset acks (zero) is published rather than buried.';
END $post$;

-- ===========================================================================
-- CLASSIFICATION -- written here, not in a follow-up. See 0272.
-- ===========================================================================
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0273_the_uplink_is_written_by_the_same_transaction_as_the_downlink', false,
  'Adds ottoq_vehicle_commands.delivered_at/delivered_to (both nullable, no backfill, no '
  'rewrite), the ottoq_command_actor_registry classification table, the '
  'ottoq_fleet_claim_commands lease, and the ottoq_command_handshake view. FALSE with proof: '
  'h_cmd is built in all three producers from an explicit six-column list (issued_at | '
  'vehicle_id | command_type | stall_id | status | reason_code), checked positively by P4, so '
  'the new columns cannot enter the verdict; no engine function calls the claim function, '
  'asserted by A6; the twin''s confirm path and ottoq_ack_vehicle_command are unmodified; and '
  'A6 re-verifies the pair''s prosrc pin 8a35b8c874fed154cc216140faec0274 unchanged.',
  now());

-- ---------------------------------------------------------------------------
-- APPLY LOG
-- Applied 2026-09-13 23:32:01 UTC as version 20260913233201 (6:32 PM CT).
--
-- Dry-run byte for byte inside BEGIN ... ROLLBACK first; P1-P4 and A1-A6
-- passed there and again on apply.
--
-- LIVE VERIFICATION AFTER APPLY -- ottoq_command_handshake, read back:
--
--   data_source   issued   delivered   acked     by_us   by_operator  by_asset
--   production         1           0       0         0             0         0
--   twin         794,744           0 794,332   794,332             0         0
--
-- That bottom-right zero is the whole point of the migration. It was always
-- true; it was never sayable. Every previous count of "confirmed commands"
-- was 794,332 instances of OTTO-Q agreeing with itself, and nothing in the
-- schema could tell you so.
--
-- ottoq_cert_recert_floor() unmoved at 2026-09-12 16:50:23.319089+00 -- the
-- classification INSERT at the foot of this file is why, and it is here
-- rather than in a follow-up because 0272 made that a CI-enforced rule after
-- 0267 and 0271 both forgot it.
--
-- ottoq_command_actor_registry: 12 rows, all three kinds used.
--
-- NOTE FOR WHOEVER READS THE HANDSHAKE VIEW NEXT. delivered will stay 0 until
-- something actually calls ottoq_fleet_claim_commands from outside the
-- database. The lease exists and is proven (A4: the peek does not stamp, the
-- claim does, a re-poll does not overwrite), but no transport calls it yet.
-- "The mechanism exists" is not "the mechanism runs" -- that is the same
-- DECLARED / WIRED / INVOKED / FOLLOWED distinction this file was written to
-- make measurable, and this migration only reaches WIRED.
-- ---------------------------------------------------------------------------
