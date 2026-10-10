// The v2 operator door's pure half (edge-functions/_shared/depot_v2.ts): canonical JSON, the signature, and the HTTP
// door over a fake engine. The database half is tests/test_v2_door_sql.py; the contract is contract/README.md.
//
// WHAT EACH PART PROVES
//   1. jcs         RFC 8785's own samples (Appendix B numbers, the 3.2.2 object, the 3.2.3 key order).
//   2. signature   RFC 8037 A.4's known answer, and EVERY signed example in contract/examples re-signed here with the
//                  RFC 8037 A.1 test key comes out byte for byte the ottoqsig contract/ottoq_contract.py committed, and
//                  verifies: the TypeScript door and the Python kit sign the same bytes.
//   3. door        the key is checked before anything else and never sent raw; type, size and batch rules; an event
//                  that breaks the schema is answered here and never reaches the engine; results stay in order;
//                  directives leave signed with the cursor in a header; no browser origin is ever allowed.
//   4. key         the depot's key is made once, stored, and a lost race signs with the winner's key.
//   5. engine      the PostgREST caller: headers, and the failures it meets.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test, { describe } from "node:test";

import {
  b64u, b64uToBytes, depotSigner, EngineError, handleDepotV2Request, jcs, MAX_BATCH, postgrestV2Engine,
  routeOf, sha256Hex, signerFromJwk, signEvent, signingPayload, verifyEvent,
} from "../edge-functions/_shared/depot_v2.ts";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const EX = join(ROOT, "contract", "examples");
const BS = "\\";   // a backslash, spelled so that no editor can turn an escape into the character it names
// RFC 8037 Appendix A.1: the published Ed25519 test key (also RFC 8032 section 7.1, TEST 1).
const A1 = { kty: "OKP", crv: "Ed25519", x: "11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo", d: "nWGxne_9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A" };
const KEY = "ottow_" + "ab".repeat(32);
const enc = new TextEncoder();

const readJson = (p) => JSON.parse(readFileSync(p, "utf8"));
const signedExamples = () => ["valid", "invalid"].flatMap((d) => readdirSync(join(EX, d))
  .filter((f) => f.endsWith(".json") && f !== "expect.json")
  .map((f) => [`${d}/${f}`, readJson(join(EX, d, f))])
  .filter(([, e]) => typeof e.ottoqsig === "string"));

