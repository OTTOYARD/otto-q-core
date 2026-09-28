// The ottoq-agent-gateway: its pure half (edge-functions/_shared/agent_gateway.ts), its contract with the database
// half (db/migrations/0550), and -- when a scratch PostgreSQL is reachable -- the two together, end to end.
//
// WHAT EACH PART PROVES
//   1. contract     the TypeScript catalog and the SQL dispatcher name the same tools, capabilities, statuses and
//                   ops actions, read out of the migration file itself, so neither half can drift alone.
//   2. schemas      every tool's input schema is closed: no argument can carry a scope (fleet, depot, principal).
//   3. http         auth first (a missing or malformed token never reaches the engine; the raw token never does),
//                   the Origin rule, the body cap, REST routing and envelopes, the public agent card.
//   4. mcp          the 2026-07-28 stateless revision (mirrored headers, -32020 / -32022, 404, 202) and the
//                   initialize-based revisions older clients speak, on one endpoint.
//   5. engine       the PostgREST caller: headers, body, and every failure it can meet.
//   6. no writes    nothing an agent's token can reach names an engine door or writes outside ottoq_agent_*.
//   7. end to end   (skips without a server) the HTTP handler over the REAL 0550 SQL against the stub engine:
//                   operator A cannot read or act on operator B's vehicle, a person's approval reaches the door.
//
// The SQL half's own suite is tests/test_agent_gateway_sql.py (21 tests); this file does not repeat it.
import assert from "node:assert/strict";
import { createHash, randomBytes } from "node:crypto";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test, { after, before, describe } from "node:test";

import {
  agentCard,
  argsFromQuery,
  ASKABLE_OPS_ACTIONS,
  CAPABILITIES,
  ENGINE_RPC,
  gatewayPath,
  GATEWAY_NAME,
  handleGatewayRequest,
  isWellFormedToken,
  JSONRPC,
  MAX_BODY_BYTES,
  MCP_MODERN_VERSION,
  MCP_SUPPORTED_VERSIONS,
  mcpToolList,
  OPS_ACTIONS,
  postgrestEngine,
  PRIORITIES,
  readBodyBounded,
  REQUEST_KIND_CAPABILITY,
  REQUEST_STATUSES,
  sha256Hex,
  STALL_TYPES,
  TOKEN_PATTERN,
  TOOLS,
  toolsFor,
  TWIN_DEPOT_ID,
  validateToolArgs,
  VEHICLE_STATES,
} from "../edge-functions/_shared/agent_gateway.ts";
import { INERT_OPS } from "../edge-functions/_shared/agent_dial_discipline.ts";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const read = (p) => readFileSync(join(ROOT, p), "utf8");
const M0550_PATH = "db/migrations/0550_an_outside_agent_asks_through_one_door_and_a_person_decides.sql";
const M0551_PATH = "db/migrations/0551_the_fleet_owner_cockpit_reads_its_own_agent_requests.sql";
const STUB_PATH = "tests/fixtures/agent_gateway_stub_engine.sql";
const M0550 = read(M0550_PATH);
const STUB = read(STUB_PATH);
const SHELL = read("edge-functions/ottoq-agent-gateway/index.ts");
const SHARED = read("edge-functions/_shared/agent_gateway.ts");

const sha = (t) => createHash("sha256").update(t, "utf8").digest("hex");
const stripSqlComments = (s) => s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/--[^\n]*/g, "");
const stripTsComments = (s) => s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/[^\n]*/g, "$1");

