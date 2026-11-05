-- lab/engine/sql/40_research_schema.sql
-- The lab's `research` schema: copies of production evidence the research wing replays, kept OUT of the engine's own
-- tables so the engine copy stays exactly what production's engine is. Each table has its source table's columns, in
-- order (LIKE), so a source row's composite text parses as the research table's row. Idempotent.
CREATE SCHEMA IF NOT EXISTS research;
CREATE TABLE IF NOT EXISTS research.ottoq_charge_order_grades    (LIKE public.ottoq_charge_order_grades    INCLUDING DEFAULTS);
CREATE TABLE IF NOT EXISTS research.ottoq_charge_order_snapshots (LIKE public.ottoq_charge_order_snapshots INCLUDING DEFAULTS);
CREATE TABLE IF NOT EXISTS research.ottoq_agent_charge_orders    (LIKE public.ottoq_agent_charge_orders    INCLUDING DEFAULTS);
DO $k$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'research_grades_pk') THEN
    ALTER TABLE research.ottoq_charge_order_grades ADD CONSTRAINT research_grades_pk PRIMARY KEY (order_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'research_snapshots_pk') THEN
    ALTER TABLE research.ottoq_charge_order_snapshots ADD CONSTRAINT research_snapshots_pk PRIMARY KEY (order_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'research_orders_pk') THEN
    ALTER TABLE research.ottoq_agent_charge_orders ADD CONSTRAINT research_orders_pk PRIMARY KEY (order_id);
  END IF;
END $k$;
