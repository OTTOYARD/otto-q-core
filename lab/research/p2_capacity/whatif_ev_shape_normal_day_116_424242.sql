-- What-if for a lab day only (capacity_day.py --lab-sql), written by make_shape_whatif.py from ottoq_cap_normal_day_116_424242
-- (run 663d217a-87bd-4ec1-80c9-b04b8c24f406): the battery's day plan sees a typical day's shape of EV charging, the EV kW that day drew in each half
-- hour of the local day, as a fourth floor under its forecast. Nothing else in the plan changes.
CREATE SCHEMA IF NOT EXISTS lab;
CREATE TABLE IF NOT EXISTS lab.ev_shape (slot int PRIMARY KEY, ev_kw numeric NOT NULL);
TRUNCATE lab.ev_shape;
INSERT INTO lab.ev_shape (slot, ev_kw) VALUES
  (12, 1273.1),
  (13, 943.2),
  (14, 1074.6),
  (15, 920.3),
  (16, 814.3),
  (17, 237.1),
  (18, 157.5),
  (19, 90.2),
  (20, 128.1),
  (21, 121.1),
  (22, 255.5),
  (23, 428.2),
  (24, 619.5),
  (25, 479.4),
  (26, 670.4),
  (27, 934.9),
  (28, 719.0),
  (29, 792.2),
  (30, 784.5),
  (31, 943.4),
  (32, 911.4),
  (33, 938.4),
  (34, 817.3),
  (35, 806.8),
  (36, 973.9);
DO $whatif$
DECLARE v_def text := pg_get_functiondef('public.ottoq_bess_day_plan'::regproc);
BEGIN
  IF (length(v_def) - length(replace(v_def, '    v_ev[k] := GREATEST(COALESCE(v_known[k], 0), COALESCE(v_queue[k], 0), v_ev_persist);   /* 0444 */', ''))) / length('    v_ev[k] := GREATEST(COALESCE(v_known[k], 0), COALESCE(v_queue[k], 0), v_ev_persist);   /* 0444 */') <> 1 THEN
    RAISE EXCEPTION 'what-if anchor not found exactly once in ottoq_bess_day_plan';
  END IF;
  EXECUTE replace(v_def, '    v_ev[k] := GREATEST(COALESCE(v_known[k], 0), COALESCE(v_queue[k], 0), v_ev_persist);   /* 0444 */', '    v_ev[k] := GREATEST(COALESCE(v_known[k], 0), COALESCE(v_queue[k], 0), v_ev_persist,   /* 0444 */
                        COALESCE((SELECT s.ev_kw FROM lab.ev_shape s WHERE s.slot = floor(v_hf * 2)::int), 0));   /* lab what-if: a typical day''s shape */');
END
$whatif$;
