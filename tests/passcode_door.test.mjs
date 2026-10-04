// The passcode door (otto-q-core 0607/0608) through the gateway: any agent, with no key, is welcomed over MCP or REST,
// enters OTTOYARD's demo passcode, and uses the session key it gets back -- as a tool's `session` argument over MCP,
// or as a Bearer on REST -- to read and adjust one fleet's cars until the demo run ends.
//
//   1. the catalog   welcome and enter_passcode are public; a caller without a key sees exactly the passcode tool list,
//                    every non-public tool with a required `session` argument; a key never needs enter_passcode.
//   2. MCP, no key   initialize, discovery, ping and tools/list need no database; a tool call reaches the one door bound
//                    to no key (welcome, enter_passcode) or to the session key it carries, hashed at the edge; a session
//                    problem is a tool result, never an HTTP 401.
//   3. REST, no key  GET /v1/welcome and POST /v1/passcode only; everything else is refused at the edge.
//   4. documents     OpenAPI marks the two doors security: []; the card and the instructions describe the passcode.
//   5. the answer    the plain-English door's answer carries every applied command's confirmation code.
//   6. end to end    (skips without a scratch server) the HTTP handler over the REAL 0559 + 0560 + 0605-0608 SQL.
import assert from "node:assert/strict";
import { createHash, randomBytes } from "node:crypto";
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test, { after, before, describe } from "node:test";

import {
  agentCard,
  findTool,
  handleGatewayRequest,
  isWellFormedToken,
  MCP_PASSCODE_INSTRUCTIONS,
  mcpPasscodeToolList,
  openApiDocument,
  PASSCODE_CAPABILITIES,
  PASSCODE_TOOL_NAMES,
  passcodeTools,
  SESSION_PATTERN,
  TOOLS,
  toolsFor,
  TWIN_DEPOT_ID,
  validateToolArgs,
} from "../edge-functions/_shared/agent_gateway.ts";
import { settleAnswer } from "../edge-functions/_shared/ottocommand_owner.ts";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const BASE = "https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-agent-gateway";
const sha = (t) => createHash("sha256").update(t, "utf8").digest("hex");
const SESSION = "oqs_" + "5".repeat(64);
const ENDED = "oqs_" + "6".repeat(64);
const KEY = "oqa_" + "1".repeat(64);
const bodyOf = async (res) => { const t = await res.text(); return t ? JSON.parse(t) : null; };
const mcpBody = (method, params = {}, id = 1) => ({ jsonrpc: "2.0", id, method, params: { ...params, _meta: { "io.modelcontextprotocol/protocolVersion": "2026-07-28" } } });
const mcpHeaders = (method, name) => ({ "mcp-protocol-version": "2026-07-28", "mcp-method": method, ...(name ? { "mcp-name": name } : {}) });
const legacy = { "mcp-protocol-version": "2025-06-18" };

/** A stand-in for public.ottoq_agent_call: no key may use welcome and enter_passcode; a session key or an agent key the
 *  rest; an ended session is answered as the database answers it. */
