import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const sql = readFileSync(
  new URL("../db/migrations/0333_every_solver_proposal_gets_a_deterministic_disposition.sql", import.meta.url),
  "utf8",
);

test("proposal payload stays separate from deterministic disposition", () => {
  assert.match(sql, /ADD COLUMN IF NOT EXISTS disposition_reason text/);
  assert.match(sql, /ADD COLUMN IF NOT EXISTS disposed_at timestamptz/);
  assert.doesNotMatch(sql, /SET proposal\s*=/);
});

test("tick path closes every known terminal outcome", () => {
  for (const reason of [
    "enacted_by_kernel",
    "entity_decided_by_other_proposal",
    "ttl_elapsed",
    "invalid_stall_id",
    "stall_missing",
    "stall_occupied",
    "stall_reserved",
    "charger_unavailable",
    "charger_heartbeat_stale",
    "target_no_longer_eligible",
  ]) {
    assert.match(sql, new RegExp(reason));
  }
  assert.match(sql, /ottoq_dispose_external_proposals\(p_sim_run_id, v_tick, v_clock, false\)/);
});

test("run stop finalizes pending proposals before marking the run stopped", () => {
  assert.match(
    sql,
    /ottoq_dispose_external_proposals\(p_sim_run_id, NULL, NULL, true\);\\n'[\s\S]*v_marked := ottoq_sim_mark_stopped/,
  );
  assert.match(sql, /run_finalized/);
});

test("proposal TTL is disposed in the selector real-time domain", () => {
  assert.match(sql, /v_wall\s+timestamptz := clock_timestamp\(\)/);
  assert.match(sql, /p\.created_at \+ interval '35 minutes'\) < v_wall/);
});

test("proposal finalizer is service-role-only", () => {
  assert.match(sql, /REVOKE ALL ON FUNCTION public\.ottoq_dispose_external_proposals[\s\S]*FROM PUBLIC, anon, authenticated/);
  assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.ottoq_dispose_external_proposals[\s\S]*TO service_role/);
  assert.match(sql, /has_function_privilege\('anon'/);
});
