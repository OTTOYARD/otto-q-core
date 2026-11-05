-- What-if for a lab day only (capacity_day.py --lab-sql), written by make_shape_whatif.py from ottoq_cap_normal_day_116_171717
-- (run d6955d8e-2998-425e-9cd0-2f06fa452310): the battery's day plan sees a typical day's shape of EV charging, the EV kW that day drew in each half
-- hour of the local day, as a fourth floor under its forecast. Nothing else in the plan changes.
CREATE SCHEMA IF NOT EXISTS lab;
CREATE TABLE IF NOT EXISTS lab.ev_shape (slot int PRIMARY KEY, ev_kw numeric NOT NULL);
TRUNCATE lab.ev_shape;
INSERT INTO lab.ev_shape (slot, ev_kw) VALUES
  (12, 1547.0),
  (13, 830.5),
  (14, 971.7),
  (15, 1400.5),
  (16, 1081.9),
  (17, 507.6),
  (18, 151.6),
  (19, 30.6),
  (20, 79.6),
  (21, 264.4),
  (22, 425.7),
  (23, 696.1),
  (24, 534.2),
  (25, 667.9),
  (26, 830.4),
  (27, 665.7),
  (28, 668.8),
  (29, 769.1),
  (30, 810.8),
  (31, 680.5),
  (32, 652.7),
  (33, 745.7),
  (34, 732.5),
  (35, 1009.0),
  (36, 1017.4);
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