function fakeEngine() {
  const calls = [];
  const engine = async (tokenHash, tool, args, transport, meta) => {
    calls.push({ tokenHash, tool, args, transport, meta });
    const call_id = calls.length;
    if (tool === "welcome" && tokenHash === null) return { ok: true, http_status: 200, tool, call_id, data: { connected: false, summary: "Welcome to OTTOYARD." } };
    if (tool === "enter_passcode") {
      if (meta.gateway_refusal) return { ok: false, http_status: 400, tool, call_id, error: { code: "invalid_arguments", message: "enter_passcode takes {...}" } };
      if (args.passcode !== "harbor-quartz-42") return { ok: false, http_status: 403, tool, call_id, error: { code: "wrong_passcode", message: "That passcode is not right, so nothing was opened." } };
      return { ok: true, http_status: 201, tool, call_id, data: { summary: `Welcome, ${args.agent ?? "Agent"}.`, session: SESSION } };
    }
    if (tokenHash === sha(ENDED)) return { ok: false, http_status: 401, tool, call_id, error: { code: "session_ended", message: "This OTTOYARD session ended when the demo run ended." } };
    if (tokenHash !== sha(SESSION) && tokenHash !== sha(KEY)) {
      return { ok: false, http_status: 401, tool, call_id, error: { code: "unauthenticated",
        message: tokenHash === null ? "Connect first: call welcome, then enter_passcode with OTTOYARD's demo passcode." : "The token is unknown or has been revoked." } };
    }
    if (meta.gateway_refusal) return { ok: false, http_status: 400, tool, call_id, error: { code: "invalid_arguments", message: "refused" } };
    const principal = { name: tokenHash === sha(KEY) ? "chase-hermes" : "grok.a1b2c3", kind: "personal", capabilities: [...PASSCODE_CAPABILITIES] };
    if (tool === "handshake" || tool === "whoami") return { ok: true, http_status: 200, tool, call_id, principal, data: { scope: { fleet_operator: { id: "33333333-3333-3333-3333-333333333333", name: "Tesla Robotaxi TN" } } } };
    return { ok: true, http_status: 200, tool, call_id, principal, data: { echo: { tool, args } } };
  };
  return { engine, calls };
}

function gateway(engine) {
  return async (path, { method = "GET", token, headers = {}, body } = {}) => {
    const h = new Headers({ "content-type": "application/json", ...headers });
    if (token !== undefined) h.set("authorization", `Bearer ${token}`);
    const init = { method, headers: h };
    if (body !== undefined) init.body = typeof body === "string" ? body : JSON.stringify(body);
    return handleGatewayRequest(new Request(`https://edge.internal/functions/v1/ottoq-agent-gateway${path}`, init), { publicUrl: BASE, allowedOrigins: [], engine });
  };
}

// ════════════════════════════════════════════════════════════════════════════════════════ 1. the catalog ══

test("welcome and enter_passcode are the two public tools; a key never needs enter_passcode", () => {
  assert.deepEqual(TOOLS.filter((t) => t.public).map((t) => t.name), ["welcome", "enter_passcode"]);
  assert.equal(findTool("enter_passcode").effect, "session");
  assert.equal(findTool("enter_passcode").annotations.readOnlyHint, false);
  assert.deepEqual(findTool("enter_passcode").inputSchema.required, ["passcode"]);
  assert.ok(validateToolArgs(findTool("enter_passcode"), { passcode: "x", agent: "Grok" }).ok);
  assert.equal(validateToolArgs(findTool("enter_passcode"), { passcode: "x", fleet: "Tesla" }).ok, false);
  assert.equal(validateToolArgs(findTool("enter_passcode"), {}).ok, false);
  assert.ok(toolsFor(["read", "note", "owner_settings"], { fleetBound: true }).some((t) => t.name === "welcome"));
  assert.ok(!toolsFor(["read", "note", "owner_settings"], { fleetBound: true }).some((t) => t.name === "enter_passcode"));
});

test("a caller without a key sees the passcode list: the two doors, then each tool with a required session argument", () => {
  const list = passcodeTools();
  assert.deepEqual(list.map((t) => t.name), [...PASSCODE_TOOL_NAMES]);
  for (const t of list) {
    if (t.public) {
      assert.ok(!("session" in (t.inputSchema.properties ?? {})), t.name);
    } else {
      assert.equal(t.inputSchema.required[0], "session", t.name);
      assert.equal(t.inputSchema.properties.session.pattern, "^oqs_[0-9a-f]{64}$", t.name);
      assert.equal(t.inputSchema.additionalProperties, false, t.name);
    }
  }
  const tool = (n) => list.find((t) => t.name === n);
  assert.ok(validateToolArgs(tool("my_fleet"), { session: SESSION }).ok);
  assert.ok(validateToolArgs(tool("set_charge_limit"), { session: SESSION, vehicles: "all", percent: 90 }).ok);
  assert.equal(validateToolArgs(tool("my_fleet"), {}).ok, false, "a session tool without its session is refused by the schema");
  // the catalog itself is untouched: a keyed caller's tools carry no session argument
  assert.ok(!("session" in findTool("my_fleet").inputSchema.properties));
  assert.deepEqual(mcpPasscodeToolList().map((t) => t.name), [...PASSCODE_TOOL_NAMES]);
  assert.ok(SESSION_PATTERN.test(SESSION) && !SESSION_PATTERN.test(KEY));
  assert.ok(isWellFormedToken(SESSION) && isWellFormedToken(KEY));
});