describe("1. jcs: RFC 8785", () => {
  const appendixB = [
    ["0000000000000000", "0"], ["8000000000000000", "0"], ["0000000000000001", "5e-324"], ["8000000000000001", "-5e-324"],
    ["7fefffffffffffff", "1.7976931348623157e+308"], ["ffefffffffffffff", "-1.7976931348623157e+308"],
    ["4340000000000000", "9007199254740992"], ["c340000000000000", "-9007199254740992"],
    ["4430000000000000", "295147905179352830000"], ["44b52d02c7e14af5", "9.999999999999997e+22"],
    ["44b52d02c7e14af6", "1e+23"], ["44b52d02c7e14af7", "1.0000000000000001e+23"],
    ["444b1ae4d6e2ef4e", "999999999999999700000"], ["444b1ae4d6e2ef4f", "999999999999999900000"],
    ["444b1ae4d6e2ef50", "1e+21"], ["3eb0c6f7a0b5ed8c", "9.999999999999997e-7"], ["3eb0c6f7a0b5ed8d", "0.000001"],
    ["41b3de4355555553", "333333333.3333332"], ["41b3de4355555554", "333333333.33333325"],
    ["41b3de4355555555", "333333333.3333333"], ["41b3de4355555556", "333333333.3333334"],
    ["41b3de4355555557", "333333333.33333343"], ["becbf647612f3696", "-0.0000033333333333333333"],
    ["43143ff3c1cb0959", "1424953923781206.2"],
  ];
  test("Appendix B numbers", () => {
    for (const [hex, want] of appendixB) {
      const dv = new DataView(new ArrayBuffer(8));
      dv.setBigUint64(0, BigInt("0x" + hex));
      assert.equal(jcs(dv.getFloat64(0)), want, hex);
    }
    assert.throws(() => jcs(NaN));
    assert.throws(() => jcs(Infinity));
  });
  test("section 3.2.2 sample", () => {
    const u = (h) => BS + "u" + h;
    const src = "{" + [
      '"numbers": [333333333.33333329, 1E30, 4.50, 2e-3, 0.000000000000000000000000001]',
      '"string": "' + u("20ac") + "$" + u("000F") + u("000a") + "A'" + u("0042") + u("0022") + u("005c") + BS + BS + BS + '"' + BS + '/"',
      '"literals": [null, true, false]'].join(", ") + "}";
    const want = '{"literals":[null,true,false],"numbers":[333333333.3333333,1e+30,4.5,0.002,1e-27],"string":"' +
      String.fromCharCode(0x20ac) + "$" + BS + "u000f" + BS + "nA'B" + BS + '"' + BS + BS + BS + BS + BS + '"/"}';
    assert.equal(jcs(JSON.parse(src)), want);
  });
  test("section 3.2.3 key order (UTF-16 code units)", () => {
    const o = {};
    o[String.fromCharCode(0x20ac)] = "Euro Sign"; o["\r"] = "Carriage Return"; o[String.fromCharCode(0xfb33)] = "Hebrew Letter Dalet With Dagesh";
    o["1"] = "One"; o[String.fromCharCode(0xd83d, 0xde00)] = "Emoji: Grinning Face"; o[String.fromCharCode(0x80)] = "Control";
    o[String.fromCharCode(0xf6)] = "Latin Small Letter O With Diaeresis";
    // Read the order off the canonical text itself: parsed back, a JavaScript object puts the integer-like key "1" first.
    const out = jcs(o);
    const order = ["Carriage Return", "One", "Control", "Latin Small Letter O With Diaeresis", "Euro Sign",
      "Emoji: Grinning Face", "Hebrew Letter Dalet With Dagesh"].map((v) => out.indexOf('"' + v + '"'));
    assert.ok(order.every((i) => i > 0), out);
    assert.deepEqual(order, [...order].sort((a, b) => a - b), out);
  });
});

describe("2. the signature", () => {
  test("RFC 8037 A.4: the known answer", async () => {
    const s = await signerFromJwk("a4", A1);
    const input = "eyJhbGciOiJFZERTQSJ9." + b64u(enc.encode("Example of Ed25519 signing"));
    assert.equal(b64u(await s.sign(enc.encode(input))),
      "hgyY0il_MGCjP0JzlnLWG1PPOt7-09PGcvMg3AIbQR6dWbhijcNR4ki4iylGjg5BhVsPt9g7sVvpAr_MuM0KAg");
  });
  test("every signed example: re-signed here byte for byte as the Python kit signed it, and it verifies", async () => {
    const jwks = readJson(join(EX, "example-jwks.json"));
    const s = await signerFromJwk("rfc8037-a1-test-key", A1);
    const all = signedExamples();
    assert.ok(all.length >= 5, "the examples carry their signatures");
    for (const [name, ev] of all) {
      const { ottoqsig, ...body } = ev;
      assert.equal((await signEvent(body, s)).ottoqsig, ottoqsig, name);
      assert.equal(await verifyEvent(ev, jwks), true, name);
    }
  });
  test("an edit anywhere in the event breaks it, and so does another key, alg or a payload left in", async () => {
    const jwks = readJson(join(EX, "example-jwks.json"));
    const ev = readJson(join(EX, "valid", "directive.charge.plan.json"));
    for (const edit of [(e) => { e.data.target_soc_pct = 90; }, (e) => { e.subject = "SIMB-0007"; },
                        (e) => { e.id = "ottoq-999"; }, (e) => { e.time = "2026-10-09T14:01:01Z"; }]) {
      const e = structuredClone(ev); edit(e);
      assert.equal(await verifyEvent(e, jwks), false);
    }
    const pair = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]);
    const other = await signerFromJwk("rfc8037-a1-test-key", await crypto.subtle.exportKey("jwk", pair.privateKey));
    const { ottoqsig: _o, ...body } = ev;
    assert.equal(await verifyEvent(await signEvent(body, other), jwks), false);
    const [h, , sig] = ev.ottoqsig.split(".");
    assert.equal(await verifyEvent({ ...ev, ottoqsig: h + "." + b64u(enc.encode(signingPayload(ev))) + "." + sig }, jwks), false);
    const eddsa = b64u(enc.encode(jcs({ alg: "EdDSA", kid: "rfc8037-a1-test-key" })));
    assert.equal(await verifyEvent({ ...ev, ottoqsig: eddsa + ".." + sig }, jwks), false);
  });
});

