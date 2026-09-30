-- migration-version: PENDING
-- migration-name:    the_twin_prices_power_at_nashvilles_published_rate
--
-- 0574  **The twin depot's price of power is Nashville's published time-of-use rate, not an unsourced table.** Lane A
--       energy. Sources and the reasoning: docs/research/direct/2026-09-30-lane-a-energy-price.md.
--
-- ══ §1 WHY ════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Chase, 2026-09-29, 8:20 PM CT, put energy savings first: "energy savings (through Bess, solar, and forward
--   planning/scheduling)". The twin priced a day's energy from two sources that disagree:
--     - demand charges from Nashville Electric Service's published rate (GSA Part 3, sourced 2026-07-09); and
--     - energy from six `ottoq_tariff_windows` rows created 2026-05-28 with no source, running from $0.052 to a $0.235
--       summer "super peak". They also left spring and fall 1-8 PM with no window at all, so the reader fell back to a
--       flat $0.10.
--   NES's large commercial rates have no such spread. OTTO-Q's battery and forward plan read these prices every tick
--   (`twin.ottoq_sim_current_tariff`, `ottoq_bess_day_plan`), so they were planning against prices that do not exist.
--   Any energy saving measured in them would have been measured in fiction.
--
-- ══ §2 WHAT THIS CHANGES (the twin depot only; rule 8) ════════════════════════════════════════════════════════════════
--
--   The twin depot's six windows are set inactive (kept, not deleted). Five windows take their place: NES Schedule TGSA
--   Part 3 (effective October 2024), plus TVA's fuel cost adjustment as NES lists it for September (2.515 c/kWh).
--     summer   (Jun-Sep)  on_peak  13:00-19:00  0.08182 $/kWh   (5.667 + 2.515 c)
--                         off_peak all hours   0.06724          (4.209 + 2.515 c)
--     winter   (Dec-Feb)  on_peak  04:00-10:00  0.07719          (5.204 + 2.515 c)
--                         off_peak all hours   0.07054          (4.539 + 2.515 c)
--     shoulder (the rest) mid_peak all hours   0.07187          (4.672 + 2.515 c; NES's transition months are flat)
--   The reader takes the highest active window for the hour, so on-peak wins in its hours. The labels are values of the
--   `tariff_label` enum the site-energy snapshot stores.
--   Demand charges are not touched: TGSA-3's are GSA-3's, which `ottoq_depot_tariffs` already holds.
--
--   Two limits of the reader, noted rather than changed, because neither affects a sweep day (every one is a Tuesday in
--   September):
--     - it maps March to its "shoulder", where NES counts March as winter;
--     - it does not read `day_of_week_mask`, so it prices weekend hours as weekdays. The on-peak rows carry mask 62
--       (Monday-Friday) so the data says what NES says.
--
--   What this does to the battery, predicted here from the planner's own rule and measured by night 2 (0575): the day
--   plan (0435) discharges to trade only where price exceeds refill cost plus wear, i.e. the season's lowest rate over
--   the round trip plus `bess_plan_degradation_usd_kwh`. At the twin's battery (round trip 0.96, wear $0.02) that is
--   6.724 / 0.96 + 2.0 = 9.004 c against an on-peak 8.182 c, so under NES the battery stops trading on price in every
--   season and works only to cut the month's peak half hour and to bank surplus solar. The old table paid up to 16 c
--   a kWh for trading. Measured on the smoke arm's own BESS commands (88e46ad3, 6-8 AM): of the 1,135 kWh it charged,
--   508.8 kWh was `worth_more_later` at $0.092 against a $0.235 spare price, which these prices remove; the other 626.4
--   kWh was `restore_dr_reserve`, because that seed started the battery at 21%, under the 600 kWh demand-response
--   reserve. Night 2's three seeds start it at 65%, 70% and 94%.
--
--   Every other reader of these rows was checked: `ottoq_bess_day_plan` prices each step through the reader and takes
--   the season's lowest active rate as its refill cost, which the overlapping windows answer correctly (summer 0.06724,
--   winter 0.07054, shoulder 0.07187); the `ottoq-energy-optimize` edge function ranks labels, so on_peak outranks the
--   all-day off_peak, and only OttoCommand's `get_energy_status` reaches it, never the tick.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: no run is live at the twin depot. P2: the reader is the function measured (md5
--   8f93e635552b6be131f7e54e8eb1f54b of its source), and the twin's windows are the six measured on 2026-09-29
--   (fingerprint fa2b6da72a5eb00485257630d306180e). P3: not already applied. The six old windows go to
--   `ottoq_schema_snapshots` as a '0574_pre' table row. V1: the reader returns the published price at six moments across
--   the three seasons, on-peak and off. V2: the twin has exactly the five new windows active and the six old ones retired, and every other
--   depot's windows are byte for byte what they were.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert TRUE and forces_dial_restart TRUE. The battery's plan and every arm's energy cost read these prices.
--
-- ROLLBACK: DELETE FROM public.ottoq_tariff_windows WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND active;
--   UPDATE public.ottoq_tariff_windows SET active = true
--    WHERE tariff_id IN (SELECT (e->>'tariff_id')::uuid FROM public.ottoq_schema_snapshots s,
--                               jsonb_array_elements(s.definition::jsonb) e WHERE s.label = '0574_pre');
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0574_the_twin_prices_power_at_nashvilles_published_rate'.

BEGIN;

-- ── P0: nothing in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0574 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

-- ── P1: no live run at the twin depot ──
DO $live$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs
              WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status IN ('initializing', 'running', 'paused')) THEN
    RAISE EXCEPTION '0574 P1: a run is live at the twin depot';
  END IF;
END $live$;