// ════════════════════════════════════════════════════════════════════════════════════════ 2. MCP, no key ══

test("MCP with no key: initialize, discovery, ping, notifications and tools/list need no database", async () => {
  const { engine, calls } = fakeEngine();
  const gw = gateway(engine);
  const init = await bodyOf(await gw("/mcp", { method: "POST", body: { jsonrpc: "2.0", id: "i", method: "initialize",
    params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "grok", version: "4" } } } }));
  assert.equal(init.result.protocolVersion, "2025-06-18");
  assert.equal(init.result.instructions, MCP_PASSCODE_INSTRUCTIONS);
  assert.match(init.result.instructions, /enter_passcode/);
  assert.match(init.result.instructions, /`session` argument/);
  assert.match(init.result.instructions, /confirmation code and an OrchestrAV link/);
  const discover = await bodyOf(await gw("/mcp", { method: "POST", headers: mcpHeaders("server/discover"), body: mcpBody("server/discover") }));
  assert.equal(discover.result.instructions, MCP_PASSCODE_INSTRUCTIONS);
  const ping = await bodyOf(await gw("/mcp", { method: "POST", headers: mcpHeaders("ping"), body: mcpBody("ping") }));
  assert.deepEqual(ping.result, { resultType: "complete" });
  const note = await gw("/mcp", { method: "POST", headers: legacy, body: { jsonrpc: "2.0", method: "notifications/initialized" } });
  assert.equal(note.status, 202);
  const list = await bodyOf(await gw("/mcp", { method: "POST", headers: mcpHeaders("tools/list"), body: mcpBody("tools/list") }));
  assert.deepEqual(list.result.tools.map((t) => t.name), [...PASSCODE_TOOL_NAMES]);
  assert.equal(list.result.cacheScope, "public", "the same list for every caller without a key");
  assert.equal(calls.length, 0, "the database was asked something a caller without a key does not need it for");
});

test("MCP with no key: welcome and enter_passcode reach the one door bound to no key; refusals are tool results", async () => {
  const { engine, calls } = fakeEngine();
  const gw = gateway(engine);
  const call = (name, args) => gw("/mcp", { method: "POST", headers: mcpHeaders("tools/call", name), body: mcpBody("tools/call", { name, arguments: args }) });
  let res = await call("welcome", {});
  let b = await bodyOf(res);
  assert.equal(res.status, 200);
  assert.equal(b.result.isError, false);
  assert.equal(b.result.structuredContent.summary, "Welcome to OTTOYARD.");
  assert.deepEqual([calls.at(-1).tokenHash, calls.at(-1).tool, calls.at(-1).transport], [null, "welcome", "mcp"]);
  res = await call("enter_passcode", { passcode: "nope", agent: "Grok" });
  b = await bodyOf(res);
  assert.equal(res.status, 200, "a wrong passcode is the tool's answer, not a transport error");
  assert.equal(b.result.isError, true);
  assert.equal(b.result.structuredContent.error.code, "wrong_passcode");
  res = await call("enter_passcode", { passcode: "harbor-quartz-42", agent: "Grok" });
  b = await bodyOf(res);
  assert.equal(b.result.isError, false);
  assert.equal(b.result.structuredContent.session, SESSION);
  assert.deepEqual(calls.at(-1).args, { passcode: "harbor-quartz-42", agent: "Grok" });
  res = await call("enter_passcode", { agent: "Grok" });
  b = await bodyOf(res);
  assert.equal(b.result.structuredContent.error.code, "invalid_arguments");
  assert.equal(calls.at(-1).meta.gateway_refusal, "invalid_arguments", "the refused call was still ledgered");
  assert.deepEqual(calls.at(-1).args, {}, "refused arguments were forwarded");
});

