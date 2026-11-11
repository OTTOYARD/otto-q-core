-- migration-version: PENDING
-- migration-name:    five_standard_chargers_no_stall_names_are_decommissioned
--
-- 0811  **Five standard chargers no stall names are decommissioned.** (G532)
--
--   NASH-L2-21..25 are in service at the twin depot with no stall. 0759 retired L2 11..15; 0763 retired 31..35 and
--   turned 16..20 and 26..30 into fast chargers; 21..25 were in neither list (read 2026-11-11 in production and in the
--   lab's 2026-11-04 export: 35 chargers in service, 30 named by a stall). They take a heartbeat every tick and read
--   Available. No car can be sent to one. This file decommissions them as 0763 §2 (d) did 31..35.
--
--   WHY ITS OWN FILE, AND WHY IT WAITS. public.ottoq_boot_state_fingerprint hashes every charger row at the depot
--   (to_jsonb(t) less three columns), decommissioned or not, so this change moves the chargers section of the
--   end-state atom for every arm run after it: measured in the lab, chargers.world 766fd7bc.. against a234e00a.. with
--   and without it, n = 45 both. Both arms of any pair move together, so no pair disagrees; what moves is the digest a
--   later arm is compared with across certifications (G140). The world fingerprint (30 chargers, joined to stalls) does
--   not move. forces_recert TRUE for that reason; nothing acts on it while testing is off (rule 12). Applying it is
--   Chase's call, as every change to the depot's base has been (0759, 0763).
BEGIN;

DO $p0$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs
              WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status = 'running') THEN
    RAISE EXCEPTION '0811 P0: a run is live at the twin depot; apply between runs';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_ocpp_chargers c
       WHERE c.depot_id = '11111111-1111-1111-1111-111111111111' AND c.decommissioned_at IS NULL
         AND c.ocpp_identifier IN ('NASH-L2-21', 'NASH-L2-22', 'NASH-L2-23', 'NASH-L2-24', 'NASH-L2-25')
         AND NOT EXISTS (SELECT 1 FROM public.stalls s WHERE s.ocpp_charger_id = c.charger_id)) <> 5 THEN
    RAISE EXCEPTION '0811 P0: the five chargers are not as read on 2026-11-11 (in service, no stall)';
  END IF;
  CREATE TEMP TABLE ottoq_0811_before ON COMMIT DROP AS
    SELECT ottoq.ottoq_world_fingerprint_sections('11111111-1111-1111-1111-111111111111') AS fp;
END $p0$;

UPDATE public.ottoq_ocpp_chargers c
   SET decommissioned_at = now()
 WHERE c.depot_id = '11111111-1111-1111-1111-111111111111' AND c.decommissioned_at IS NULL
   AND c.ocpp_identifier IN ('NASH-L2-21', 'NASH-L2-22', 'NASH-L2-23', 'NASH-L2-24', 'NASH-L2-25')
   AND NOT EXISTS (SELECT 1 FROM public.stalls s WHERE s.ocpp_charger_id = c.charger_id);

DO $v$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_ocpp_chargers c
   WHERE c.depot_id = '11111111-1111-1111-1111-111111111111' AND c.decommissioned_at IS NULL
     AND NOT EXISTS (SELECT 1 FROM public.stalls s WHERE s.ocpp_charger_id = c.charger_id);
  IF v_n <> 0 THEN RAISE EXCEPTION '0811 V1: % chargers in service with no stall', v_n; END IF;
  IF (SELECT count(*) FROM public.ottoq_ocpp_chargers WHERE depot_id = '11111111-1111-1111-1111-111111111111'
        AND decommissioned_at IS NULL) <> 30 THEN
    RAISE EXCEPTION '0811 V1: the twin depot does not have thirty chargers in service'; END IF;
  IF ottoq.ottoq_world_fingerprint_sections('11111111-1111-1111-1111-111111111111')
     IS DISTINCT FROM (SELECT fp FROM ottoq_0811_before) THEN
    RAISE EXCEPTION '0811 V2: the world fingerprint moved'; END IF;
END $v$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0811_five_standard_chargers_no_stall_names_are_decommissioned', true, false,
        'G532. Sets decommissioned_at on NASH-L2-21..25, which no stall names. The end-state fingerprint hashes every '
        'charger row at the depot, so the end-state digest of every later arm moves (both arms of a pair together). The '
        'world fingerprint does not move. No function body changes.',
        now());

COMMIT;