/** Every CREATE FUNCTION in 0550, name -> body (all of them use the $fn$ tag). */
function functionBodies(sql) {
  const out = new Map();
  const re = /CREATE OR REPLACE FUNCTION (?:public|ottoq)\.(\w+)\([\s\S]*?\nAS \$fn\$([\s\S]*?)\$fn\$;/g;
  for (const m of sql.matchAll(re)) out.set(m[1], m[2]);
  return out;
}
const FUNCS = functionBodies(M0550);

/** A CASE ... WHEN 'a' THEN 'b' ... map out of a function body, starting at `anchor`. */
function caseMap(body, anchor) {
  const at = body.indexOf(anchor);
  assert.ok(at >= 0, `anchor not found: ${anchor}`);
  const end = body.indexOf("END", at);
  const map = {};
  for (const m of body.slice(at, end).matchAll(/WHEN '([a-z_]+)'\s+THEN '([a-z_]*)'/g)) map[m[1]] = m[2];
  return map;
}

// ════════════════════════════════════════════════════════════════════════════════════════ 1. contract ══

test("0550 defines the functions this suite reads (the parser saw all 26)", () => {
  assert.equal(FUNCS.size, 26, [...FUNCS.keys()].join(", "));
  for (const f of ["ottoq_agent_call", "ottoq_agent_submit_request", "ottoq_agent_request_decide", "ottoq_agent_issue_token"]) {
    assert.ok(FUNCS.has(f), f);
  }
});

test("the tool catalog is exactly the dispatcher's vocabulary, with the same capability each", () => {
  const need = caseMap(FUNCS.get("ottoq_agent_call"), "v_need := CASE v_tool");
  assert.equal(need.handshake, "", "handshake is the authentication-only tool");
  delete need.handshake;
  assert.deepEqual(Object.keys(need).sort(), TOOLS.map((t) => t.name).sort());
  const asTs = { "": null, read: "read", note: "note", per_kind: "any_request" };
  for (const t of TOOLS) assert.equal(t.capability, asTs[need[t.name]], t.name);
});

test("capabilities, request kinds, statuses and priorities agree with the tables' CHECKs", () => {
  const caps = /capabilities <@ ARRAY\[([^\]]+)\]/.exec(M0550);
  assert.deepEqual(caps[1].split(",").map((s) => s.trim().replace(/'/g, "")), [...CAPABILITIES]);
  const kinds = /ottoq_agent_requests_kind_check CHECK \(kind IN \(([^)]+)\)/.exec(M0550);
  assert.deepEqual(kinds[1].split(",").map((s) => s.trim().replace(/'/g, "")).sort(),
    ["note", ...Object.keys(REQUEST_KIND_CAPABILITY)].sort());
  const status = /ottoq_agent_requests_status_check CHECK \(status IN \(([^)]+)\)/.exec(M0550);
  assert.deepEqual(status[1].split(",").map((s) => s.trim().replace(/'/g, "")), [...REQUEST_STATUSES]);
  const prio = /ottoq_agent_requests_priority_check CHECK \(priority IN \(([^)]+)\)/.exec(M0550);
  assert.deepEqual(prio[1].split(",").map((s) => s.trim().replace(/'/g, "")), [...PRIORITIES]);
});

test("the ops-action map agrees with the database's and with the engine's whitelist", () => {
  assert.deepEqual(caseMap(FUNCS.get("ottoq_agent_submit_request"), "v_param := CASE v_action"), { ...OPS_ACTIONS });
  // the stub's ottoq_apply_ops_action is the live body (md5-checked by the SQL suite): its refusal names the whitelist
  const wl = /'whitelist', jsonb_build_array\(([\s\S]*?)\)\)/.exec(STUB);
  assert.deepEqual(wl[1].split(",").map((s) => s.trim().replace(/'/g, "")), Object.keys(OPS_ACTIONS));
});

test("an agent is offered only the ops actions it can actually get (no placebo)", () => {
  assert.deepEqual([...ASKABLE_OPS_ACTIONS], Object.keys(OPS_ACTIONS).filter((a) => !(a in INERT_OPS)));
  assert.deepEqual([...ASKABLE_OPS_ACTIONS], ["enable_energy_reserve"]);
  const submit = TOOLS.find((t) => t.name === "submit_request");
  assert.deepEqual([...submit.inputSchema.properties.action.enum], ["enable_energy_reserve"]);
  for (const inert of Object.keys(INERT_OPS)) {
    const v = validateToolArgs(submit, { kind: "ops_action", title: "x", action: inert });
    assert.equal(v.ok, false, inert);
  }
});

test("stall types and vehicle states are the engine's enums (read from the live catalog 2026-09-28)", () => {
  const stall = /CREATE TYPE public\.stall_type AS ENUM \(([^)]+)\)/.exec(STUB);
  assert.deepEqual(stall[1].split(",").map((s) => s.trim().replace(/'/g, "")), [...STALL_TYPES]);
  const veh = /CREATE TYPE public\.vehicle_state AS ENUM \(([\s\S]+?)\);/.exec(STUB);
  assert.deepEqual(veh[1].split(",").map((s) => s.trim().replace(/'/g, "")), [...VEHICLE_STATES]);
});

test("the token shape is what ottoq_agent_issue_token mints, and the hash is what it stores", async () => {
  const issue = FUNCS.get("ottoq_agent_issue_token");
  assert.match(issue, /'oqa_' \|\| encode\(extensions\.gen_random_bytes\(32\), 'hex'\)/);
  assert.match(issue, /encode\(sha256\(convert_to\(v_token, 'UTF8'\)\), 'hex'\)/);
  const token = "oqa_" + randomBytes(32).toString("hex");
  assert.ok(TOKEN_PATTERN.test(token) && isWellFormedToken(token));
  assert.equal(await sha256Hex(token), sha(token));
  for (const bad of [token.toUpperCase(), token.slice(0, -1), token + "0", "oqb_" + token.slice(4), "", null, undefined]) {
    assert.equal(isWellFormedToken(bad), false, String(bad));
  }
});

// ═════════════════════════════════════════════════════════════════════════════════════════ 2. schemas ══

const MINIMAL = {
  whoami: {}, depot_status: {}, fleet_summary: {}, recent_decisions: {}, stall_availability: {}, list_requests: {},
  vehicle_card: { vehicle_id: "ee000000-0000-0000-0000-0000000000a1" },
  send_note: { title: "hello" },
  submit_request: { kind: "recall_vehicle", title: "home", vehicle_id: "ee000000-0000-0000-0000-0000000000a1" },
};

function closedEverywhere(schema, path) {
  if (schema.type === "object" || schema.properties) {
    assert.equal(schema.additionalProperties, false, `${path} is not closed`);
    for (const [k, sub] of Object.entries(schema.properties ?? {})) closedEverywhere(sub, `${path}.${k}`);
  }
}

test("every tool's input schema is a closed object, all the way down", () => {
  for (const t of TOOLS) {
    assert.equal(t.inputSchema.type, "object", t.name);
    closedEverywhere(t.inputSchema, t.name);
    assert.ok(validateToolArgs(t, MINIMAL[t.name]).ok, `${t.name}: its minimal arguments are refused`);
  }
});

test("no tool accepts a scope from the caller: the database derives it from the token alone", () => {
  const smuggled = ["fleet_operator_id", "depot_id", "principal", "principal_id", "principal_name", "capabilities",
    "token", "token_hash", "sim_run_id", "auth_user_id", "decided_by", "operator", "scope"];
  for (const t of TOOLS) {
    for (const key of smuggled) {
      const v = validateToolArgs(t, { ...MINIMAL[t.name], [key]: "22222222-2222-2222-2222-222222222222" });
      assert.equal(v.ok, false, `${t.name} accepted ${key}`);
      assert.ok(v.errors.some((e) => e.path === `$.${key}` && /not a known argument/.test(e.message)), `${t.name}/${key}`);
    }
  }
});

test("argument validation refuses what the database would, with a path per problem", () => {
  const tool = (n) => TOOLS.find((t) => t.name === n);
  const bad = [
    ["vehicle_card", {}, "$.vehicle_id"],
    ["vehicle_card", { vehicle_id: "W1" }, "$.vehicle_id"],
    ["fleet_summary", { limit: 0 }, "$.limit"],
    ["fleet_summary", { limit: 501 }, "$.limit"],
    ["fleet_summary", { limit: 2.5 }, "$.limit"],
    ["fleet_summary", { state: "flying" }, "$.state"],
    ["stall_availability", { stall_type: "garage" }, "$.stall_type"],
    ["stall_availability", { horizon_min: 4 }, "$.horizon_min"],
    ["list_requests", { status: "done" }, "$.status"],
    ["send_note", {}, "$.title"],
    ["send_note", { title: "" }, "$.title"],
    ["send_note", { title: "x".repeat(141) }, "$.title"],
    ["send_note", { title: "x", body: "y".repeat(4001) }, "$.body"],
    ["send_note", { title: "x", priority: "asap" }, "$.priority"],
    ["send_note", { title: "x", ttl_minutes: 1 }, "$.ttl_minutes"],
    ["send_note", { title: "x", idempotency_key: "has space" }, "$.idempotency_key"],
    ["submit_request", { kind: "teleport", title: "x" }, "$.kind"],
    ["submit_request", { kind: "recall_vehicle", title: "x" }, "$.vehicle_id"],
    ["submit_request", { kind: "ops_action", title: "x" }, "$.action"],
    ["submit_request", { kind: "ops_action", title: "x", action: "enable_energy_reserve", vehicle_id: MINIMAL.vehicle_card.vehicle_id }, "$.vehicle_id"],
    ["submit_request", { kind: "ops_action", title: "x", action: "enable_energy_reserve", args: { value: "1" } }, "$.args.value"],
    ["submit_request", { kind: "ops_action", title: "x", action: "enable_energy_reserve", args: { dial: "x" } }, "$.args.dial"],
    ["submit_request", { kind: "adjustment", title: "x" }, "$.adjustment"],
    ["submit_request", { kind: "adjustment", title: "x", adjustment: "Bad Name" }, "$.adjustment"],
    ["submit_request", { kind: "adjustment", title: "x", adjustment: "charge_target", value: "v".repeat(201) }, "$.value"],
    ["submit_request", { kind: "adjustment", title: "x", adjustment: "charge_target", value: { nested: 1 } }, "$.value"],
    ["submit_request", { kind: "recall_vehicle", title: "x", vehicle_id: MINIMAL.vehicle_card.vehicle_id, action: "enable_energy_reserve" }, "$.action"],
    ["submit_request", { kind: "recall_vehicle", title: "x", vehicle_id: MINIMAL.vehicle_card.vehicle_id, value: 1 }, "$.adjustment"],
  ];
  for (const [name, args, path] of bad) {
    const v = validateToolArgs(tool(name), args);
    assert.equal(v.ok, false, `${name} accepted ${JSON.stringify(args)}`);
    assert.ok(v.errors.some((e) => e.path === path), `${name} ${JSON.stringify(args)}: ${JSON.stringify(v.errors)}`);
  }
  // lengths are characters, as char_length() counts them, not UTF-16 units
  assert.ok(validateToolArgs(tool("send_note"), { title: "\u{1F697}".repeat(140) }).ok);
  assert.equal(validateToolArgs(tool("send_note"), []).ok, false);
  assert.ok(validateToolArgs(tool("submit_request"),
    { kind: "adjustment", title: "cap", adjustment: "charge_target", value: 90, vehicle_id: MINIMAL.vehicle_card.vehicle_id }).ok);
});

test("REST query strings are coerced to the schema's types, and unknown parameters are refused", () => {
  const fleet = TOOLS.find((t) => t.name === "fleet_summary");
  assert.deepEqual(argsFromQuery(fleet, new URLSearchParams("state=charging_dcfc&limit=5")),
    { ok: true, value: { state: "charging_dcfc", limit: 5 } });
  assert.deepEqual(argsFromQuery(fleet, new URLSearchParams("limit=")), { ok: true, value: {} });
  assert.equal(argsFromQuery(fleet, new URLSearchParams("limit=5x")).ok, false);
  assert.equal(argsFromQuery(fleet, new URLSearchParams("fleet_operator_id=22222222-2222-2222-2222-222222222222")).ok, false);
});

test("a token sees the tools its capabilities allow, and submit_request only the kinds it may ask for", () => {
  const names = (caps) => toolsFor(caps).map((t) => t.name);
  assert.deepEqual(names([]), ["whoami", "list_requests"]);
  assert.deepEqual(names(["read"]),
    ["whoami", "depot_status", "fleet_summary", "vehicle_card", "recent_decisions", "stall_availability", "list_requests"]);
  assert.deepEqual(names(["note"]), ["whoami", "list_requests", "send_note"]);
  const recallOnly = toolsFor(["request_recall"]).find((t) => t.name === "submit_request");
  assert.deepEqual(recallOnly.inputSchema.properties.kind.enum, ["recall_vehicle"]);
  const all = toolsFor([...CAPABILITIES]).find((t) => t.name === "submit_request");
  assert.deepEqual(all.inputSchema.properties.kind.enum, ["recall_vehicle", "ops_action", "adjustment"]);
  // narrowing copies; the catalog itself is untouched
  assert.equal(TOOLS.find((t) => t.name === "submit_request").inputSchema.properties.kind.enum.length, 3);
});

test("only send_note and submit_request can change anything, and what they change is the request ledger", () => {
  for (const t of TOOLS) {
    const writes = t.effect !== "read";
    assert.equal(t.annotations.readOnlyHint, !writes, t.name);
    assert.equal(t.annotations.destructiveHint, false, t.name);
    assert.equal(t.annotations.openWorldHint, false, t.name);
    if (writes) assert.equal(t.effect, "ledger_write", t.name);
  }
  assert.deepEqual(TOOLS.filter((t) => t.effect !== "read").map((t) => t.name), ["send_note", "submit_request"]);
});

// ════════════════════════════════════════════════════════════════════════════════════════════ 3. http ══

const BASE = "https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-agent-gateway";
const T_ALL = "oqa_" + "1".repeat(64);
const T_READ = "oqa_" + "2".repeat(64);
const T_NOTE = "oqa_" + "3".repeat(64);
const T_LIMITED = "oqa_" + "4".repeat(64);
const T_UNKNOWN = "oqa_" + "9".repeat(64);
const PRINCIPALS = {
  [T_ALL]: { name: "hermes", kind: "personal", capabilities: [...CAPABILITIES] },
  [T_READ]: { name: "reader", kind: "fleet_operator", capabilities: ["read"] },
  [T_NOTE]: { name: "noter", kind: "personal", capabilities: ["note"] },
  [T_LIMITED]: { name: "busy", kind: "personal", capabilities: ["read"], limited: true },
};

/** A stand-in for public.ottoq_agent_call with its contract: auth first, rate limit, flagged refusals, a call id each. */
function fakeEngine(overrides = {}) {
  const calls = [];
  const byHash = new Map(Object.entries(PRINCIPALS).map(([t, p]) => [sha(t), p]));
  const engine = async (tokenHash, tool, args, transport, meta) => {
    calls.push({ tokenHash, tool, args, transport, meta });
    const call_id = calls.length;
    const p = byHash.get(tokenHash);
    if (!p) return { ok: false, http_status: 401, tool, call_id, error: { code: "unauthenticated", message: "The token is unknown or has been revoked." } };
    if (p.limited) return { ok: false, http_status: 429, tool, call_id, error: { code: "rate_limited", retry_after_s: 60, message: "At most 60 calls a minute for this token." } };
    if (!["handshake", ...TOOLS.map((t) => t.name)].includes(tool)) {
      return { ok: false, http_status: 404, tool, call_id, error: { code: "unknown_tool", message: `No tool named ${tool}.` } };
    }
    if (meta.gateway_refusal === "invalid_arguments") {
      return { ok: false, http_status: 400, tool, call_id, error: { code: "invalid_arguments", message: "refused" } };
    }
    if (overrides[tool]) return { tool, call_id, ...overrides[tool](args) };
    const principal = { name: p.name, kind: p.kind, capabilities: p.capabilities };
    return { ok: true, http_status: tool === "send_note" || tool === "submit_request" ? 201 : 200, tool, call_id, principal, data: { echo: { tool, args } } };
  };
  return { engine, calls };
}

function gateway(engine, { allowedOrigins = [], prefix = "/ottoq-agent-gateway" } = {}) {
  return (path, { method = "GET", token, headers = {}, body, raw } = {}) => {
    const h = new Headers(headers);
    if (token !== undefined) h.set("authorization", `Bearer ${token}`);
    const init = { method, headers: h };
    if (raw !== undefined) Object.assign(init, raw);
    else if (body !== undefined) init.body = typeof body === "string" ? body : JSON.stringify(body);
    return handleGatewayRequest(new Request(`https://edge.internal${prefix}${path}`, init), { publicUrl: BASE, allowedOrigins, engine });
  };
}
const bodyOf = async (res) => { const t = await res.text(); return t ? JSON.parse(t) : null; };

test("the function's path is found whether or not the platform keeps the /functions/v1 prefix", () => {
  assert.equal(gatewayPath("/functions/v1/ottoq-agent-gateway/v1/fleet"), "/v1/fleet");
  assert.equal(gatewayPath("/ottoq-agent-gateway/mcp"), "/mcp");
  assert.equal(gatewayPath("/ottoq-agent-gateway"), "/");
  assert.equal(GATEWAY_NAME, "ottoq-agent-gateway");
});

test("auth failure: no token, a malformed token or another scheme never reaches the engine", async () => {
  const { engine, calls } = fakeEngine();
  const gw = gateway(engine);
  for (const headers of [{}, { authorization: `Bearer ${T_ALL.toUpperCase()}` }, { authorization: `Bearer ${T_ALL}x` },
    { authorization: `Basic ${Buffer.from("a:b").toString("base64")}` }, { authorization: `Bearer ${T_ALL} ${T_ALL}` },
    { authorization: "Bearer eyJhbGciOiJIUzI1NiJ9.e30.sig" }]) {
    for (const path of ["/v1/whoami", "/v1/fleet", "/v1/requests"]) {
      const res = await gw(path, { headers });
      assert.equal(res.status, 401, `${path} ${JSON.stringify(headers)}`);
      assert.match(res.headers.get("www-authenticate"), /^Bearer realm="ottoq-agent-gateway"/);
      assert.equal((await bodyOf(res)).error.code, "unauthenticated");
    }
  }
  const mcp = await gw("/mcp", { method: "POST", body: { jsonrpc: "2.0", id: 1, method: "tools/list" } });
  assert.equal(mcp.status, 401);
  const rpc = await bodyOf(mcp);
  assert.equal(rpc.error.code, JSONRPC.UNAUTHORIZED);
  assert.equal(rpc.id, null);
  assert.equal(calls.length, 0, "a request without a well-formed token reached the engine");
});

test("auth failure: a well-formed but unknown token is refused BY THE DATABASE, even with bad arguments", async () => {
  const { engine, calls } = fakeEngine();
  const gw = gateway(engine);
  for (const [path, init] of [["/v1/whoami", {}], ["/v1/vehicles/not-a-uuid", {}], ["/v1/fleet?fleet_operator_id=x", {}],
    ["/v1/requests", { method: "POST", body: "{not json" }], ["/v1/notes", { method: "POST", body: { title: "" } }]]) {
    const res = await gw(path, { token: T_UNKNOWN, ...init });
    assert.equal(res.status, 401, path);
    assert.ok(res.headers.get("www-authenticate"), path);
  }
  assert.equal(calls.length, 5);
  assert.ok(calls.every((c) => c.tokenHash === sha(T_UNKNOWN)));
});

test("the raw token never leaves the edge: the engine sees its SHA-256 and nothing else of it", async () => {
  const { engine, calls } = fakeEngine();
  const gw = gateway(engine);
  await gw("/v1/whoami", { token: T_ALL });
  await gw("/v1/notes", { method: "POST", token: T_ALL, body: { title: "hello" }, headers: { "idempotency-key": "k1" } });
  await gw("/mcp", { method: "POST", token: T_ALL, body: { jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "hermes", version: "1" } } } });
  assert.ok(calls.length >= 3);
  for (const c of calls) {
    assert.equal(c.tokenHash, sha(T_ALL));
    assert.ok(!JSON.stringify(c).includes(T_ALL.slice(4)), "the token appears in an engine call");
  }
});

test("scope never comes from the request: headers, query and body cannot name a fleet or a depot", async () => {
  const { engine, calls } = fakeEngine();
  const gw = gateway(engine);
  const scopeHeaders = { "x-fleet-operator-id": "33333333-3333-3333-3333-333333333333", "x-depot-id": "22222222-2222-2222-2222-222222222222" };
  const ok = await gw("/v1/fleet", { token: T_READ, headers: scopeHeaders });
  assert.equal(ok.status, 200);
  assert.deepEqual(calls.at(-1).args, {});
  for (const [path, init] of [["/v1/fleet?fleet_operator_id=33333333-3333-3333-3333-333333333333", {}],
    ["/v1/vehicles/ee000000-0000-0000-0000-0000000000b1?depot_id=22222222-2222-2222-2222-222222222222", {}],
    ["/v1/requests", { method: "POST", body: { kind: "recall_vehicle", title: "x", vehicle_id: "ee000000-0000-0000-0000-0000000000b1", fleet_operator_id: "33333333-3333-3333-3333-333333333333" } }]]) {
    const before = calls.length;
    const res = await gw(path, { token: T_ALL, ...init });
    assert.equal(res.status, 400, path);
    assert.equal(calls.length, before + 1, "the refusal was not taken to the database");
    assert.equal(calls.at(-1).meta.gateway_refusal, "invalid_arguments", path);
    assert.deepEqual(calls.at(-1).args, {}, "refused arguments were forwarded");
  }
  // the whole engine surface: token hash, tool, validated args, transport, small request metadata -- no scope
  for (const c of calls) {
    assert.deepEqual(Object.keys(c.meta).filter((k) => !["http_method", "path", "ip", "client", "gateway_refusal", "mcp_method", "mcp_version"].includes(k)), []);
  }
});

test("REST: routes, path parameters, the idempotency header and the envelope", async () => {
  const { engine, calls } = fakeEngine();
  const gw = gateway(engine);
  const res = await gw("/v1/vehicles/ee000000-0000-0000-0000-0000000000a1", { token: T_READ, headers: { "user-agent": "hermes/1.0", "x-forwarded-for": "203.0.113.9, 10.0.0.1" } });
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("cache-control"), "no-store");
  assert.equal(res.headers.get("x-content-type-options"), "nosniff");
  assert.match(res.headers.get("content-type"), /^application\/json/);
  const b = await bodyOf(res);
  assert.deepEqual(b.meta, { tool: "vehicle_card", call_id: 1, principal: { name: "reader", kind: "fleet_operator" } });
  assert.deepEqual(calls[0].args, { vehicle_id: "ee000000-0000-0000-0000-0000000000a1" });
  assert.equal(calls[0].transport, "rest");
  assert.deepEqual(calls[0].meta, { http_method: "GET", path: "/v1/vehicles/ee000000-0000-0000-0000-0000000000a1", ip: "203.0.113.9", client: "hermes/1.0" });

  const note = await gw("/v1/notes", { method: "POST", token: T_ALL, body: { title: "Tire warning" }, headers: { "idempotency-key": "tire-1" } });
  assert.equal(note.status, 201);
  assert.deepEqual(calls.at(-1).args, { title: "Tire warning", idempotency_key: "tire-1" });

  await gw("/v1/requests/0b0b0b0b-0000-0000-0000-000000000001", { token: T_ALL });
  assert.deepEqual(calls.at(-1), { ...calls.at(-1), tool: "list_requests", args: { request_id: "0b0b0b0b-0000-0000-0000-000000000001" } });
  await gw("/v1/fleet?state=charging_dcfc&limit=5", { token: T_READ });
  assert.deepEqual(calls.at(-1).args, { state: "charging_dcfc", limit: 5 });

  const wrong = await gw("/v1/requests", { method: "DELETE", token: T_ALL });
  assert.equal(wrong.status, 405);
  assert.equal(wrong.headers.get("allow"), "GET, POST");
  const missing = await gw("/v1/garage", { token: T_ALL });
  assert.equal(missing.status, 404);
  const badJson = await bodyOf(await gw("/v1/requests", { method: "POST", token: T_ALL, body: "{" }));
  assert.equal(badJson.error.code, "invalid_json");
  const arr = await gw("/v1/requests", { method: "POST", token: T_ALL, body: "[]" });
  assert.equal(arr.status, 400);
});

test("REST: /v1/tools lists what this token may use, and 429s say when to come back only when waiting helps", async () => {
  const { engine } = fakeEngine({
    submit_request: () => ({ ok: false, http_status: 429, error: { code: "too_many_pending", message: "20 requests are waiting." } }),
  });
  const gw = gateway(engine);
  const tools = await bodyOf(await gw("/v1/tools", { token: T_NOTE }));
  assert.deepEqual(tools.data.tools.map((t) => t.name), ["whoami", "list_requests", "send_note"]);
  assert.ok(tools.data.tools.every((t) => t.input_schema.type === "object" && t.path.startsWith("/v1/")));
  const limited = await gw("/v1/whoami", { token: T_LIMITED });
  assert.equal(limited.status, 429);
  assert.equal(limited.headers.get("retry-after"), "60");
  const pending = await gw("/v1/requests", { method: "POST", token: T_ALL, body: { kind: "recall_vehicle", title: "x", vehicle_id: "ee000000-0000-0000-0000-0000000000a1" } });
  assert.equal(pending.status, 429);
  assert.equal(pending.headers.get("retry-after"), null, "waiting does not clear the pending cap; a person deciding does");
});

test("browsers: an unlisted Origin is refused before the engine; a listed one gets CORS", async () => {
  const { engine, calls } = fakeEngine();
  const closed = gateway(engine);
  for (const path of ["/v1/whoami", "/mcp"]) {
    const res = await closed(path, { method: path === "/mcp" ? "POST" : "GET", token: T_ALL, headers: { origin: "https://evil.example" }, body: path === "/mcp" ? {} : undefined });
    assert.equal(res.status, 403, path);
  }
  assert.equal(calls.length, 0);
  const open = gateway(engine, { allowedOrigins: ["https://pulse.ottoyard.com"] });
  const pre = await open("/v1/whoami", { method: "OPTIONS", headers: { origin: "https://pulse.ottoyard.com" } });
  assert.equal(pre.status, 204);
  assert.equal(pre.headers.get("access-control-allow-origin"), "https://pulse.ottoyard.com");
  assert.match(pre.headers.get("access-control-allow-headers"), /mcp-protocol-version/);
  const res = await open("/v1/whoami", { token: T_ALL, headers: { origin: "https://pulse.ottoyard.com" } });
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("access-control-allow-origin"), "https://pulse.ottoyard.com");
  assert.equal(res.headers.get("vary"), "Origin");
});

test("bodies over 64 KiB are refused, declared or streamed", async () => {
  const { engine, calls } = fakeEngine();
  const gw = gateway(engine);
  const big = JSON.stringify({ title: "x", body: "y".repeat(MAX_BODY_BYTES) });
  const declared = await gw("/v1/notes", { method: "POST", token: T_ALL, body: big });
  assert.equal(declared.status, 413);
  const stream = new ReadableStream({
    start(c) { for (let i = 0; i < 10; i++) c.enqueue(new TextEncoder().encode("z".repeat(8 * 1024))); c.close(); },
  });
  const streamed = await gw("/v1/notes", { method: "POST", token: T_ALL, raw: { body: stream, duplex: "half" } });
  assert.equal(streamed.status, 413);
  assert.equal(calls.length, 0);
  assert.equal(await readBodyBounded(null, 10), "");
  assert.equal(await readBodyBounded(new Response("abc").body, 3), "abc");
  assert.equal(await readBodyBounded(new Response("abcd").body, 3), null);
});

test("without its database connection the gateway fails closed, after authentication's first check", async () => {
  const gw = gateway(null);
  assert.equal((await gw("/v1/whoami")).status, 401);
  const res = await gw("/v1/whoami", { token: T_ALL });
  assert.equal(res.status, 500);
  assert.equal((await bodyOf(res)).error.code, "not_configured");
});

test("the A2A agent card is public, cacheable and describes the two interfaces and the token scheme", async () => {
  const { engine, calls } = fakeEngine();
  const gw = gateway(engine);
  for (const path of ["/.well-known/agent-card.json", "/.well-known/agent.json"]) {
    const res = await gw(path);
    assert.equal(res.status, 200, path);
    assert.equal(res.headers.get("access-control-allow-origin"), "*");
    assert.equal(res.headers.get("cache-control"), "public, max-age=300");
    const card = await bodyOf(res);
    assert.deepEqual(card, JSON.parse(JSON.stringify(agentCard(BASE))));
  }
  const card = agentCard(BASE);
  for (const k of ["name", "description", "version", "supportedInterfaces", "capabilities", "securitySchemes", "securityRequirements", "defaultInputModes", "defaultOutputModes", "skills"]) {
    assert.ok(card[k] !== undefined, k);
  }
  assert.deepEqual(card.supportedInterfaces.map((i) => i.url), [`${BASE}/mcp`, `${BASE}/v1`]);
  assert.equal(card.supportedInterfaces[0].protocolVersion, MCP_MODERN_VERSION);
  assert.equal(card.securitySchemes.ottoqAgentToken.httpAuthSecurityScheme.scheme, "Bearer");
  assert.deepEqual(Object.keys(card.securityRequirements[0].schemes), ["ottoqAgentToken"]);
  assert.deepEqual(card.skills.map((s) => s.id), TOOLS.map((t) => t.name));
  assert.ok(card.skills.every((s) => s.name && s.description && s.tags.length > 0));
  assert.equal(card.capabilities.streaming, false);
  assert.equal((await gw("/.well-known/agent-card.json", { method: "POST", body: "{}" })).status, 405);
  const head = await gw("/.well-known/agent-card.json", { method: "HEAD" });
  assert.equal(head.status, 200);
  assert.equal(await head.text(), "");
  const index = await bodyOf(await gw("/v1"));
  assert.ok(TOOLS.every((t) => index.endpoints.some((e) => e.tool === t.name && e.path === t.rest.path)));
  assert.equal((await gw("/")).status, 200);
  assert.equal(calls.length, 0, "discovery touched the engine");
});

// ═════════════════════════════════════════════════════════════════════════════════════════════ 4. mcp ══

const modernHeaders = (method, extra = {}) => ({ "content-type": "application/json", accept: "application/json, text/event-stream", "mcp-protocol-version": MCP_MODERN_VERSION, "mcp-method": method, ...extra });
const modern = (method, params = {}, id = 1) =>
  ({ jsonrpc: "2.0", id, method, params: { ...params, _meta: { "io.modelcontextprotocol/protocolVersion": MCP_MODERN_VERSION, "io.modelcontextprotocol/clientInfo": { name: "hermes", version: "2.1" } } } });

test("MCP tools/list: the token's tools, each with a closed JSON Schema and honest annotations", async () => {
  const { engine, calls } = fakeEngine();
  const gw = gateway(engine);
  const res = await gw("/mcp", { method: "POST", token: T_READ, headers: modernHeaders("tools/list"), body: modern("tools/list") });
  assert.equal(res.status, 200);
  const { result } = await bodyOf(res);
  assert.equal(result.resultType, "complete");
  assert.equal(result.cacheScope, "private", "the list varies by token");
  assert.ok(result.ttlMs > 0);
  assert.deepEqual(result.tools.map((t) => t.name), toolsFor(["read"]).map((t) => t.name));
  for (const t of result.tools) {
    assert.match(t.name, /^[a-z_]{1,64}$/);
    assert.ok(t.title && t.description);
    assert.equal(t.inputSchema.type, "object");
    assert.equal(t.inputSchema.additionalProperties, false);
    assert.equal(typeof t.annotations.readOnlyHint, "boolean");
  }
  assert.deepEqual(mcpToolList([...CAPABILITIES]).map((t) => t.name), TOOLS.map((t) => t.name));
  assert.equal(calls[0].tool, "handshake");
  assert.equal(calls[0].transport, "mcp");
  assert.deepEqual(calls[0].meta, { http_method: "POST", path: "/mcp", mcp_method: "tools/list", mcp_version: MCP_MODERN_VERSION, client: "hermes/2.1" });
});

test("MCP 2026-07-28: mirrored headers are required and must agree; unknown versions and methods are refused", async () => {
  const { engine, calls } = fakeEngine();
  const gw = gateway(engine);
  const post = (headers, body) => gw("/mcp", { method: "POST", token: T_ALL, headers, body });
  const code = async (res) => (await bodyOf(res)).error.code;

  let res = await post({ "mcp-protocol-version": MCP_MODERN_VERSION }, modern("tools/list"));
  assert.equal(res.status, 400); assert.equal(await code(res), JSONRPC.HEADER_MISMATCH);                 // no Mcp-Method
  res = await post(modernHeaders("tools/call"), modern("tools/list"));
  assert.equal(res.status, 400); assert.equal(await code(res), JSONRPC.HEADER_MISMATCH);                 // disagrees
  res = await post(modernHeaders("tools/list", { "mcp-protocol-version": "2025-11-25" }), modern("tools/list"));
  assert.equal(res.status, 400); assert.equal(await code(res), JSONRPC.HEADER_MISMATCH);                 // header vs _meta
  res = await post(modernHeaders("tools/list"), { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} });
  assert.equal(res.status, 400); assert.equal(await code(res), JSONRPC.HEADER_MISMATCH);                 // no _meta version
  res = await post(modernHeaders("tools/call"), modern("tools/call", { name: "whoami", arguments: {} }));
  assert.equal(res.status, 400); assert.equal(await code(res), JSONRPC.HEADER_MISMATCH);                 // no Mcp-Name
  res = await post(modernHeaders("tools/call", { "mcp-name": "fleet_summary" }), modern("tools/call", { name: "whoami", arguments: {} }));
  assert.equal(res.status, 400); assert.equal(await code(res), JSONRPC.HEADER_MISMATCH);                 // Mcp-Name disagrees
  res = await post({ "mcp-protocol-version": "2099-01-01" }, { jsonrpc: "2.0", id: 1, method: "tools/list" });
  assert.equal(res.status, 400);
  const unsupported = await bodyOf(res);
  assert.equal(unsupported.error.code, JSONRPC.UNSUPPORTED_PROTOCOL_VERSION);
  assert.deepEqual(unsupported.error.data.supported, [...MCP_SUPPORTED_VERSIONS]);
  res = await post(modernHeaders("resources/list"), modern("resources/list"));
  assert.equal(res.status, 404); assert.equal(await code(res), JSONRPC.METHOD_NOT_FOUND);
  assert.equal(calls.length, 0, "a refused protocol message reached the engine");

  res = await post(modernHeaders("tools/call", { "mcp-name": "=?base64?d2hvYW1p?=" }), modern("tools/call", { name: "whoami", arguments: {} }));
  assert.equal(res.status, 200, "the base64 sentinel form of Mcp-Name is accepted");
  const ok = await bodyOf(res);
  assert.equal(ok.result.isError, false);
  assert.equal(ok.result.resultType, "complete");
  assert.deepEqual(ok.result.structuredContent, { echo: { tool: "whoami", args: {} } });
  assert.deepEqual(JSON.parse(ok.result.content[0].text), ok.result.structuredContent);
});

test("MCP server/discover and ping (stateless), and initialize for older clients (no session minted)", async () => {
  const { engine } = fakeEngine();
  const gw = gateway(engine);
  const discover = await bodyOf(await gw("/mcp", { method: "POST", token: T_ALL, headers: modernHeaders("server/discover"), body: modern("server/discover") }));
  assert.deepEqual(discover.result.supportedVersions, [...MCP_SUPPORTED_VERSIONS]);
  assert.equal(discover.result.cacheScope, "public");
  assert.deepEqual(discover.result.capabilities, { tools: { listChanged: false } });
  assert.equal(discover.result._meta["io.modelcontextprotocol/serverInfo"].name, GATEWAY_NAME);
  const ping = await bodyOf(await gw("/mcp", { method: "POST", token: T_ALL, headers: modernHeaders("ping"), body: modern("ping") }));
  assert.deepEqual(ping.result, { resultType: "complete" });

  const init = (protocolVersion) => gw("/mcp", { method: "POST", token: T_ALL, headers: { "content-type": "application/json" },
    body: { jsonrpc: "2.0", id: "i1", method: "initialize", params: { protocolVersion, capabilities: {}, clientInfo: { name: "hermes", version: "1" } } } });
  for (const v of ["2025-11-25", "2025-06-18", "2025-03-26"]) {
    const res = await init(v);
    assert.equal(res.status, 200);
    assert.equal(res.headers.get("mcp-session-id"), null, "a stateless server mints no session");
    const b = await bodyOf(res);
    assert.equal(b.id, "i1");
    assert.equal(b.result.protocolVersion, v);
    assert.equal(b.result.serverInfo.name, GATEWAY_NAME);
    assert.match(b.result.instructions, /REQUEST/);
  }
  assert.equal((await bodyOf(await init("2024-11-05"))).result.protocolVersion, "2025-11-25", "an unknown version is answered with the latest");
  const legacyList = await bodyOf(await gw("/mcp", { method: "POST", token: T_NOTE, headers: { "mcp-protocol-version": "2025-06-18" }, body: { jsonrpc: "2.0", id: 2, method: "tools/list" } }));
  assert.deepEqual(legacyList.result.tools.map((t) => t.name), ["whoami", "list_requests", "send_note"]);
  assert.equal(legacyList.result.resultType, undefined, "no 2026 fields in a 2025 reply");
  const legacyUnknown = await gw("/mcp", { method: "POST", token: T_ALL, headers: { "mcp-protocol-version": "2025-06-18" }, body: { jsonrpc: "2.0", id: 3, method: "resources/list" } });
  assert.equal(legacyUnknown.status, 200);
  assert.equal((await bodyOf(legacyUnknown)).error.code, JSONRPC.METHOD_NOT_FOUND);
});

test("MCP notifications are authenticated and answered 202 with no body; malformed traffic is refused", async () => {
  const { engine, calls } = fakeEngine();
  const gw = gateway(engine);
  const note = await gw("/mcp", { method: "POST", token: T_ALL, headers: { "mcp-protocol-version": "2025-06-18" }, body: { jsonrpc: "2.0", method: "notifications/initialized" } });
  assert.equal(note.status, 202);
  assert.equal(await note.text(), "");
  assert.equal(calls.at(-1).tool, "handshake");
  const stranger = await gw("/mcp", { method: "POST", token: T_UNKNOWN, body: { jsonrpc: "2.0", method: "notifications/initialized" } });
  assert.equal(stranger.status, 401);
  for (const [body, status, code] of [["not json", 400, JSONRPC.PARSE_ERROR], ["[]", 400, JSONRPC.INVALID_REQUEST],
    [JSON.stringify({ jsonrpc: "1.0", id: 1, method: "ping" }), 400, JSONRPC.INVALID_REQUEST],
    [JSON.stringify({ jsonrpc: "2.0", id: null, method: "ping" }), 400, JSONRPC.INVALID_REQUEST],
    [JSON.stringify({ jsonrpc: "2.0", id: 1, method: "ping", params: [] }), 400, JSONRPC.INVALID_REQUEST],
    [JSON.stringify({ jsonrpc: "2.0", id: 1, result: {} }), 400, JSONRPC.INVALID_REQUEST]]) {
    const res = await gw("/mcp", { method: "POST", token: T_ALL, body });
    assert.equal(res.status, status, body);
    assert.equal((await bodyOf(res)).error.code, code, body);
  }
  for (const method of ["GET", "DELETE", "PUT"]) {
    const res = await gw("/mcp", { method, token: T_ALL });
    assert.equal(res.status, 405, method);
    assert.equal(res.headers.get("allow"), "POST");
  }
});

test("MCP tools/call: refusals are tool results an agent can read; auth and rate limits are transport errors", async () => {
  const { engine, calls } = fakeEngine({
    vehicle_card: () => ({ ok: false, http_status: 404, error: { code: "vehicle_not_found", message: "No vehicle with that id is in your scope." } }),
  });
  const gw = gateway(engine);
  const legacy = { "mcp-protocol-version": "2025-11-25" };
  const call = (token, name, args, id = 7) => gw("/mcp", { method: "POST", token, headers: legacy, body: { jsonrpc: "2.0", id, method: "tools/call", params: { name, arguments: args } } });

  let b = await bodyOf(await call(T_ALL, "vehicle_card", { vehicle_id: "ee000000-0000-0000-0000-0000000000b1" }));
  assert.equal(b.result.isError, true);
  assert.equal(b.result.structuredContent.error.code, "vehicle_not_found");
  b = await bodyOf(await call(T_ALL, "vehicle_card", { vehicle_id: "nope" }));
  assert.equal(b.result.isError, true);
  assert.equal(b.result.structuredContent.error.code, "invalid_arguments");
  assert.equal(b.result.structuredContent.error.details[0].path, "$.vehicle_id");
  assert.deepEqual(calls.at(-1).args, {}, "refused arguments were forwarded");
  b = await bodyOf(await call(T_ALL, "drop_tables", {}));
  assert.equal(b.error.code, JSONRPC.INVALID_PARAMS);
  assert.equal(calls.at(-1).tool, "drop_tables", "the unknown tool was not asked of the database (so not ledgered)");
  const unknown = await call(T_UNKNOWN, "whoami", {});
  assert.equal(unknown.status, 401);
  assert.equal((await bodyOf(unknown)).error.code, JSONRPC.UNAUTHORIZED);
  const strangerBadArgs = await call(T_UNKNOWN, "vehicle_card", { vehicle_id: "nope" });
  assert.equal(strangerBadArgs.status, 401, "an unknown token learned the schema before being refused");
  const limited = await call(T_LIMITED, "whoami", {});
  assert.equal(limited.status, 429);
  assert.equal(limited.headers.get("retry-after"), "60");
  assert.equal((await bodyOf(limited)).error.code, JSONRPC.RATE_LIMITED);
});

// ══════════════════════════════════════════════════════════════════════════════════════════ 5. engine ══

function fakeFetch(respond) {
  const seen = [];
  const f = async (url, init) => { seen.push({ url, init, body: JSON.parse(init.body) }); return respond(url, init); };
  return { f, seen };
}
const json = (status, body) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

test("the engine is one PostgREST call to ottoq_agent_call, with the key sent the way each key kind needs", async () => {
  assert.equal(ENGINE_RPC, "ottoq_agent_call");
  const reply = { ok: true, http_status: 200, tool: "whoami", call_id: 5, principal: { name: "hermes", kind: "personal", capabilities: ["read"] }, data: {} };
  const legacyKey = "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.c2ln";
  const { f, seen } = fakeFetch(() => json(200, reply));
  const out = await postgrestEngine({ supabaseUrl: "https://x.supabase.co/", serviceKey: legacyKey, fetchImpl: f })("ab".repeat(32), "whoami", { a: 1 }, "mcp", { path: "/mcp" });
  assert.deepEqual(out, reply);
  assert.equal(seen[0].url, "https://x.supabase.co/rest/v1/rpc/ottoq_agent_call");
  assert.equal(seen[0].init.method, "POST");
  assert.equal(seen[0].init.headers.apikey, legacyKey);
  assert.equal(seen[0].init.headers.Authorization, `Bearer ${legacyKey}`);
  assert.deepEqual(seen[0].body, { p_token_hash: "ab".repeat(32), p_tool: "whoami", p_args: { a: 1 }, p_transport: "mcp", p_meta: { path: "/mcp" } });
  const { f: f2, seen: seen2 } = fakeFetch(() => json(200, reply));
  await postgrestEngine({ supabaseUrl: "https://x.supabase.co", serviceKey: "sb_secret_abc", fetchImpl: f2 })("h", "whoami", {}, "rest", {});
  assert.equal(seen2[0].init.headers.apikey, "sb_secret_abc");
  assert.equal(seen2[0].init.headers.Authorization, undefined, "a non-JWT key is not a Bearer");
});

test("the engine's failures are named: not enabled, unreachable, timed out, misconfigured, off-contract", async () => {
  const run = async (respond, timeoutMs) => {
    const { f } = fakeFetch(respond);
    return postgrestEngine({ supabaseUrl: "https://x.supabase.co", serviceKey: "k", fetchImpl: f, timeoutMs })("h", "whoami", {}, "rest", {});
  };
  let r = await run(() => json(404, { code: "PGRST202", message: "Could not find the function public.ottoq_agent_call" }));
  assert.deepEqual([r.http_status, r.error.code], [503, "gateway_not_enabled"]);
  assert.match(r.error.message, /0550/);
  r = await run(() => { throw new TypeError("fetch failed"); });
  assert.deepEqual([r.http_status, r.error.code], [503, "engine_unreachable"]);
  r = await run(() => { throw new DOMException("The operation timed out.", "TimeoutError"); });
  assert.deepEqual([r.http_status, r.error.code], [504, "engine_timeout"]);
  // Node unrefs AbortSignal.timeout's timer, so hold the event loop open while the real timeout fires
  const keepAlive = setInterval(() => {}, 50);
  try {
    r = await run((_url, init) => new Promise((_res, rej) => init.signal.addEventListener("abort", () => rej(init.signal.reason))), 20);
  } finally {
    clearInterval(keepAlive);
  }
  assert.deepEqual([r.http_status, r.error.code], [504, "engine_timeout"], "the timeout is real, not only a mapping");
  r = await run(() => json(401, { message: "Invalid API key" }));
  assert.deepEqual([r.http_status, r.error.code], [502, "engine_misconfigured"]);
  r = await run(() => json(403, { code: "42501", message: "permission denied for function ottoq_agent_call" }));
  assert.deepEqual([r.http_status, r.error.code], [502, "engine_misconfigured"]);
  r = await run(() => json(200, { hello: "world" }));
  assert.deepEqual([r.http_status, r.error.code], [502, "engine_error"]);
  r = await run(() => new Response("<html>", { status: 500 }));
  assert.deepEqual([r.http_status, r.error.code], [502, "engine_error"]);
  // and over MCP an unreachable engine is a transport-level 5xx, so a client retries instead of reading a tool error
  const gw = gateway(async () => ({ ok: false, http_status: 503, tool: "whoami", call_id: null, error: { code: "engine_unreachable", message: "x" } }));
  const res = await gw("/mcp", { method: "POST", token: T_ALL, headers: { "mcp-protocol-version": "2025-06-18" }, body: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "whoami", arguments: {} } } });
  assert.equal(res.status, 503);
  assert.equal((await bodyOf(res)).error.code, JSONRPC.INTERNAL_ERROR);
});

// ═══════════════════════════════════════════════════════════════════════════════════════ 6. no writes ══

test("the edge function reaches the database through ottoq_agent_call and nothing else", () => {
  const shell = stripTsComments(SHELL);
  // a supabase-js table read is `.from("table")`; Array.from(...) and friends are not
  assert.doesNotMatch(shell, /\.from\(\s*["'`]|\.rpc\(|createClient|\/rest\/v1\/|fetch\(/, "the shell talks to the database itself");
  assert.match(shell, /postgrestEngine\(/);
  const shared = stripTsComments(SHARED);
  const restUrls = [...shared.matchAll(/\/rest\/v1\/[^`"'\s]*/g)].map((m) => m[0]);
  assert.deepEqual(restUrls, ["/rest/v1/rpc/${ENGINE_RPC}"]);
  assert.doesNotMatch(shared, /\.from\(\s*["'`]|\.rpc\(|createClient|\/storage\/v1|\/auth\/v1/);
  // imports: the dial-discipline module only (no network client, no Deno API)
  assert.deepEqual([...shared.matchAll(/^import .* from "([^"]+)";$/gm)].map((m) => m[1]), ["./agent_dial_discipline.ts"]);
  assert.doesNotMatch(shared, /\bDeno\./);
});

const WORLD_TABLES = ["vehicles", "stalls", "ottoq_stall_bookings", "ocpp_sessions", "ottoq_vehicle_commands",
  "ottoq_policy_params", "ottoq_itinerary_legs", "ottoq_events", "ottoq_decisions", "ottoq_ocpp_chargers",
  "ottoq_external_proposals", "ottoq_sim_runs", "depots", "fleet_operators", "staff_users"];
const DOORS = ["ottoq_hw_recall_vehicle", "ottoq_apply_ops_action", "ottoq_policy_set", "ottoq_submit_external_proposal",
  "ottoq_record_event", "ottoq_start_demo_run"];

test("no function an agent's token can reach names an engine door or writes outside the ottoq_agent_* tables", () => {
  // reachable from the dispatcher: itself, the tools it runs, and the helpers they call (never request_decide)
  const reachable = [...FUNCS.keys()].filter((n) => n.startsWith("ottoq_agent_") &&
    !["ottoq_agent_request_decide", "ottoq_agent_inbox", "ottoq_agent_requests_for_operator", "ottoq_agent_issue_token",
      "ottoq_agent_revoke", "ottoq_agent_expire_lapsed", "ottoq_agent_ledger_append_only", "ottoq_agent_no_truncate",
      "ottoq_agent_requests_guard", "ottoq_agent_principals_guard"].includes(n));
  assert.ok(reachable.includes("ottoq_agent_call") && reachable.includes("ottoq_agent_submit_request"));
  assert.ok(reachable.length >= 14, reachable.join(", "));
  for (const name of reachable) {
    const body = stripSqlComments(FUNCS.get(name));
    for (const door of DOORS) assert.ok(!body.includes(door), `${name} names ${door}`);
    for (const m of body.matchAll(/\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+(?:public\.)?([a-z_]+)/gi)) {
      assert.match(m[1], /^ottoq_agent_(requests|call_ledger|principals)$/, `${name} writes ${m[1]}`);
    }
    for (const t of WORLD_TABLES) {
      assert.doesNotMatch(body, new RegExp(`\\b(?:INSERT\\s+INTO|UPDATE|DELETE\\s+FROM|TRUNCATE)\\s+(?:public\\.)?${t}\\b`, "i"), `${name} writes ${t}`);
    }
  }
  // the ONE function that calls a door is the person's, and it is not reachable from a token
  const decide = stripSqlComments(FUNCS.get("ottoq_agent_request_decide"));
  assert.match(decide, /auth\.uid\(\)/);
  assert.match(decide, /public\.ottoq_hw_recall_vehicle\(/);
  assert.match(decide, /public\.ottoq_apply_ops_action\(/);
  assert.doesNotMatch(stripSqlComments(FUNCS.get("ottoq_agent_call")), /ottoq_agent_request_decide/);
  // and the grants say the same: the dispatcher is service_role's alone, the decide door authenticated's
  assert.match(M0550, /GRANT EXECUTE ON FUNCTION public\.ottoq_agent_call\(text, text, jsonb, text, jsonb\)\s+TO service_role;/);
  assert.doesNotMatch(M0550, /GRANT EXECUTE ON FUNCTION public\.ottoq_agent_call\([^)]*\)\s+TO [^;]*\b(anon|authenticated)\b/);
});

// ═════════════════════════════════════════════════════════════════════════════════════ 7. end to end ══
// The HTTP handler over the REAL 0550 SQL, executed against tests/fixtures/agent_gateway_stub_engine.sql (whose
// engine doors are byte-identical to the live catalog -- tests/test_agent_gateway_sql.py asserts it by md5).

function pgConn() {
  if (process.env.PGHOST) {
    return ["-h", process.env.PGHOST, "-p", process.env.PGPORT ?? "5432", "-U", process.env.PGUSER ?? "postgres"];
  }
  return ["-h", "/var/tmp", "-p", "55432", "-U", "postgres"];
}
function psql(db, sql, vars = {}) {
  const args = [...pgConn(), "-d", db, "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1"];
  for (const [k, v] of Object.entries(vars)) args.push("-v", `${k}=${v}`);
  const r = spawnSync("psql", args, { input: sql, encoding: "utf8" });
  if (r.status !== 0) throw new Error(`psql failed (${r.status}): ${r.stderr || r.error}`);
  return r.stdout.split("\n").filter((l) => l.trim() !== "");
}
const SERVER_UP = (() => {
  const r = spawnSync("psql", [...pgConn(), "-d", "postgres", "-X", "-Atc", "select 1"], { encoding: "utf8" });
  return r.status === 0;
})();

describe("end to end: the HTTP gateway over the real 0550 SQL", { skip: SERVER_UP ? false : "no scratch PostgreSQL (PGHOST or /var/tmp:55432)" }, () => {
  const DB = `ottoq_agw_node_${process.pid}_${randomBytes(3).toString("hex")}`;
  const W1 = "ee000000-0000-0000-0000-0000000000a1";
  const T1 = "ee000000-0000-0000-0000-0000000000b1";
  const SUPERVISOR = "a0000000-0000-0000-0000-00000000000a";
  const TECH = "c0000000-0000-0000-0000-00000000000c";
  const tokens = {};
  let gw;

  const sqlEngine = async (tokenHash, tool, args, transport, meta) => {
    const out = psql(DB, "SELECT ottoq_agent_call(:'h', :'t', :'a'::jsonb, :'tr', :'m'::jsonb);",
      { h: tokenHash, t: tool, a: JSON.stringify(args), tr: transport, m: JSON.stringify(meta) });
    return JSON.parse(out.at(-1));
  };
  const decideAs = (uid, requestId, decision) => JSON.parse(psql(DB,
    "SELECT set_config('request.jwt.claim.sub', :'uid', false);\nSET ROLE authenticated;\nSELECT ottoq_agent_request_decide(:'rid'::uuid, :'d', NULL);",
    { uid, rid: requestId, d: decision }).at(-1));
  const issue = (name, kind, caps, fleet) => JSON.parse(psql(DB,
    "SELECT ottoq_agent_issue_token(:'n', :'k', string_to_array(:'c', ',')::text[], NULLIF(:'f', '')::uuid, :'d'::uuid, NULL, 60, 20);",
    { n: name, k: kind, c: caps.join(","), f: fleet ?? "", d: TWIN_DEPOT_ID }).at(-1));

  before(() => {
    spawnSync("psql", [...pgConn(), "-d", "postgres", "-X", "-q", "-c", `CREATE DATABASE ${DB}`], { encoding: "utf8" });
    for (const f of [STUB_PATH, M0550_PATH, M0551_PATH]) {
      const r = spawnSync("psql", [...pgConn(), "-d", DB, "-X", "-q", "-v", "ON_ERROR_STOP=1", "-f", join(ROOT, f)], { encoding: "utf8" });
      if (r.status !== 0) throw new Error(`${f} did not load: ${r.stderr}`);
    }
    const hermes = issue("hermes", "personal", ["read", "note", "request_recall", "request_ops_action", "request_adjustment"]);
    const waymo = issue("waymo-agent", "fleet_operator", ["read", "note", "request_recall"], "22222222-2222-2222-2222-222222222222");
    const tesla = issue("tesla-agent", "fleet_operator", ["read", "note", "request_recall"], "33333333-3333-3333-3333-333333333333");
    assert.ok(hermes.ok && waymo.ok && tesla.ok);
    Object.assign(tokens, { hermes: hermes.token, waymo: waymo.token, tesla: tesla.token });
    for (const t of Object.values(tokens)) assert.ok(isWellFormedToken(t), "the database minted a token the edge would refuse");
    gw = gateway(sqlEngine);
  });
  after(() => {
    spawnSync("psql", [...pgConn(), "-d", "postgres", "-X", "-q", "-c", `DROP DATABASE IF EXISTS ${DB} WITH (FORCE)`], { encoding: "utf8" });
  });

  test("whoami over REST and MCP names the principal and its scope", async () => {
    const rest = await bodyOf(await gw("/v1/whoami", { token: tokens.waymo }));
    assert.equal(rest.data.principal.name, "waymo-agent");
    assert.equal(rest.data.scope.fleet_operator.id, "22222222-2222-2222-2222-222222222222");
    assert.deepEqual(rest.meta.principal, { name: "waymo-agent", kind: "fleet_operator" });
    const mcp = await bodyOf(await gw("/mcp", { method: "POST", token: tokens.hermes, headers: { "mcp-protocol-version": "2025-06-18" },
      body: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "whoami", arguments: {} } } }));
    assert.equal(mcp.result.isError, false);
    assert.equal(mcp.result.structuredContent.principal.name, "hermes");
  });

  test("operator A cannot read operator B's vehicle -- over REST or MCP -- and can read its own", async () => {
    const theirs = await gw(`/v1/vehicles/${T1}`, { token: tokens.waymo });
    assert.equal(theirs.status, 404);
    assert.equal((await bodyOf(theirs)).error.code, "vehicle_not_found");
    const mcp = await bodyOf(await gw("/mcp", { method: "POST", token: tokens.waymo, headers: modernHeaders("tools/call", { "mcp-name": "vehicle_card" }),
      body: modern("tools/call", { name: "vehicle_card", arguments: { vehicle_id: T1 } }) }));
    assert.equal(mcp.result.isError, true);
    assert.equal(mcp.result.structuredContent.error.code, "vehicle_not_found");
    const own = await gw(`/v1/vehicles/${W1}`, { token: tokens.waymo });
    assert.equal(own.status, 200);
    const fleet = await bodyOf(await gw("/v1/fleet", { token: tokens.waymo }));
    assert.ok(fleet.data.vehicles.length > 0);
    assert.ok(fleet.data.vehicles.every((v) => v.display_name.startsWith("Waymo")), JSON.stringify(fleet.data.vehicles.map((v) => v.display_name)));
  });

  test("operator A cannot act on operator B's vehicle, nor read B's requests", async () => {
    const onTheirs = await gw("/v1/requests", { method: "POST", token: tokens.waymo, body: { kind: "recall_vehicle", title: "not mine", vehicle_id: T1 } });
    assert.equal(onTheirs.status, 404);
    const mine = await gw("/v1/requests", { method: "POST", token: tokens.waymo, body: { kind: "recall_vehicle", title: "Bring W1 home: tire warning", vehicle_id: W1 } });
    assert.equal(mine.status, 201);
    const rid = (await bodyOf(mine)).data.request.request_id;
    const peek = await gw(`/v1/requests/${rid}`, { token: tokens.tesla });
    assert.equal(peek.status, 404);
    assert.equal((await bodyOf(peek)).error.code, "request_not_found");
    const opsByFleet = await gw("/v1/requests", { method: "POST", token: tokens.tesla, body: { kind: "ops_action", title: "x", action: "enable_energy_reserve" } });
    assert.equal(opsByFleet.status, 403);
  });

  test("a note reaches the crew, is replayed on retry, and the crew's decision comes back to the agent", async () => {
    const send = () => gw("/v1/notes", { method: "POST", token: tokens.hermes, headers: { "idempotency-key": "hermes-note-1" },
      body: { title: "Hermes here: testing the agent door", priority: "normal" } });
    const first = await send();
    assert.equal(first.status, 201);
    const rid = (await bodyOf(first)).data.request.request_id;
    const again = await send();
    assert.equal(again.status, 200);
    assert.equal((await bodyOf(again)).data.request.request_id, rid);
    assert.equal(decideAs(TECH, rid, "approved").error, "role_insufficient");
    assert.equal(decideAs(SUPERVISOR, rid, "approved").status, "acknowledged");
    const seen = await bodyOf(await gw(`/v1/requests/${rid}`, { token: tokens.hermes }));
    assert.equal(seen.data.requests[0].status, "acknowledged");
    assert.deepEqual(seen.data.requests[0].decided_by, { kind: "crew" });
  });

  test("an approved recall goes through the engine's own door, and the agent reads the door's reply", async () => {
    const asked = await bodyOf(await gw("/v1/requests", { method: "POST", token: tokens.hermes, body: { kind: "recall_vehicle", title: "Recall Zoox for inspection", vehicle_id: "ee000000-0000-0000-0000-0000000000c1" } }));
    const rid = asked.data.request.request_id;
    assert.equal(asked.data.request.status, "pending");
    const before = psql(DB, "SELECT count(*) FROM ottoq_vehicle_commands;").at(-1);
    const decided = decideAs(SUPERVISOR, rid, "approved");
    assert.equal(decided.status, "applied", JSON.stringify(decided));
    assert.equal(decided.engine_door, "ottoq_hw_recall_vehicle");
    assert.equal(Number(psql(DB, "SELECT count(*) FROM ottoq_vehicle_commands;").at(-1)), Number(before) + 1);
    const seen = await bodyOf(await gw(`/v1/requests/${rid}`, { token: tokens.hermes }));
    assert.equal(seen.data.requests[0].status, "applied");
    assert.equal(seen.data.requests[0].engine_reply.ok, true);
  });

  test("every call that presented a well-formed token is in the ledger, refusals and strangers included", async () => {
    const before = Number(psql(DB, "SELECT count(*) FROM ottoq_agent_call_ledger;").at(-1));
    await gw("/v1/whoami", { token: "oqa_" + "0".repeat(64) });
    await gw("/v1/vehicles/not-a-uuid", { token: tokens.tesla });
    await gw("/mcp", { method: "POST", token: tokens.tesla, headers: { "mcp-protocol-version": "2025-06-18" },
      body: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "drop_tables", arguments: {} } } });
    const rows = psql(DB, `SELECT coalesce(principal_name, '-') || '|' || transport || '|' || tool || '|' || http_status || '|' || coalesce(error_code, '') || '|' || coalesce(path, '')
                             FROM ottoq_agent_call_ledger ORDER BY call_id DESC LIMIT 3;`).reverse();
    assert.equal(Number(psql(DB, "SELECT count(*) FROM ottoq_agent_call_ledger;").at(-1)), before + 3);
    assert.deepEqual(rows, [
      "-|rest|whoami|401|unauthenticated|/v1/whoami",
      "tesla-agent|rest|vehicle_card|400|invalid_arguments|/v1/vehicles/not-a-uuid",
      "tesla-agent|mcp|drop_tables|404|unknown_tool|/mcp",
    ]);
    const leaked = psql(DB, `SELECT count(*) FROM ottoq_agent_call_ledger WHERE detail::text LIKE '%oqa_%';`).at(-1);
    assert.equal(leaked, "0", "a token reached the ledger");
  });
});