test("MCP with no key: a tool call carries its session key, hashed at the edge and never forwarded", async () => {
  const { engine, calls } = fakeEngine();
  const gw = gateway(engine);
  const call = (name, args) => gw("/mcp", { method: "POST", headers: mcpHeaders("tools/call", name), body: mcpBody("tools/call", { name, arguments: args }) });
  const b = await bodyOf(await call("set_charge_limit", { session: SESSION, vehicles: "all", percent: 90 }));
  assert.equal(b.result.isError, false);
  assert.deepEqual(b.result.structuredContent, { echo: { tool: "set_charge_limit", args: { vehicles: "all", percent: 90 } } });
  assert.equal(calls.at(-1).tokenHash, sha(SESSION));
  assert.ok(!JSON.stringify(calls).includes(SESSION.slice(4)), "the session key reached the engine");
});

test("MCP with no key: no session, a malformed one, or an ended one is an answer to act on, never an HTTP 401", async () => {
  const { engine, calls } = fakeEngine();
  const gw = gateway(engine);
  const call = (name, args) => gw("/mcp", { method: "POST", headers: mcpHeaders("tools/call", name), body: mcpBody("tools/call", { name, arguments: args }) });
  let res = await call("my_fleet", {});
  let b = await bodyOf(res);
  assert.equal(res.status, 200);
  assert.equal(b.result.isError, true);
  assert.match(b.result.structuredContent.error.message, /^Connect first: call welcome, then enter_passcode/);
  assert.equal(calls.at(-1).tokenHash, null, "asked of the database with no key, so the attempt is ledgered");
  res = await call("my_fleet", { session: "oqs_not-a-key" });
  b = await bodyOf(res);
  assert.equal(res.status, 200);
  assert.equal(b.result.structuredContent.error.code, "invalid_session");
  res = await call("my_fleet", { session: ENDED });
  b = await bodyOf(res);
  assert.equal(res.status, 200, "an ended session must not look like 'this server needs OAuth'");
  assert.equal(b.result.isError, true);
  assert.equal(b.result.structuredContent.error.code, "session_ended");
  res = await call("my_fleet", { session: KEY });
  b = await bodyOf(res);
  assert.equal(b.result.structuredContent.error.code, "invalid_session", "a long-lived agent key never travels as an argument");
  res = await call("set_charge_limit", { session: SESSION, vehicles: "all", percent: "ninety" });
  b = await bodyOf(res);
  assert.equal(b.result.structuredContent.error.code, "invalid_arguments");
  assert.equal(b.result.structuredContent.error.details[0].path, "$.percent");
  res = await gw("/mcp", { method: "POST", headers: mcpHeaders("tools/call", "drop_tables"), body: mcpBody("tools/call", { name: "drop_tables", arguments: {} }) });
  assert.match((await bodyOf(res)).error.message, /Unknown tool: drop_tables\. Start with welcome\./);
});