// ───────────────────────────────────────────────────────────────────────────────────────── a fake engine

function fakeEngine(over = {}) {
  const calls = [];
  const e = {
    calls,
    takeEvents: async (h, events, dryRun) => { calls.push(["take", h, events, dryRun]);
      return { ok: true, operator: "sim-a", data_source: "twin", results: events.map((ev) => ({ id: ev.id, disposition: "applied" })) }; },
    readDirectives: async (h, after, limit, mark) => { calls.push(["read", h, after, limit, mark]);
      const ev = readJson(join(EX, "valid", "directive.stall.assignment.json")); delete ev.ottoqsig;
      return { ok: true, events: [ev], next_after: 42 }; },
    signingKeyCurrent: async () => null,
    signingKeyStore: async (kid) => ({ stored: true, kid }),
    jwks: async () => ({ keys: [] }),
    ...over,
  };
  return e;
}
const okValidator = () => [];
const a1Signer = () => signerFromJwk("rfc8037-a1-test-key", A1);
const url = (p) => `https://x.supabase.co/functions/v1/ottoq-depot-v2${p}`;
const post = (p, body, headers = {}) => new Request(url(p), { method: "POST", body,
  headers: { "content-type": "application/cloudevents-batch+json", "x-otto-q-api-key": KEY, ...headers } });