-- ── P2: the reader and the six windows measured on 2026-09-29 ──
DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'twin.ottoq_sim_current_tariff(uuid,timestamp with time zone)'::regprocedure)
     IS DISTINCT FROM '8f93e635552b6be131f7e54e8eb1f54b' THEN
    RAISE EXCEPTION '0574 P2: twin.ottoq_sim_current_tariff is not the reader measured on 2026-09-29';
  END IF;
  IF (SELECT md5(string_agg(format('%s|%s|%s|%s|%s|%s|%s', label, rate_usd_per_kwh, hour_start, hour_end,
                                   day_of_week_mask, season, active), ';' ORDER BY label, season, hour_start))
        FROM public.ottoq_tariff_windows WHERE depot_id = '11111111-1111-1111-1111-111111111111')
     IS DISTINCT FROM 'fa2b6da72a5eb00485257630d306180e' THEN
    RAISE EXCEPTION '0574 P2: the twin depot''s tariff windows are not the six measured on 2026-09-29';
  END IF;
  -- every other depot's windows, fingerprinted for V2
  PERFORM set_config('ottoq.m0574_others',
                     COALESCE((SELECT md5(string_agg(to_jsonb(w)::text, ';' ORDER BY w.tariff_id))
                                 FROM public.ottoq_tariff_windows w
                                WHERE w.depot_id <> '11111111-1111-1111-1111-111111111111'), 'none'), true);
END $premises$;

-- ── P3: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0574_the_twin_prices_power_at_nashvilles_published_rate') THEN
    RAISE EXCEPTION '0574 P3: already applied';
  END IF;
END $once$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0574_pre', 'table_row', 'public', 'ottoq_tariff_windows', d::text, md5(d::text)
  FROM (SELECT jsonb_agg(to_jsonb(w) ORDER BY w.label, w.season, w.hour_start) AS d
          FROM public.ottoq_tariff_windows w WHERE w.depot_id = '11111111-1111-1111-1111-111111111111') x;

UPDATE public.ottoq_tariff_windows SET active = false
 WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND active;

INSERT INTO public.ottoq_tariff_windows (depot_id, label, rate_usd_per_kwh, hour_start, hour_end, day_of_week_mask, season, active)
VALUES
  -- NES Schedule TGSA Part 3 (effective October 2024) + TVA fuel cost adjustment 2.515 c/kWh (NES, September)
  ('11111111-1111-1111-1111-111111111111', 'on_peak',  0.08182, 13, 19,  62, 'summer',   true),
  ('11111111-1111-1111-1111-111111111111', 'off_peak', 0.06724,  0, 24, 127, 'summer',   true),
  ('11111111-1111-1111-1111-111111111111', 'on_peak',  0.07719,  4, 10,  62, 'winter',   true),
  ('11111111-1111-1111-1111-111111111111', 'off_peak', 0.07054,  0, 24, 127, 'winter',   true),
  ('11111111-1111-1111-1111-111111111111', 'mid_peak', 0.07187,  0, 24, 127, 'shoulder', true);

-- ── V1: the reader returns the published price, across the seasons ──
DO $v1$
DECLARE r record; got record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('2026-09-01 14:30:00-05'::timestamptz, 'on_peak',  0.08182::numeric),   -- a September Tuesday, 2:30 PM CDT
      ('2026-09-01 09:00:00-05',              'off_peak', 0.06724),
      ('2026-09-01 19:00:00-05',              'off_peak', 0.06724),            -- on-peak ends at 7 PM
      ('2026-01-13 05:00:00-06',              'on_peak',  0.07719),            -- a January Tuesday, 5 AM CST
      ('2026-01-13 12:00:00-06',              'off_peak', 0.07054),
      ('2026-04-14 15:00:00-05',              'mid_peak', 0.07187)) x(at, lbl, rate)  -- April: flat
  LOOP
    SELECT * INTO got FROM twin.ottoq_sim_current_tariff('11111111-1111-1111-1111-111111111111', r.at);
    IF got.out_label IS DISTINCT FROM r.lbl OR got.out_rate_usd_kwh IS DISTINCT FROM r.rate THEN
      RAISE EXCEPTION '0574 V1: at % the reader says % %, not % %', r.at, got.out_label, got.out_rate_usd_kwh, r.lbl, r.rate;
    END IF;
  END LOOP;
END $v1$;

-- ── V2: exactly the five new windows at the twin; no other depot touched ──
DO $v2$
BEGIN
  IF (SELECT count(*) FROM public.ottoq_tariff_windows
       WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND active) <> 5
  OR (SELECT count(*) FROM public.ottoq_tariff_windows
       WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND NOT active) <> 6 THEN
    RAISE EXCEPTION '0574 V2: the twin does not hold five active and six retired windows';
  END IF;
  IF COALESCE((SELECT md5(string_agg(to_jsonb(w)::text, ';' ORDER BY w.tariff_id))
                  FROM public.ottoq_tariff_windows w
                 WHERE w.depot_id <> '11111111-1111-1111-1111-111111111111'), 'none')
     IS DISTINCT FROM current_setting('ottoq.m0574_others') THEN
    RAISE EXCEPTION '0574 V2: another depot''s windows changed';
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0574_the_twin_prices_power_at_nashvilles_published_rate', true, true,
  'Lane A energy (docs/research/direct/2026-09-30-lane-a-energy-price.md). The twin depot''s six unsourced tariff windows '
  '($0.052-$0.235) are retired; five windows of NES Schedule TGSA Part 3 plus TVA''s September fuel cost adjustment '
  '(summer 8.182 c on-peak 1-7 PM, 6.724 c off-peak; winter 7.719 c 4-10 AM, 7.054 c; shoulder 7.187 c flat) take '
  'their place. The battery''s plan and every arm''s energy cost read them.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