test("MCP with a key: a session argument beside it is dropped, and the header decides", async () => {
  const { engine, calls } = fakeEngine();
  const gw = gateway(engine);
  const res = await gw("/mcp", { method: "POST", token: KEY, headers: mcpHeaders("tools/call", "my_fleet"),
    body: mcpBody("tools/call", { name: "my_fleet", arguments: { session: SESSION } }) });
  const b = await bodyOf(res);
  assert.equal(b.result.isError, false, JSON.stringify(b));
  assert.equal(calls.at(-1).tokenHash, sha(KEY));
  assert.deepEqual(calls.at(-1).args, {});
  const list = await bodyOf(await gw("/mcp", { method: "POST", token: KEY, headers: mcpHeaders("tools/list"), body: mcpBody("tools/list") }));
  assert.ok(list.result.tools.some((t) => t.name === "welcome") && !list.result.tools.some((t) => t.name === "enter_passcode"));
  assert.ok(!("session" in list.result.tools.find((t) => t.name === "my_fleet").inputSchema.properties));
});

// ═══════════════════════════════════════════════════════════════════════════════════════ 3. REST, no key ══

test("REST with no key: only GET /v1/welcome and POST /v1/passcode; then the session key is a Bearer like any other", async () => {
  const { engine, calls } = fakeEngine();
  const gw = gateway(engine);
  const hello = await gw("/v1/welcome");
  assert.equal(hello.status, 200);
  assert.equal((await bodyOf(hello)).data.summary, "Welcome to OTTOYARD.");
  const wrong = await gw("/v1/passcode", { method: "POST", body: { passcode: "nope" } });
  assert.equal(wrong.status, 403);
  assert.equal((await bodyOf(wrong)).error.code, "wrong_passcode");
  const right = await gw("/v1/passcode", { method: "POST", body: { passcode: "harbor-quartz-42", agent: "a script" } });
  assert.equal(right.status, 201);
  const key = (await bodyOf(right)).data.session;
  const before = calls.length;
  for (const [path, init] of [["/v1/me/fleet", {}], ["/v1/whoami", {}], ["/v1/tools", {}],
    ["/v1/me/charge-limit", { method: "POST", body: { vehicles: "all", percent: 90 } }], ["/v1/ask", { method: "POST", body: { text: "hi" } }]]) {
    const res = await gw(path, init);
    assert.equal(res.status, 401, path);
    assert.match((await bodyOf(res)).error.message, /No key\? GET \/v1\/welcome, then POST \/v1\/passcode/, path);
  }
  assert.equal(calls.length, before, "a REST call with no key reached the engine");
  const fleet = await gw("/v1/me/fleet", { token: key });
  assert.equal(fleet.status, 200);
  assert.equal(calls.at(-1).tokenHash, sha(SESSION));
});

// ═════════════════════════════════════════════════════════════════════════════════════════ 4. documents ══

test("OpenAPI: the two doors need no key; the scheme names both kinds of key; the card tells an agent where to start", () => {
  const doc = openApiDocument(BASE);
  assert.deepEqual(doc.paths["/v1/welcome"].get.security, []);
  assert.deepEqual(doc.paths["/v1/passcode"].post.security, []);
  assert.equal(doc.paths["/v1/me/fleet"].get.security, undefined, "every other operation keeps the document's Bearer");
  assert.ok(doc.paths["/v1/passcode"].post.responses["201"]);
  assert.equal(doc.paths["/v1/passcode"].post.responses["200"], undefined);
  assert.match(doc.components.securitySchemes.agentToken.bearerFormat, /oqa_ or oqs_/);
  const card = agentCard(BASE);
  assert.match(card.description, /start with the welcome tool/);
  assert.ok(card.skills.some((s) => s.id === "enter_passcode"));
});

// ═══════════════════════════════════════════════════════════════════════════════════════════ 5. the answer ══

