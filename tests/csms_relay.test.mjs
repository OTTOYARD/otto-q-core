// The charger back end's relay, its pure half (edge-functions/_shared/csms_relay.ts), over a fake engine. The database
// half is tests/test_csms_relay_sql.py (0697 executed on the stub engine); the back end and its bridge are csms/.
//
// WHAT EACH PART PROVES
//   1. key     checked before anything else, and only its SHA-256 reaches the engine.
//   2. frames  the cursor and limit rules, the default start at the head, chargers on request, and every refusal the
//              database gives mapped to its status.
//   3. report  type and size rules, a body that is not one object refused here, the engine's verdict passed on.
//   4. routes  no other route or method answers, and no browser origin is ever allowed.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test, { describe } from "node:test";

import { handleCsmsRelayRequest, MAX_REPORT_BYTES, relayRouteOf } from "../edge-functions/_shared/csms_relay.ts";
import { EngineError } from "../edge-functions/_shared/depot_v2.ts";

const KEY = "ottow_" + "cd".repeat(32);
const HASH = createHash("sha256").update(KEY).digest("hex");
const BASE = "https://x.supabase.co/functions/v1/ottoq-csms-relay";

function fakeEngine(over = {}) {
  const calls = [];
  return {
    calls,
    pull: async (h, after, limit, withChargers) => {
      calls.push(["pull", h, after, limit, withChargers]);
      if (over.pull) return over.pull(h, after, limit, withChargers);
      return { ok: true, rows: [{ message_seq: after + 1 }], next_after: after + 1, more: false };
    },
    report: async (h, body) => {
      calls.push(["report", h, body]);
      if (over.report) return over.report(h, body);
      return { ok: true, report_id: 7 };
    },
  };
}

const get = (path, key = KEY) => new Request(BASE + path, { headers: key ? { "x-otto-q-api-key": key } : {} });
const post = (path, body, ctype = "application/json", key = KEY) =>
  new Request(BASE + path, { method: "POST", headers: { "content-type": ctype, ...(key ? { "x-otto-q-api-key": key } : {}) },
                             body: typeof body === "string" ? body : JSON.stringify(body) });

describe("1. key", () => {
  test("no key, a malformed key: refused before the engine is asked", async () => {
    const e = fakeEngine();
    assert.equal((await handleCsmsRelayRequest(get("/frames", ""), e)).status, 401);
    const r = await handleCsmsRelayRequest(get("/frames", "ottow_ABC"), e);
    assert.equal(r.status, 401);
    assert.equal((await r.json()).error.code, "malformed_key");
    assert.equal(e.calls.length, 0);
  });
  test("only the key's SHA-256 reaches the engine", async () => {
    const e = fakeEngine();
    await handleCsmsRelayRequest(get("/frames?after=5"), e);
    assert.equal(e.calls[0][1], HASH);
    assert.ok(!JSON.stringify(e.calls).includes(KEY));
  });
});

describe("2. frames", () => {
  test("starts at the head by default, passes the cursor, the limit and chargers on", async () => {
    const e = fakeEngine();
    await handleCsmsRelayRequest(get("/frames"), e);
    await handleCsmsRelayRequest(get("/frames?after=41&limit=1000&chargers=true"), e);
    assert.deepEqual(e.calls.map((c) => c.slice(2)), [[-1, 200, false], [41, 1000, true]]);
  });
  test("a cursor or limit outside the rules is refused here", async () => {
    const e = fakeEngine();
    for (const q of ["?after=x", "?limit=0", "?limit=1001", "?after=1e5"]) {
      assert.equal((await handleCsmsRelayRequest(get("/frames" + q), e)).status, 400, q);
    }
    assert.equal(e.calls.length, 0);
  });
  test("the database's refusals keep their reason and get their status", async () => {
    const cases = { unknown_or_revoked_key: 401, stream_not_allowed: 403, not_a_charger_backend_key: 403, pull_is_for_the_twin: 403 };
    for (const [reason, status] of Object.entries(cases)) {
      const r = await handleCsmsRelayRequest(get("/frames?after=1"), fakeEngine({ pull: async () => ({ ok: false, reason }) }));
      assert.equal(r.status, status, reason);
      assert.equal((await r.json()).error.code, reason);
    }
  });
  test("an engine that cannot be reached is the engine's status, not a 200", async () => {
    const e = fakeEngine({ pull: async () => { throw new EngineError(503, "relay_not_enabled", "not applied"); } });
    const r = await handleCsmsRelayRequest(get("/frames?after=1"), e);
    assert.equal(r.status, 503);
    assert.equal((await r.json()).error.code, "relay_not_enabled");
  });
});

describe("3. report", () => {
  test("a report goes to the engine as sent and its id comes back", async () => {
    const e = fakeEngine();
    const body = { from_seq: 1, to_seq: 3, frames: 3, outcomes: { accepted: 3 } };
    const r = await handleCsmsRelayRequest(post("/report", body), e);
    assert.equal(r.status, 200);
    assert.deepEqual(await r.json(), { ok: true, report_id: 7 });
    assert.deepEqual(e.calls[0][2], body);
  });
  test("the wrong type, too large, not JSON, not one object: refused here", async () => {
    const e = fakeEngine();
    assert.equal((await handleCsmsRelayRequest(post("/report", {}, "text/plain"), e)).status, 415);
    assert.equal((await handleCsmsRelayRequest(post("/report", "x".repeat(MAX_REPORT_BYTES + 1)), e)).status, 413);
    assert.equal((await handleCsmsRelayRequest(post("/report", "{"), e)).status, 400);
    assert.equal((await handleCsmsRelayRequest(post("/report", [1, 2]), e)).status, 400);
    assert.equal(e.calls.length, 0);
  });
  test("a report that does not add up is the database's 422", async () => {
    const e = fakeEngine({ report: async () => ({ ok: false, reason: "report_does_not_add_up" }) });
    assert.equal((await handleCsmsRelayRequest(post("/report", { frames: 9 }), e)).status, 422);
  });
});

describe("4. routes", () => {
  test("only GET /frames and POST /report, and no CORS header on any answer", async () => {
    const e = fakeEngine();
    assert.equal(relayRouteOf(new URL(BASE + "/frames")), "/frames");
    assert.equal((await handleCsmsRelayRequest(post("/frames", {}), e)).status, 405);
    assert.equal((await handleCsmsRelayRequest(get("/report"), e)).status, 405);
    const r = await handleCsmsRelayRequest(get("/elsewhere"), e);
    assert.equal(r.status, 404);
    assert.equal(r.headers.get("access-control-allow-origin"), null);
  });
});
