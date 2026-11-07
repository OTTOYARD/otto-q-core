-- lab/research/p2_capacity/call_day_readout.sql -- run in a finished lab replica with a demand-response call (psql -At
-- -f). The call, the grid and the battery through it at every 5-minute snapshot, the battery's mode each tick of the call
-- (ottoq_energy_commands, bess_setpoint_kw's recorded reason), and the battery's charge when the call starts and ends.
-- G519: with the planner followed (energy_mpc_follow = 1) the battery's mode through the call says whether it answered
-- the call (discharge_dr, the day plan's) or kept following a plan made without it (mpc_follow). LAB ONLY.
WITH c AS (SELECT issued_at AS t0, LEAST(expires_at, COALESCE(cleared_at, expires_at)) AS t1, required_load_cap_kw AS cap
             FROM ottoq_dr_calls ORDER BY issued_at LIMIT 1),
s AS (SELECT e.* FROM site_energy_snapshots e, c WHERE e.timestamp >= c.t0 AND e.timestamp < c.t1),
m AS (SELECT COALESCE(ec.reason ->> 'mode', '?') AS mode, count(*) AS n
        FROM ottoq_energy_commands ec, c
       WHERE ec.command_type = 'bess_setpoint_kw' AND ec.issued_at >= c.t0 AND ec.issued_at < c.t1 GROUP BY 1)
SELECT json_build_object(
  'call_ct', (SELECT to_char(t0 AT TIME ZONE 'America/Chicago', 'HH24:MI') || '-' || to_char(t1 AT TIME ZONE 'America/Chicago', 'HH24:MI') FROM c),
  'cap_kw', (SELECT round(cap::numeric, 1) FROM c),
  'snapshots', (SELECT count(*) FROM s),
  'grid_max_kw', (SELECT round(max(grid_import_kw)::numeric, 1) FROM s),
  'grid_mean_kw', (SELECT round(avg(grid_import_kw)::numeric, 1) FROM s),
  'snapshots_over_cap', (SELECT count(*) FROM s, c WHERE s.grid_import_kw > c.cap + 1),
  'kwh_over_cap', (SELECT round(sum(GREATEST(s.grid_import_kw - c.cap, 0)) * 5 / 60.0, 1) FROM s, c),
  'battery_mean_kw', (SELECT round(avg(bess_output_kw)::numeric, 1) FROM s),
  'ev_mean_kw', (SELECT round(avg(total_ev_charging_kw)::numeric, 1) FROM s),
  'battery_modes', (SELECT json_object_agg(mode, n) FROM m),
  'soc_at_call_pct', (SELECT round(b.soc_percent::numeric, 1) FROM bess_snapshots b, c WHERE b.timestamp <= c.t0 ORDER BY b.timestamp DESC LIMIT 1),
  'soc_at_end_pct', (SELECT round(b.soc_percent::numeric, 1) FROM bess_snapshots b, c WHERE b.timestamp <= c.t1 ORDER BY b.timestamp DESC LIMIT 1),
  'fingerprint', (SELECT md5(string_agg(concat_ws('|', timestamp, round(grid_import_kw::numeric, 1), round(bess_output_kw::numeric, 1),
                                                  round(total_ev_charging_kw::numeric, 1)), ',' ORDER BY timestamp)) FROM s));
