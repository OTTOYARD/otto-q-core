-- migration-version: 20260819200000
-- migration-name:    site_alpha_pack_classes
-- 0046 — C8 SITE ALPHA: the non-robotaxi asset classes, as PACK DATA.
-- Data-only, additive, idempotent. Classes live in ottoq_vehicle_classes with
-- the 0043 pack_id column carrying the pack; the kernel never branches on it.
-- NOT YET APPLIED TO PRODUCTION — apply after founder merge.

INSERT INTO public.ottoq_vehicle_classes
  (vehicle_class_code, oem_name, manufacturer, model, battery_capacity_kwh,
   max_charge_rate_kw, inlet_type, status, pack_id, energy_curve, duty_cycle_profile, notes)
VALUES
 ('yard_tractor_e_2025', 'YardCo', 'Generic', 'E-Tractor', 220, 150, 'CCS', 'active',
  'yard-logistics',
  '[{"above_soc_pct":0,"accept_frac":1.0},{"above_soc_pct":70,"accept_frac":0.6},{"above_soc_pct":85,"accept_frac":0.35}]'::jsonb,
  '{"shape":"daytime_waves","waves":[[360,300],[780,300]],"note":"two day-shift waves; battery_swap is the alternative to charge"}'::jsonb,
  'C8 Site Alpha tenant B: electric yard tractor; swap-capable'),
 ('amr_pallet_2025', 'AMRCo', 'Generic', 'Pallet-AMR', 12, 4, 'PAD', 'active',
  'yard-logistics',
  '[{"above_soc_pct":0,"accept_frac":1.0},{"above_soc_pct":80,"accept_frac":0.5}]'::jsonb,
  '{"shape":"opportunity","visits_per_day":2,"note":"short frequent top-ups at AMR pads"}'::jsonb,
  'C8 Site Alpha tenant C: autonomous mobile robot; opportunity charging at dedicated pads')
ON CONFLICT (vehicle_class_code) DO NOTHING;