test("the plain-English door's answer carries every applied command's confirmation code, above the link", () => {
  const applied = { tool: "set_charge_limit", args: {}, ok: true, http_status: 201, outcome: "applied", summary: "Done.",
    link: "https://ottoyard-orchestra-av.lovable.app/?source=agent&command=c1", command_id: "c1", confirmation_code: "OQ-B610-EA0E", cars: 4 };
  const refused = { ...applied, outcome: "refused", ok: false, link: null, confirmation_code: null };
  assert.equal(settleAnswer("Done. Your Teslas now charge to 90%.", [applied], false),
    "Done. Your Teslas now charge to 90%.\nConfirmation code: OQ-B610-EA0E.\nSee it in OrchestrAV: https://ottoyard-orchestra-av.lovable.app/?source=agent&command=c1");
  assert.equal(settleAnswer("Done (OQ-B610-EA0E): see https://ottoyard-orchestra-av.lovable.app/?source=agent&command=c1", [applied], false),
    "Done (OQ-B610-EA0E): see https://ottoyard-orchestra-av.lovable.app/?source=agent&command=c1", "nothing added twice");
  assert.equal(settleAnswer("It was not done: 70% is below your contract.", [refused], false), "It was not done: 70% is below your contract.");
  const two = settleAnswer("Done.", [applied, { ...applied, command_id: "c2", confirmation_code: "OQ-1234-ABCD" }], false);
  assert.match(two, /\nConfirmation codes: OQ-B610-EA0E, OQ-1234-ABCD\.\n/);
});

// ═════════════════════════════════════════════════════════════════════════════════════════ 6. end to end ══

function pgConn() {
  if (process.env.PGHOST) return ["-h", process.env.PGHOST, "-p", process.env.PGPORT ?? "5432", "-U", process.env.PGUSER ?? "postgres"];
  return ["-h", "/var/tmp", "-p", "55432", "-U", "postgres"];
}
function psql(db, sql, vars = {}) {
  const args = [...pgConn(), "-d", db, "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1"];
  for (const [k, v] of Object.entries(vars)) args.push("-v", `${k}=${v}`);
  const r = spawnSync("psql", args, { input: sql, encoding: "utf8" });
  if (r.status !== 0) throw new Error(`psql failed (${r.status}): ${r.stderr || r.error}`);
  return r.stdout.split("\n").filter((l) => l.trim() !== "");
}
const SERVER_UP = spawnSync("psql", [...pgConn(), "-d", "postgres", "-X", "-Atc", "select 1"], { encoding: "utf8" }).status === 0;