describe("3. the door", () => {
  test("routes after the function's own name", () => {
    assert.equal(routeOf(new URL(url("/events"))), "/events");
    assert.equal(routeOf(new URL("https://x/ottoq-depot-v2/jwks/")), "/jwks");
    assert.equal(routeOf(new URL("https://x/ottoq-depot-v2")), "/");
  });
  test("no key, a malformed key: refused before the engine is asked anything", async () => {
    const eng = fakeEngine();
    const deps = { engine: eng, validate: okValidator, signer: a1Signer };
    let r = await handleDepotV2Request(new Request(url("/events"), { method: "POST", body: "[]",
      headers: { "content-type": "application/cloudevents-batch+json" } }), deps);
    assert.equal(r.status, 401); assert.equal((await r.json()).error.code, "no_key");
    r = await handleDepotV2Request(post("/events", "[]", { "x-otto-q-api-key": "ottow_XYZ" }), deps);
    assert.equal(r.status, 401); assert.equal((await r.json()).error.code, "malformed_key");
    r = await handleDepotV2Request(new Request(url("/directives"), { headers: {} }), deps);
    assert.equal(r.status, 401);
    assert.equal(eng.calls.length, 0);
  });
  test("type, JSON, batch and size rules", async () => {
    const deps = { engine: fakeEngine(), validate: okValidator, signer: a1Signer };
    let r = await handleDepotV2Request(post("/events", "{}", { "content-type": "application/json" }), deps);
    assert.equal(r.status, 415);
    r = await handleDepotV2Request(post("/events", "{not json"), deps);
    assert.equal(r.status, 400);
    r = await handleDepotV2Request(post("/events", "{}"), deps);
    assert.equal((await r.json()).error.code, "batch_not_array");
    r = await handleDepotV2Request(post("/events", JSON.stringify(Array.from({ length: MAX_BATCH + 1 }, (_, i) => ({ id: String(i) })))), deps);
    assert.equal(r.status, 413);
    r = await handleDepotV2Request(post("/events", JSON.stringify([{ pad: "x".repeat(1024 * 1024) }])), deps);
    assert.equal(r.status, 413);
    r = await handleDepotV2Request(post("/events", "[]"), deps);
    assert.equal(r.status, 413);
    r = await handleDepotV2Request(new Request(url("/events"), { method: "GET", headers: { "x-otto-q-api-key": KEY } }), deps);
    assert.equal(r.status, 405);
    r = await handleDepotV2Request(new Request(url("/nope")), deps);
    assert.equal(r.status, 404);
  });
  test("a schema-broken event is answered here and never sent; the rest go with the key's hash, in order", async () => {
    const eng = fakeEngine();
    const validate = (ev) => (ev.id === "bad" ? ["/data: Additional properties are not allowed [additionalProperties]"] : []);
    const body = JSON.stringify([{ id: "a" }, { id: "bad", source: "urn:ottoq:src:sim-a:X" }, { id: "c" }]);
    const r = await handleDepotV2Request(post("/events?dry_run=true", body), { engine: eng, validate, signer: a1Signer });
    assert.equal(r.status, 200);
    const j = await r.json();
    assert.deepEqual(j.results.map((x) => [x.id, x.disposition]), [["a", "applied"], ["bad", "refused"], ["c", "applied"]]);
    assert.equal(j.results[1].reason, "schema");
    assert.equal(j.applied, 2); assert.equal(j.refused, 1); assert.equal(j.dry_run, true);
    const [, h, sent, dry] = eng.calls[0];
    assert.equal(h, createHash("sha256").update(KEY).digest("hex"));
    assert.equal(h, await sha256Hex(KEY));
    assert.deepEqual(sent.map((e) => e.id), ["a", "c"]);
    assert.equal(dry, true);
    assert.ok(!JSON.stringify(eng.calls).includes(KEY), "the raw key never reaches the engine");
  });
  test("one event in structured mode", async () => {
    const eng = fakeEngine();
    const r = await handleDepotV2Request(post("/events", JSON.stringify({ id: "solo" }),
      { "content-type": "application/cloudevents+json; charset=utf-8" }), { engine: eng, validate: okValidator, signer: a1Signer });
    assert.equal(r.status, 200);
    assert.deepEqual(eng.calls[0][2], [{ id: "solo" }]);
  });
  test("the engine's refusals keep their meaning", async () => {
    for (const [reason, status] of [["unknown_or_revoked_key", 401], ["no_running_run", 409], ["key_speaks_for_no_fleet", 403]]) {
      const eng = fakeEngine({ takeEvents: async () => ({ ok: false, reason }) });
      const r = await handleDepotV2Request(post("/events", JSON.stringify([{ id: "a" }])), { engine: eng, validate: okValidator, signer: a1Signer });
      assert.equal(r.status, status, reason);
    }
    const down = fakeEngine({ takeEvents: async () => { throw new EngineError(503, "engine_unreachable", "x"); } });
    const r = await handleDepotV2Request(post("/events", JSON.stringify([{ id: "a" }])), { engine: down, validate: okValidator, signer: a1Signer });
    assert.equal(r.status, 503);
  });
  test("directives leave signed, as a batch, with the cursor in a header; peek leaves them unmarked", async () => {
    const eng = fakeEngine();
    const deps = { engine: eng, validate: okValidator, signer: a1Signer };
    const r = await handleDepotV2Request(new Request(url("/directives?after=7&limit=50&peek=true"),
      { headers: { "x-otto-q-api-key": KEY } }), deps);
    assert.equal(r.status, 200);
    assert.match(r.headers.get("content-type"), /^application\/cloudevents-batch\+json/);
    assert.equal(r.headers.get("ottoq-next-after"), "42");
    assert.equal(r.headers.get("access-control-allow-origin"), null);
    const events = await r.json();
    assert.equal(events.length, 1);
    assert.equal(await verifyEvent(events[0], readJson(join(EX, "example-jwks.json"))), true);
    assert.deepEqual(eng.calls[0].slice(2), [7, 50, false]);
    for (const q of ["?after=-1", "?after=x", "?limit=0", "?limit=501"]) {
      const bad = await handleDepotV2Request(new Request(url("/directives" + q), { headers: { "x-otto-q-api-key": KEY } }), deps);
      assert.equal(bad.status, 400, q);
    }
  });
});

