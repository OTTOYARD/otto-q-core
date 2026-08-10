-- MIGRATION: 0035_drop_decorative_seed_phase_max.sql
-- P1-16: column service_cadence_policy.seed_phase_max is decorative.
-- It holds constants 1.45/1.18/1.45/1.50 — the EXACT values hardcoded inside
-- ottoq_seed_vehicle_need_profiles at lines 13854/13855/13862.
-- The seeder never reads this column. Tuning it changes nothing while appearing to.
-- Migration 0035 deletes the column so it stops lying.

ALTER TABLE public.service_cadence_policy DROP COLUMN IF EXISTS seed_phase_max;