describe("end to end: any agent through the passcode door, over the real 0559-0608 SQL", { skip: SERVER_UP ? false : "no scratch PostgreSQL (PGHOST or /var/tmp:55432)" }, () => {
  const DB = `ottoq_door_node_${process.pid}_${randomBytes(3).toString("hex")}`;
  const TESLA = "33333333-3333-3333-3333-333333333333";
  const AV041 = "ee000000-0000-0000-0000-0000000000b2";
  const AV045 = "ee000000-0000-0000-0000-0000000000b3";
  const RT003 = "ee000000-0000-0000-0000-0000000000b4";
  const FILES = ["tests/fixtures/agent_gateway_stub_engine.sql", "tests/fixtures/owner_agent_stub_engine.sql",
    "db/migrations/0559_an_outside_agent_asks_through_one_door_and_a_person_decides.sql",
    "db/migrations/0560_the_fleet_owner_cockpit_reads_its_own_agent_requests.sql",
    "db/migrations/0605_an_owners_agent_sets_what_its_own_cars_need_and_the_runs_end_puts_it_back.sql",
    "db/migrations/0606_the_fleet_owner_cockpit_reads_what_its_agent_set.sql",
    "db/migrations/0607_any_agent_is_welcomed_and_the_demo_passcode_opens_the_fleet_until_the_run_ends.sql",
    "db/migrations/0608_the_crew_and_the_twin_see_what_every_owners_agent_set_with_its_confirmation_code.sql"];
  let run;

  // the gateway's one door, with SQL NULL for "no key" exactly as PostgREST sends a JSON null
  const sqlEngine = async (tokenHash, tool, args, transport, meta) => {
    const out = psql(DB, "SELECT ottoq_agent_call(NULLIF(:'h', ''), :'t', :'a'::jsonb, :'tr', :'m'::jsonb);",
      { h: tokenHash ?? "", t: tool, a: JSON.stringify(args), tr: transport, m: JSON.stringify(meta) });
    return JSON.parse(out.at(-1));
  };
  const freshRun = () => {
    const id = psql(DB, "SELECT gen_random_uuid();").at(-1);
    psql(DB, `UPDATE ottoq_sim_runs SET status = 'completed' WHERE status IN ('running', 'paused');
      INSERT INTO ottoq_sim_runs (sim_run_id, depot_id, status, started_at, sim_clock_current, sim_clock_end, run_by)
      VALUES ('${id}', '${TWIN_DEPOT_ID}', 'running', clock_timestamp(), '2026-09-27 12:00+00', '2026-09-28 08:00+00', 'operator_demo');
      UPDATE vehicles SET target_soc = 100 WHERE fleet_operator_id = '${TESLA}';
      INSERT INTO ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, atoms, target_soc) VALUES
        ('${AV041}', '${id}', '${TWIN_DEPOT_ID}', '2026-09-27 11:30+00', 'd41:${id}', '[{"svc":"charge","status":"in_progress","target_soc":100,"concurrency":"anchor"},{"svc":"readiness_check","concurrency":"gate"}]', 100),
        ('${AV045}', '${id}', '${TWIN_DEPOT_ID}', '2026-09-27 10:30+00', 'd45:${id}', '[{"svc":"charge","status":"done","target_soc":100},{"svc":"readiness_check","status":"done"}]', 100),
        ('${RT003}', '${id}', '${TWIN_DEPOT_ID}', '2026-09-27 11:00+00', 'd03:${id}', '[{"svc":"charge","status":"in_progress","target_soc":100},{"svc":"readiness_check"}]', 100);`);
    return id;
  };

  before(() => {
    spawnSync("psql", [...pgConn(), "-d", "postgres", "-X", "-q", "-c", `CREATE DATABASE ${DB}`], { encoding: "utf8" });
    for (const f of FILES) {
      const r = spawnSync("psql", [...pgConn(), "-d", DB, "-X", "-q", "-v", "ON_ERROR_STOP=1", "-f", join(ROOT, f)], { encoding: "utf8" });
      if (r.status !== 0) throw new Error(`${f} did not load: ${r.stderr}`);
    }
    psql(DB, `INSERT INTO vehicles (id, fleet_operator_id, home_depot_id, current_depot_id, make, model, display_name, current_soc, current_state, target_soc, av_api_vehicle_id) VALUES
      ('${AV041}', '${TESLA}', '${TWIN_DEPOT_ID}', '${TWIN_DEPOT_ID}', 'Tesla', 'Model Y', 'Tesla-AV-041', 72, 'charging_dcfc', 100, 'twin-sim-041'),
      ('${AV045}', '${TESLA}', '${TWIN_DEPOT_ID}', '${TWIN_DEPOT_ID}', 'Tesla', 'Model Y', 'Tesla-AV-045', 99, 'staged_for_departure', 100, 'twin-sim-045'),
      ('${RT003}', '${TESLA}', '${TWIN_DEPOT_ID}', '${TWIN_DEPOT_ID}', 'Tesla', 'Cybercab', 'Tesla-RT-003', 93, 'charging_l2', 100, NULL);
      SELECT ottoq_agent_set_passcode('harbor-quartz-42');`);
    run = freshRun();
  });
  after(() => {
    spawnSync("psql", [...pgConn(), "-d", "postgres", "-X", "-q", "-c", `DROP DATABASE IF EXISTS ${DB} WITH (FORCE)`], { encoding: "utf8" });
  });

  test("a new agent over MCP: welcome, the passcode, a change with its confirmation code, and the run's end", async () => {
    const gw = gateway(sqlEngine);
    const call = async (name, args) => (await bodyOf(await gw("/mcp", { method: "POST", headers: mcpHeaders("tools/call", name),
      body: mcpBody("tools/call", { name, arguments: args }) }))).result;
    const hello = await call("welcome", {});
    assert.equal(hello.isError, false);
    assert.match(hello.structuredContent.summary, /^Welcome to OTTOYARD\. You have reached OTTO-Q/);
    assert.match(hello.structuredContent.summary, /Tesla Robotaxi TN's 4 cars here \(3 Model Y and 1 Cybercab\)/);
    const wrong = await call("enter_passcode", { passcode: "guess", agent: "Grok" });
    assert.equal(wrong.isError, true);
    assert.match(wrong.structuredContent.error.message, /^That passcode is not right, so nothing was opened\./);
    const open = await call("enter_passcode", { passcode: "harbor-quartz-42", agent: "Grok" });
    assert.equal(open.isError, false, JSON.stringify(open));
    const session = open.structuredContent.session;
    assert.match(session, /^oqs_[0-9a-f]{64}$/);
    assert.match(open.structuredContent.summary, /^Welcome, Grok\. The passcode is right: you have Tesla Robotaxi TN's 4 cars/);
    const fleet = await call("my_fleet", { session });
    assert.equal(fleet.isError, false, JSON.stringify(fleet));
    const set = await call("set_charge_limit", { session, vehicles: "all", percent: 90 });
    assert.equal(set.isError, false, JSON.stringify(set));
    const code = set.structuredContent.confirmation_code;
    assert.match(code, /^OQ-[0-9A-F]{4}-[0-9A-F]{4}$/);
    assert.match(set.structuredContent.summary, new RegExp(`\\nConfirmation code: ${code}\\.\\nSee it in OrchestrAV: https://`));
    const low = await call("set_charge_limit", { session, vehicles: "all", percent: 70 });
    assert.equal(low.isError, true);
    assert.match(low.structuredContent.data.summary, /^Not done: 70% is below the 80% minimum in your contract/);
    // the crew's and the twin's read shows it, with the same code and the agent's own name
    const board = JSON.parse(psql(DB, "SET ROLE anon; SELECT ottoq_depot_owner_board();").at(-1));
    assert.ok(board.in_force.some((s) => s.kind === "charge_limit" && s.confirmation_code === code && s.agent === "Grok"));
    // a stop of the twin ends the session; the agent is told, as a tool result
    psql(DB, `UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '${run}';`);
    const after = await call("my_fleet", { session });
    assert.equal(after.isError, true);
    assert.equal(after.structuredContent.error.code, "session_ended");
    assert.match(after.structuredContent.error.message, /enter_passcode again/);
    run = freshRun();
  });

  test("a script over REST: welcome, the passcode, then the session key as a Bearer", async () => {
    const gw = gateway(sqlEngine);
    const hello = await bodyOf(await gw("/v1/welcome"));
    assert.equal(hello.data.passcode, "required");
    const opened = await gw("/v1/passcode", { method: "POST", body: { passcode: "harbor-quartz-42", agent: "a script" } });
    assert.equal(opened.status, 201);
    const session = (await bodyOf(opened)).data.session;
    const wash = await gw("/v1/me/services", { method: "POST", token: session, body: { vehicles: ["Tesla 45"], service: "exterior_wash", when: "every_return" } });
    assert.equal(wash.status, 201);
    const w = await bodyOf(wash);
    assert.match(w.data.confirmation_code, /^OQ-/);
    assert.equal(w.meta.principal.kind, "personal");
    assert.equal(psql(DB, `SELECT count(*) FROM ottoq_owner_settings WHERE sim_run_id = '${run}' AND vehicle_id = '${AV045}' AND service = 'exterior_wash' AND status = 'active';`).at(-1), "1");
    const noKey = await gw("/v1/me/fleet");
    assert.equal(noKey.status, 401);
  });
});