describe("4. the depot's key", () => {
  test("made once, stored, cached; the public half alone leaves", async () => {
    const stored = [];
    const eng = fakeEngine({ signingKeyStore: async (kid, pub, priv) => { stored.push({ kid, pub, priv }); return { stored: true, kid }; } });
    const get = depotSigner(eng);
    const s1 = await get(); const s2 = await get();
    assert.equal(s1, s2);
    assert.equal(stored.length, 1);
    assert.match(stored[0].kid, /^ottoq-depot-[0-9a-f]{16}$/);
    assert.equal("d" in stored[0].pub, false);
    assert.equal(b64uToBytes(stored[0].priv.d).length, 32);
    const ev = { specversion: "1.0", id: "x", data: { a: 1 } };
    const signed = await signEvent(ev, s1);
    assert.equal(await verifyEvent(signed, { keys: [{ ...stored[0].pub, kid: stored[0].kid }] }), true);
  });
  test("a lost race signs with the winner's key", async () => {
    const eng = fakeEngine({
      signingKeyStore: async () => ({ stored: false, kid: "winner" }),
      signingKeyCurrent: (() => { let n = 0; return async () => (n++ === 0 ? null : { kid: "winner", private_jwk: A1 }); })(),
    });
    const s = await depotSigner(eng)();
    assert.equal(s.kid, "winner");
  });
});

describe("5. the engine caller", () => {
  test("a secret key goes in apikey alone; a JWT also as the Bearer; the hash and flags are what is sent", async () => {
    const seen = [];
    const fetchImpl = async (u, init) => { seen.push([u, init]); return new Response(JSON.stringify({ ok: true, results: [] }), { status: 200 }); };
    await postgrestV2Engine({ supabaseUrl: "https://x.supabase.co/", serviceKey: "sb_secret_abc", fetchImpl }).takeEvents("h", [{ id: 1 }], true);
    assert.equal(seen[0][0], "https://x.supabase.co/rest/v1/rpc/ottoq_v2_take_events");
    assert.equal(seen[0][1].headers.apikey, "sb_secret_abc");
    assert.equal(seen[0][1].headers.Authorization, undefined);
    assert.deepEqual(JSON.parse(seen[0][1].body), { p_key_hash: "h", p_events: [{ id: 1 }], p_dry_run: true });
    await postgrestV2Engine({ supabaseUrl: "https://x", serviceKey: "aaa.bbb.ccc", fetchImpl }).jwks();
    assert.equal(seen[1][1].headers.Authorization, "Bearer aaa.bbb.ccc");
  });
  test("a missing function, a refused key, a timeout", async () => {
    const mk = (fetchImpl) => postgrestV2Engine({ supabaseUrl: "https://x", serviceKey: "k", fetchImpl });
    await assert.rejects(mk(async () => new Response(JSON.stringify({ code: "PGRST202" }), { status: 404 })).jwks(), { code: "door_not_enabled" });
    await assert.rejects(mk(async () => new Response("{}", { status: 401 })).jwks(), { code: "engine_misconfigured" });
    await assert.rejects(mk(async () => { const e = new Error("t"); e.name = "TimeoutError"; throw e; }).jwks(), { code: "engine_timeout", status: 504 });
  });
});
