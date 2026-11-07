-- lab/research/p2_capacity/day_fingerprint.sql -- run in a finished lab replica (psql -At -f). A day's fingerprint, row
-- count and md5 (first 8) over its ordered rows: the battery's and the chargers' commands (a day plan's solve time set
-- aside), the site's energy every 5 minutes, the charging sessions, and the visits with their services' states. Two days
-- whose four fingerprints agree ran the same day. LAB ONLY.
SELECT json_build_object(
  'energy_commands', (SELECT count(*) || ':' || left(md5(string_agg(concat_ws('|', tick_seq, command_type, round(setpoint_kw::numeric, 3),
                                ((reason - 'solve_ms') #- '{day_plan,solve_ms}')::text), ',' ORDER BY tick_seq, command_type, issued_at)), 8)
                        FROM ottoq_energy_commands),
  'snapshots', (SELECT count(*) || ':' || left(md5(string_agg(concat_ws('|', timestamp, round(grid_import_kw::numeric, 1),
                          round(bess_output_kw::numeric, 1), round(total_ev_charging_kw::numeric, 1)), ',' ORDER BY timestamp)), 8)
                  FROM site_energy_snapshots),
  'sessions', (SELECT count(*) || ':' || left(md5(string_agg(concat_ws('|', vehicle_id, stall_id, started_at, ended_at, status),
                         ',' ORDER BY started_at, vehicle_id, stall_id)), 8) FROM ocpp_sessions),
  'visits', (SELECT count(*) || ':' || left(md5(string_agg(concat_ws('|', vehicle_id, arrived_at, status,
                       (SELECT string_agg((a->>'svc') || ':' || COALESCE(a->>'status', ''), ',' ORDER BY a->>'svc', a->>'status')
                          FROM jsonb_array_elements(atoms) a)), ',' ORDER BY arrived_at, vehicle_id)), 8) FROM ottoq_visit_needs));
