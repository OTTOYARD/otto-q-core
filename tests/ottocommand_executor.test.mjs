// OTTO-Command as the one filter and executor between personal agents and OTTO-Q (db/migrations/0721, PERSONAL_AGENT.md
// section 11; Chase 2026-10-14): the MCP tool ask_ottocommand, the wider reads, the 50-second cap and production's
// preview-then-confirm, in the gateway's pure half and over the real SQL.
//
// WHAT EACH PART PROVES
//   1. the catalog   ask_ottocommand is offered to every token bound to a fleet (an owner key, a fleet reader, a passcode
//                    session, a signed-in agent) and to no other; the discovery documents list it once; the dispatcher
//                    never learns its name.
//   2. routing       a tools/call reaches the same door POST /v1/ask uses, through the caller's own call bound to
//                    transport 'ask' (a passcode session's too); bad arguments are refused after authenticating; a door
//                    that is off or refuses is a tool error, an unknown token a protocol error.
//   3. the budget    the whole ask is capped at 50 s, under Hermes's 60-s MCP timeout; each model call is cut at what is
//                    left; no engine call starts without its reserve.
//   4. production    the door never rewrites a command's mode: OTTO-Q decides. A lowering it records as a preview
//                    (confirm_required) is answered as not done, with what to confirm; the confirm goes out on the confirm
//                    door (transport 'confirm'), never as OTTO-Command's own call, with no model; the model can never send
//                    the arguments that name a preview.
//   5. end to end    (skips without a scratch server) the HTTP handler over the REAL 0559-0608, 0700 and 0721 SQL: a
//                    signed-in owner on a production run asks for a lower limit, OTTO-Q records a preview, and the confirm
//                    through ask_ottocommand applies it bound to that preview; the rows say who, which door and which
//                    preview; a passcode session there is refused with why.
import assert from "node:assert/strict";
import { createHash, randomBytes } from "node:crypto";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test, { after, before, describe } from "node:test";

import {
  agentCard,
  ASK_TOOL_NAME,
  askInputSchema,
  findTool,
  handleGatewayRequest,
  mcpPasscodeToolList,
  mcpToolList,
  openApiDocument,
  OWNER_COMMANDS,
  OWNER_READS,
  PASSCODE_TOOL_NAMES,
  restIndex,
  routeRest,
  TOOLS,
  toolsFor,
  TWIN_DEPOT_ID,
  validateToolArgs,
} from "../edge-functions/_shared/agent_gateway.ts";
import {
  anthropicModel,
  ASK_BUDGET_MS,
  ASK_ENGINE_RESERVE_MS,
  ASK_MIN_MODEL_MS,
  OTTOCOMMAND_READS,
  modelTools,
  ownerAskHandler,
  ownerContext,
  ownerTools,
  runOwnerAsk,
  SYSTEM_PROMPT,
} from "../edge-functions/_shared/ottocommand_owner.ts";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const BASE = "https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-agent-gateway";
const TESLA = "33333333-3333-3333-3333-333333333333";
const HASH = "0123456789abcdef0123456789abcdef";
const sha = (t) => createHash("sha256").update(t, "utf8").digest("hex");
const sorted = (xs) => [...xs].sort();
const bodyOf = async (res) => { const t = await res.text(); return t ? JSON.parse(t) : null; };
const mcpBody = (method, params = {}) => ({ jsonrpc: "2.0", id: 1, method, params: { ...params, _meta: { "io.modelcontextprotocol/protocolVersion": "2026-07-28" } } });
const mcpHeaders = (method, name) => ({ "mcp-protocol-version": "2026-07-28", "mcp-method": method, ...(name ? { "mcp-name": name } : {}) });

const T_OWNER = "oqa_" + "a".repeat(64);
const T_DEPOT = "oqa_" + "b".repeat(64);
const T_READER = "oqa_" + "c".repeat(64);
const T_SIGNED = "oqt_" + "d".repeat(64);
const T_SESSION = "oqs_" + "e".repeat(64);

const ownerBlock = (changes) => ({
  cars: 36, live_demo_run: changes?.run_kind === "demo" ? "5e5e5e5e-0000-0000-0000-000000000001" : null,
  live_production_run: changes?.run_kind === "production" ? "7e7e7e7e-0000-0000-0000-000000000001" : null,
  charge_limit_pct: { min: 80, max: 100 }, hold_max_hours: 24, requestable_services: [],
  ...(changes ? { changes } : {}),
});
const PRODUCTION = { allowed: true, run_kind: "production", person: "chase@ottoyard.com", lower_limit_needs_preview: true,
  message: "A production run is live. Changes are recorded under chase@ottoyard.com and lift when the run ends." };
const DEMO = { allowed: true, run_kind: "demo", person: "chase@ottoyard.com", message: "A demo run is live: settings apply to it and lift when it ends." };
const whoami = (fleet, changes) => ({
  principal: { name: "x", kind: "personal" },
  scope: { depot: { id: TWIN_DEPOT_ID, name: "OTTOYARD Nashville Flagship" }, fleet_operator: fleet ? { id: TESLA, name: "Tesla Robotaxi TN" } : null },
  owner: fleet && changes !== null ? ownerBlock(changes) : null,
});
const OWNER_CAPS = ["read", "note", "owner_settings"];
const principals = (changes = PRODUCTION) => new Map([
  [sha(T_OWNER), { name: "chase-hermes", capabilities: OWNER_CAPS, whoami: whoami(true, changes) }],
  [sha(T_SIGNED), { name: "oauth.hermes-agent.08e94d9e", capabilities: OWNER_CAPS, whoami: whoami(true, changes) }],
  [sha(T_SESSION), { name: "passcode.grok", capabilities: OWNER_CAPS, whoami: whoami(true, changes) }],
  [sha(T_READER), { name: "fleet-reader", capabilities: ["read"], whoami: whoami(true, null) }],
  [sha(T_DEPOT), { name: "depot-reader", capabilities: ["read"], whoami: whoami(false, null) }],
]);

const VIA = { ask: "ottocommand", confirm: "confirm" };
const NOTE = "Send this to apply exactly the plan shown, from the agent that previewed it, within 15 minutes; it confirms this preview once.";

/** A receipt as ottoq_owner_command_reply shapes one, for a preview or an apply (0721: the door is the transport's). */
function receipt(tool, args, n, transport) {
  const command_id = `cccccccc-0000-0000-0000-${String(n).padStart(12, "0")}`;
  const via = VIA[transport] ?? "direct";
  if (args.mode === "preview") {
    const { idempotency_key: _key, ...shown } = args;
    return { ok: true, http_status: 200, data: { outcome: "previewed", summary: `Preview only, nothing has changed. If you confirm: ${tool} ${args.percent ?? ""}%.`,
      command: { command_id, tool, mode: "preview", outcome: "previewed", plan_hash: HASH, via },
      confirm: { tool, args: { ...shown, mode: "apply", expect_plan_hash: HASH, confirms_command_id: command_id }, note: NOTE } } };
  }
  const link = `https://ottoyard-orchestra-av.lovable.app/?source=agent&command=${command_id}`;
  return { ok: true, http_status: 201, data: { outcome: "applied", summary: `Done. ${tool}.\nConfirmation code: OQ-ABCD-1234.\nSee it in OrchestrAV: ${link}`,
    confirmation_code: "OQ-ABCD-1234", link, command: { command_id, tool, mode: "apply", outcome: "applied", acting_person: "chase@ottoyard.com", via,
      ...(args.confirms_command_id ? { confirms_command_id: args.confirms_command_id } : {}) } } };
}

/** 0721, as the database answers it: on a production run a lower limit that names no preview applies nothing; it is
 *  recorded as a preview and answered 422 confirm_required, with that preview's confirm. */
function confirmRequired(tool, args, n, transport) {
  const prev = receipt(tool, { ...args, mode: "preview" }, n, transport);
  const refusal = { code: "confirm_required", reason: "not_named",
    message: "This is a production run, so lowering how full a car charges applies only as the confirm of a preview this agent recorded in the last 15 minutes. Nothing was applied.",
    hint: "Show your person the plan. Once they say yes, send the confirm object this answer carries." };
  return { ok: false, http_status: 422, error: { code: refusal.code, message: refusal.message, hint: refusal.hint },
    data: { ...prev.data, summary: `Not applied yet: OTTO-Q needs a confirm.\nIf you confirm: ${tool} ${args.percent}%.`,
      refusal: { ...refusal, preview_command_id: prev.data.command.command_id } } };
}

function fakeEngine(changes) {
  const calls = [];
  const byHash = principals(changes);
  const engine = async (tokenHash, tool, args, transport, meta) => {
    calls.push({ tokenHash, tool, args, transport, meta });
    const call_id = calls.length;
    const p = byHash.get(tokenHash);
    if (!p) return { ok: false, http_status: 401, tool, call_id, error: { code: "unauthenticated", message: "The token is unknown or has been revoked." } };
    const principal = { name: p.name, kind: "personal", capabilities: p.capabilities };
    if (meta.gateway_refusal === "invalid_arguments") return { ok: false, http_status: 400, tool, call_id, principal, error: { code: "invalid_arguments", message: "refused" } };
    if (tool === "handshake" || tool === "whoami") return { ok: true, http_status: 200, tool, call_id, principal, data: p.whoami };
    if (OWNER_COMMANDS.includes(tool)) {
      const lowers = tool === "set_charge_limit" && typeof args.percent === "number" && args.percent < 100;
      if (changes?.run_kind === "production" && lowers && args.mode !== "preview" && !args.confirms_command_id && !args.expect_plan_hash) {
        return { tool, call_id, principal, ...confirmRequired(tool, args, call_id, transport) };
      }
      return { tool, call_id, principal, ...receipt(tool, args, call_id, transport) };
    }
    if (tool === "my_fleet") return { ok: true, http_status: 200, tool, call_id, principal, data: { summary: "You have 36 cars.", cars: [{ vehicle_id: "ee000000-0000-0000-0000-0000000000b2", name: "Tesla-AV-041" }] } };
    if (tool === ASK_TOOL_NAME) return { ok: false, http_status: 404, tool, call_id, principal, error: { code: "unknown_tool", message: `No tool named ${tool}.` } };
    return { ok: true, http_status: 200, tool, call_id, principal, data: { echo: { tool, args } } };
  };
  return { engine, calls };
}

function scriptedModel(turns) {
  const requests = [];
  const model = async (req) => {
    requests.push(JSON.parse(JSON.stringify(req)));
    const next = turns[requests.length - 1];
    if (next === undefined) return { ok: true, content: [{ type: "text", text: "(the script ended)" }], stop_reason: "end_turn" };
    return typeof next === "function" ? next(req) : next;
  };
  return { model, requests };
}
const use = (...uses) => ({ ok: true, stop_reason: "tool_use", content: uses.map(([name, input], i) => ({ type: "tool_use", id: `tu_${name}_${i}`, name, input })) });
const say = (text) => ({ ok: true, stop_reason: "end_turn", content: [{ type: "text", text }] });

function gateway(engine, ask) {
  return (path, { method = "POST", token, headers = {}, body } = {}) => {
    const h = new Headers(headers);
    if (token !== undefined) h.set("authorization", `Bearer ${token}`);
    const init = { method, headers: h };
    if (body !== undefined) init.body = typeof body === "string" ? body : JSON.stringify(body);
    return handleGatewayRequest(new Request(`https://edge.internal/ottoq-agent-gateway${path}`, init), { publicUrl: BASE, allowedOrigins: [], engine, ask });
  };
}
const callTool = async (gw, path, token, name, args) => (await bodyOf(await gw(path, {
  token, headers: mcpHeaders("tools/call", name), body: mcpBody("tools/call", { name, arguments: args }) })));
const listTools = async (gw, path, token) => (await bodyOf(await gw(path, { token, headers: mcpHeaders("tools/list"), body: mcpBody("tools/list") })));

// ════════════════════════════════════════════════════════════════════════════════════════════ 1. the catalog ══

test("ask_ottocommand is offered to every token bound to a fleet, first among its fleet tools, and to no other", async () => {
  const door = findTool(ASK_TOOL_NAME);
  assert.ok(door && door.gateway === true && door.scope === "fleet" && door.capability === "read" && door.effect === "ask");
  assert.deepEqual(door.inputSchema, askInputSchema());
  assert.equal(door.annotations.readOnlyHint, false, "it can change the owner's settings through the owner's own tools");
  // 0721: one call can hold cars, order or withdraw services and undo commands, so a client gating destructive tools
  // must gate this one; the typed tools each stay non-destructive, so a client can gate them one by one
  assert.equal(door.annotations.destructiveHint, true);
  assert.deepEqual(mcpToolList(OWNER_CAPS, { fleetBound: true }).find((t) => t.name === ASK_TOOL_NAME).annotations,
    { title: "Ask OTTO-Command", readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false });
  for (const n of OWNER_COMMANDS) assert.equal(findTool(n).annotations.destructiveHint, false, n);
  const names = (caps, fleetBound) => toolsFor(caps, { fleetBound }).map((t) => t.name);
  assert.ok(names(OWNER_CAPS, true).includes(ASK_TOOL_NAME));
  assert.ok(names(["read"], true).includes(ASK_TOOL_NAME), "a fleet reader may ask questions");
  assert.ok(!names([...OWNER_CAPS, "request_recall"], false).includes(ASK_TOOL_NAME), "a depot-wide token is not offered it");
  assert.ok(!names(["note"], true).includes(ASK_TOOL_NAME), "without read there is nothing to ask");
  const fleetTools = names(OWNER_CAPS, true).filter((n) => findTool(n).scope === "fleet");
  assert.equal(fleetTools[0], ASK_TOOL_NAME);
  // a caller without a key: offered third, after the two public doors, with its required session
  assert.deepEqual(PASSCODE_TOOL_NAMES.slice(0, 3), ["welcome", "enter_passcode", ASK_TOOL_NAME]);
  const keyless = mcpPasscodeToolList().find((t) => t.name === ASK_TOOL_NAME);
  assert.deepEqual(keyless.inputSchema.required, ["session"]);
  assert.ok("text" in keyless.inputSchema.properties && "confirm" in keyless.inputSchema.properties);

  const { engine } = fakeEngine();
  const gw = gateway(engine);
  const listed = async (path, token) => (await listTools(gw, path, token)).result.tools.map((t) => t.name);
  assert.ok((await listed("/mcp", T_OWNER)).includes(ASK_TOOL_NAME));
  assert.ok((await listed("/account/mcp", T_SIGNED)).includes(ASK_TOOL_NAME), "the signed-in address lists it");
  assert.ok((await listed("/mcp", T_READER)).includes(ASK_TOOL_NAME));
  assert.ok(!(await listed("/mcp", T_DEPOT)).includes(ASK_TOOL_NAME));
  assert.ok((await listed("/mcp")).includes(ASK_TOOL_NAME), "the passcode door lists it");
  assert.deepEqual(mcpToolList(OWNER_CAPS, { fleetBound: true }).find((t) => t.name === ASK_TOOL_NAME).inputSchema, askInputSchema());
});

test("the discovery documents list the door once, as ask_ottocommand at POST /v1/ask", () => {
  const doc = openApiDocument(BASE);
  const op = doc.paths["/v1/ask"].post;
  assert.equal(op.operationId, ASK_TOOL_NAME);
  assert.equal(op["x-ottoq-tool"], ASK_TOOL_NAME);
  assert.equal(op["x-ottoq-effect"], "ask");
  assert.equal(op.requestBody.content["application/json"].schema.additionalProperties, false);
  assert.deepEqual(op.responses["200"].content["application/json"].schema, { $ref: "#/components/schemas/AskResponse" });
  assert.ok(op.parameters.some((p) => p.name === "Idempotency-Key" && p.in === "header"));
  assert.ok(doc.components.schemas.AskResponse.properties.data.properties.confirm);
  const ids = Object.values(doc.paths).flatMap((ops) => Object.values(ops).map((o) => o.operationId));
  assert.equal(ids.filter((i) => i === ASK_TOOL_NAME).length, 1);
  assert.ok(!ids.includes("ask"));
  const index = restIndex(BASE).endpoints.filter((e) => e.path === "/v1/ask");
  assert.deepEqual(index, [{ method: "POST", path: "/v1/ask", tool: ASK_TOOL_NAME, capability: "read", title: "Ask OTTO-Command" }]);
  assert.ok(agentCard(BASE).skills.some((s) => s.id === ASK_TOOL_NAME));
  assert.match(agentCard(BASE).description, /ask_ottocommand/);
  assert.deepEqual(routeRest("POST", "/v1/ask"), { tool: ASK_TOOL_NAME, pathArgs: {} });
});

test("Hermes's skill (v1.3) sends every request to ask_ottocommand first, and keeps the typed tools as the fallback", () => {
  const skill = readFileSync(join(ROOT, "integrations", "hermes", "ottoq-owner", "SKILL.md"), "utf8");
  assert.match(skill, /^version: 1\.3\.0$/m);
  const body = skill.slice(skill.indexOf("## Every request goes to OTTO-Command first"));
  assert.ok(body.length < skill.length, "the section exists");
  assert.equal(/mcp__ottoyard__(\w+)/.exec(body)[1], ASK_TOOL_NAME, "the first tool the section names is the door");
  assert.ok(body.indexOf("### Only if OTTO-Command is not available") < body.indexOf("mcp__ottoyard__set_charge_limit"));
});

test("the dispatcher never learns the door's name, so the database can never answer it as a tool", () => {
  for (const m of ["0559_an_outside_agent_asks_through_one_door_and_a_person_decides.sql",
    "0605_an_owners_agent_sets_what_its_own_cars_need_and_the_runs_end_puts_it_back.sql",
    "0607_any_agent_is_welcomed_and_the_demo_passcode_opens_the_fleet_until_the_run_ends.sql",
    "0721_a_signed_in_owner_changes_production_under_their_own_name.sql"]) {
    const sql = readFileSync(join(ROOT, "db", "migrations", m), "utf8");
    assert.doesNotMatch(sql, /WHEN 'ask_ottocommand'/, m);
  }
});

// ═══════════════════════════════════════════════════════════════════════════════════════════════ 2. routing ══

test("a tools/call reaches the same door as POST /v1/ask, through the caller's own call bound to transport 'ask'", async () => {
  const { engine, calls } = fakeEngine(DEMO);
  const { model, requests } = scriptedModel([use(["my_fleet", {}], ["depot_status", {}]), say("You have 36 cars; a demo run is live.")]);
  const gw = gateway(engine, ownerAskHandler({ model, modelName: "a-model" }));
  const out = await callTool(gw, "/account/mcp", T_SIGNED, ASK_TOOL_NAME, { text: "how are my cars?" });
  assert.equal(out.result.isError, false, JSON.stringify(out));
  const data = out.result.structuredContent;
  assert.equal(data.answer, "You have 36 cars; a demo run is live.");
  assert.equal(data.answered_by, "OTTO-Command");
  assert.deepEqual(data.reads, ["my_fleet", "depot_status"]);
  assert.equal(data.model, "a-model");
  assert.equal(data.call_id, 1);
  assert.match(out.result.content[0].text, /"answer": "You have 36 cars/);
  // every engine call is THIS token's, ledgered as the door's
  assert.deepEqual(calls.map((c) => [c.tool, c.transport, c.tokenHash === sha(T_SIGNED)]),
    [["handshake", "ask", true], ["my_fleet", "ask", true], ["depot_status", "ask", true]]);
  assert.equal(calls[0].meta.mcp_method, "tools/call");
  assert.equal(calls[0].meta.path, "/account/mcp");
  // the model is offered the owner's tools and the fleet's reads, never the door itself
  assert.deepEqual(sorted(requests[0].tools.map((t) => t.name)), sorted([...OWNER_READS, ...OTTOCOMMAND_READS, ...OWNER_COMMANDS]));
  assert.ok(!requests[0].tools.some((t) => t.name === ASK_TOOL_NAME || t.name === "fleet_summary" || t.name === "submit_request"));
});

test("a passcode session's ask goes through the session's own call, as the door's", async () => {
  const { engine, calls } = fakeEngine(DEMO);
  const { model } = scriptedModel([say("Your cars are fine.")]);
  const gw = gateway(engine, ownerAskHandler({ model }));
  const out = await callTool(gw, "/mcp", undefined, ASK_TOOL_NAME, { session: T_SESSION, text: "how are my cars?" });
  assert.equal(out.result.isError, false, JSON.stringify(out));
  assert.equal(out.result.structuredContent.answer, "Your cars are fine.");
  assert.deepEqual(calls.map((c) => [c.tool, c.transport, c.tokenHash === sha(T_SESSION)]), [["handshake", "ask", true]]);
  const noSession = await callTool(gw, "/mcp", undefined, ASK_TOOL_NAME, { text: "hi" });
  assert.equal(noSession.result.isError, true);
  assert.equal(calls.at(-1).tokenHash, null, "without a session it is asked of the database with no key, and refused there");
});

test("arguments the door refuses are refused after authenticating; a door that is off or refuses is a tool error", async () => {
  const { engine, calls } = fakeEngine(DEMO);
  const gw = gateway(engine, ownerAskHandler({ model: null }));
  for (const [args, path] of [[{}, "$.text"], [{ text: "x", confirm: [{ tool: "set_charge_limit", args: {} }] }, "$.text"],
    [{ text: "x", fleet_operator_id: TESLA }, "$.fleet_operator_id"], [{ confirm: [{ tool: "set_charge_limit", args: {} }], dry_run: true }, "$.dry_run"]]) {
    const r = await callTool(gw, "/mcp", T_OWNER, ASK_TOOL_NAME, args);
    assert.equal(r.result.isError, true, JSON.stringify(args));
    assert.equal(r.result.structuredContent.error.code, "invalid_arguments");
    assert.ok(r.result.structuredContent.error.details.some((d) => d.path === path), JSON.stringify(r.result.structuredContent));
    assert.deepEqual([calls.at(-1).tool, calls.at(-1).transport, calls.at(-1).meta.gateway_refusal], ["handshake", "ask", "invalid_arguments"]);
  }
  const off = await callTool(gw, "/mcp", T_OWNER, ASK_TOOL_NAME, { text: "how are my cars?" });
  assert.equal(off.result.isError, true);
  assert.equal(off.result.structuredContent.error.code, "ask_not_configured");
  const unplugged = await callTool(gateway(engine), "/mcp", T_OWNER, ASK_TOOL_NAME, { text: "how are my cars?" });
  assert.equal(unplugged.result.structuredContent.error.code, "ask_not_configured", "no door at all reads the same");
  // a depot-wide token is not offered the door, and the door refuses it by name
  const { model } = scriptedModel([say("never")]);
  const depot = await callTool(gateway(engine, ownerAskHandler({ model })), "/mcp", T_DEPOT, ASK_TOOL_NAME, { text: "hi" });
  assert.equal(depot.result.isError, true);
  assert.equal(depot.result.structuredContent.error.code, "ask_needs_an_owner_token");
  // an unknown token is the protocol's 401, before anything else
  const stranger = await gateway(engine, ownerAskHandler({ model }))("/mcp", { token: "oqa_" + "9".repeat(64),
    headers: mcpHeaders("tools/call", ASK_TOOL_NAME), body: mcpBody("tools/call", { name: ASK_TOOL_NAME, arguments: { text: "hi" } }) });
  assert.equal(stranger.status, 401);
  assert.ok(!calls.some((c) => c.tool === ASK_TOOL_NAME), "the database is never asked for a tool by the door's name");
});

test("POST /v1/ask honours the Idempotency-Key header, as every other POST does; the body's key wins", async () => {
  for (const [body, want] of [[{ text: "cap all at 90%" }, "hdr-1"], [{ text: "cap all at 90%", idempotency_key: "body-1" }, "body-1"]]) {
    const { engine, calls } = fakeEngine(DEMO);
    const { model } = scriptedModel([use(["set_charge_limit", { vehicles: "all", percent: 90 }]), say("Done.")]);
    const res = await gateway(engine, ownerAskHandler({ model }))("/v1/ask", { token: T_OWNER, headers: { "idempotency-key": "hdr-1" }, body });
    assert.equal(res.status, 200);
    assert.match(calls.find((c) => c.tool === "set_charge_limit").args.idempotency_key, new RegExp(`^${want}:[0-9a-f]{24}$`));
  }
});

// ═══════════════════════════════════════════════════════════════════════════════════════════════ 3. the budget ══

test("the ask is capped at 50 s, under Hermes's 60-s MCP timeout, and each model call is cut at what is left", async () => {
  assert.equal(ASK_BUDGET_MS, 50_000);
  assert.ok(ASK_BUDGET_MS + 15_000 - ASK_ENGINE_RESERVE_MS <= 60_000, "an engine call started at the reserve still ends inside 60 s");
  let t = 0;
  const { engine } = fakeEngine(DEMO);
  const who = { ok: true, http_status: 200, principal: { name: "x", kind: "personal", capabilities: OWNER_CAPS }, data: whoami(true, DEMO), call_id: 1 };
  const call = (tool, args, meta) => engine(sha(T_OWNER), tool, args, "ask", meta);
  // each model call takes 24 s and asks for a read: the first read runs (26 s left), the second does not (2 s left)
  const slow = scriptedModel([() => { t += 24_000; return use(["my_fleet", {}]); }, () => { t += 24_000; return use(["my_fleet", {}]); }]);
  const out = await runOwnerAsk({ text: "x", dry_run: false, history: [] }, { who, call, model: slow.model, now: () => t });
  assert.deepEqual(slow.requests.map((r) => r.timeout_ms), [50_000, 26_000]);
  assert.equal(out.status, 504);
  assert.equal(out.error.code, "ask_budget_spent");
  // an engine call is not started without its reserve: the model answered at 41 s and asked for a tool
  t = 0;
  const late = scriptedModel([() => { t += 41_000; return use(["set_charge_limit", { vehicles: "all", percent: 90 }]); }]);
  const half = await runOwnerAsk({ text: "x", dry_run: false, history: [] }, { who, call, model: late.model, now: () => t });
  assert.equal(half.status, 504);
  assert.equal(half.error.code, "ask_budget_spent");
  // and no model call is started with less than ASK_MIN_MODEL_MS left
  t = 0;
  const edge = scriptedModel([() => { t += 48_000; return say("first"); }]);
  const tight = await runOwnerAsk({ text: "x", dry_run: false, history: [] }, { who, call, model: edge.model, now: () => t, budgetMs: ASK_MIN_MODEL_MS - 1 });
  assert.equal(edge.requests.length, 0);
  assert.equal(tight.error.code, "ask_budget_spent");
});

test("the model call honours the request's timeout, never later than its own cap", async () => {
  // a fetch that never answers until its signal fires (Node's AbortSignal.timeout timer does not hold the event loop
  // open, so this one does, until the abort)
  const hang = (url, init) => new Promise((_, reject) => {
    const keep = setInterval(() => {}, 1_000);
    init.signal.addEventListener("abort", () => { clearInterval(keep); reject(Object.assign(new Error("t"), { name: "TimeoutError" })); });
  });
  const t0 = Date.now();
  const r = await anthropicModel({ apiKey: "k", model: "m", fetchImpl: hang, timeoutMs: 45_000 })({ system: "", tools: [], messages: [], max_tokens: 1, timeout_ms: 30 });
  assert.equal(r.ok, false);
  assert.equal(r.status, 504);
  assert.ok(Date.now() - t0 < 5_000, "cut at the request's 30 ms, not the 45 s cap");
  const capped = await anthropicModel({ apiKey: "k", model: "m", fetchImpl: hang, timeoutMs: 20 })({ system: "", tools: [], messages: [], max_tokens: 1, timeout_ms: 60_000 });
  assert.equal(capped.status, 504);
});

// ════════════════════════════════════════════════════════════════════════════════════════════════ 4. production ══

test("production: the door sends the change as asked; OTTO-Q records a lowering as a preview, and the confirm door applies it", async () => {
  const { engine, calls } = fakeEngine(PRODUCTION);
  const { model, requests } = scriptedModel([use(["set_charge_limit", { vehicles: "all", percent: 90, mode: "apply" }]), say("Done. All your Teslas now charge to 90%.")]);
  const gw = gateway(engine, ownerAskHandler({ model }));
  const words = "charge all my Teslas to 90% from now on";
  const out = await callTool(gw, "/account/mcp", T_SIGNED, ASK_TOOL_NAME, { text: words, idempotency_key: "tg-77" });
  const data = out.result.structuredContent;
  const sent = calls.find((c) => c.tool === "set_charge_limit");
  assert.deepEqual([sent.transport, sent.args.mode], ["ask", "apply"], "the door does not rewrite the mode: the database decides");
  assert.match(sent.args.idempotency_key, /^tg-77:[0-9a-f]{24}$/);
  assert.equal(data.actions[0].outcome, "previewed");
  assert.equal(data.actions[0].error.code, "confirm_required");
  assert.match(data.answer, /^Not applied yet: OTTO-Q needs a confirm\./, "the answer cannot say it was done");
  assert.match(data.answer, /\nNothing has changed yet: this is a production run, so lowering how full a car charges applies only when you confirm it, within 15 minutes\.$/);
  const pid = data.actions[0].command_id;
  assert.deepEqual(data.confirm, [{ tool: "set_charge_limit", args: { vehicles: "all", percent: 90, mode: "apply", expect_plan_hash: HASH, confirms_command_id: pid, note: words }, note: NOTE }]);
  // the context told the model, and the prompt says what to tell the owner
  assert.match(requests[0].messages[0].content, /Live: a PRODUCTION run\. Changes are allowed now, recorded under chase@ottoyard\.com\./);
  assert.match(requests[0].messages[0].content, /PRODUCTION RULE: OTTO-Q applies a lower charge limit \(or an undo that puts one back\) only as the confirm of a preview recorded in the last 15 minutes\./);
  assert.match(SYSTEM_PROMPT, /it comes back with error code confirm_required and outcome "previewed", and NOTHING has changed\. Then tell the owner exactly what they would be confirming/);
  // the owner says yes: the agent sends the confirm back, unchanged; it goes out on the confirm door, with no model
  const before = requests.length;
  const yes = await callTool(gw, "/account/mcp", T_SIGNED, ASK_TOOL_NAME, { confirm: data.confirm });
  assert.equal(yes.result.isError, false, JSON.stringify(yes));
  assert.equal(requests.length, before);
  const applied = calls.at(-1);
  assert.deepEqual([applied.tool, applied.transport, applied.args.mode, applied.args.expect_plan_hash, applied.args.confirms_command_id],
    ["set_charge_limit", "confirm", "apply", HASH, pid]);
  assert.equal(calls.at(-2).tool, "handshake");
  assert.equal(calls.at(-2).transport, "ask");
  assert.match(yes.result.structuredContent.answer, /^Done\. set_charge_limit\.\nConfirmation code: OQ-ABCD-1234\./);
  assert.equal(yes.result.structuredContent.actions[0].outcome, "applied");
});

test("the door never rewrites a command's mode, in production or not: whether a change needs a confirm is OTTO-Q's", async () => {
  for (const [changes, tool, args] of [
    [PRODUCTION, "set_charge_limit", { vehicles: "all", percent: 90 }],
    [PRODUCTION, "set_charge_limit", { vehicles: "all", percent: 100 }],
    [PRODUCTION, "clear_charge_limit", { vehicles: "all" }],
    [PRODUCTION, "undo_command", { command_id: "cccccccc-0000-0000-0000-000000000009" }],
    [DEMO, "set_charge_limit", { vehicles: "all", percent: 90 }],
  ]) {
    const { engine, calls } = fakeEngine(changes);
    const { model } = scriptedModel([use([tool, args]), say("Done.")]);
    await runOwnerAsk({ text: "x", dry_run: false, history: [] }, { who: await engine(sha(T_OWNER), "handshake", {}, "ask", {}), call: (t, a, m) => engine(sha(T_OWNER), t, a, "ask", m), model });
    assert.equal(calls.find((c) => c.tool === tool).args.mode, undefined, JSON.stringify([changes.run_kind, tool, args]));
  }
});

test("a confirm goes out on the confirm door, never as OTTO-Command's own call, over REST and MCP, keyed or not", async () => {
  const confirm = [{ tool: "set_charge_limit", args: { vehicles: "all", percent: 90, mode: "apply", expect_plan_hash: HASH, confirms_command_id: "cccccccc-0000-0000-0000-000000000001" } }];
  for (const [path, token, args] of [["/v1/ask", T_OWNER, null], ["/account/mcp", T_SIGNED, { confirm }], ["/mcp", T_OWNER, { confirm }],
    ["/mcp", undefined, { session: T_SESSION, confirm }]]) {
    const { engine, calls } = fakeEngine(PRODUCTION);
    const gw = gateway(engine, ownerAskHandler({ model: null }));
    if (args === null) {
      const res = await gw(path, { token, body: { confirm } });
      assert.equal(res.status, 200, path);
    } else {
      const out = await callTool(gw, path, token, ASK_TOOL_NAME, args);
      assert.equal(out.result.isError, false, JSON.stringify(out));
    }
    assert.deepEqual(calls.map((c) => [c.tool, c.transport]), [["handshake", "ask"], ["set_charge_limit", "confirm"]], `${path} ${token ? "key" : "session"}`);
    assert.equal(calls[1].tokenHash, sha(token ?? T_SESSION), "the same token, bound to the confirm door");
  }
  // a door with no confirm call refuses, and sends nothing as OTTO-Command's own call
  const { engine, calls } = fakeEngine(PRODUCTION);
  const who = await engine(sha(T_OWNER), "handshake", {}, "ask", {});
  const out = await runOwnerAsk({ dry_run: false, history: [], confirm }, { who, call: (t, a, m) => engine(sha(T_OWNER), t, a, "ask", m), model: null });
  assert.equal(out.status, 500);
  assert.equal(out.error.code, "confirm_not_wired");
  assert.equal(calls.length, 1, "only the handshake reached the engine");
});

test("the model can never send what names a preview: expect_plan_hash and confirms_command_id are not offered, and are stripped", async () => {
  const { engine, calls } = fakeEngine(PRODUCTION);
  const who = await engine(sha(T_OWNER), "handshake", {}, "ask", {});
  for (const t of modelTools(ownerTools(who), false)) {
    for (const k of ["expect_plan_hash", "confirms_command_id", "idempotency_key", "note"]) assert.ok(!(k in (t.input_schema.properties ?? {})), `${t.name} offers ${k}`);
  }
  assert.ok("confirms_command_id" in findTool("set_charge_limit").inputSchema.properties, "the typed tool takes it from a confirm object");
  const { model } = scriptedModel([use(["set_charge_limit", { vehicles: "all", percent: 90, expect_plan_hash: HASH, confirms_command_id: "cccccccc-0000-0000-0000-000000000001" }]), say("Done.")]);
  await runOwnerAsk({ text: "x", dry_run: false, history: [] }, { who, call: (t, a, m) => engine(sha(T_OWNER), t, a, "ask", m), model });
  const sent = calls.find((c) => c.tool === "set_charge_limit");
  assert.equal(sent.args.expect_plan_hash, undefined);
  assert.equal(sent.args.confirms_command_id, undefined);
  // and a typed confirms_command_id goes with mode apply only
  assert.deepEqual(validateToolArgs(findTool("hold_vehicle"), { vehicles: "all", for_minutes: 30, mode: "preview", confirms_command_id: "cccccccc-0000-0000-0000-000000000001" }).errors,
    [{ path: "$.confirms_command_id", message: "is for mode apply: it names the preview this apply confirms" }]);
});

test("the owner's context says whether changes are allowed now, why not, and under whose name", () => {
  const who = (changes) => ({ ok: true, http_status: 200, data: whoami(true, changes) });
  assert.match(ownerContext(who(PRODUCTION), false), /Live: a PRODUCTION run\. Changes are allowed now, recorded under chase@ottoyard\.com\./);
  assert.match(ownerContext(who(DEMO), false), /Live: a demo run\. Changes are allowed now, recorded under chase@ottoyard\.com\./);
  const refused = ownerContext(who({ allowed: false, run_kind: "production", code: "production_needs_a_person",
    message: "The live run at the twin depot is a production run, and a passcode session can read your cars there but not change them.",
    hint: "Sign your agent in to your OTTOYARD account and send it again." }), false);
  assert.match(refused, /Changes are NOT allowed now: The live run at the twin depot is a production run, and a passcode session can read your cars there but not change them\. Sign your agent in/);
  // a whoami from before 0721 still reads as it did
  assert.match(ownerContext(who(undefined), false), /Demo run live: no \(no change can be made until one starts\)\./);
  assert.match(SYSTEM_PROMPT, /what is allowed instead \(its hint, when it has one\)/);
  assert.match(SYSTEM_PROMPT, /stall_availability \(chargers and bays free at the depot now; it names no car\)/);
});

// ═════════════════════════════════════════════════════════════════════════════════════════════ 5. end to end ══

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
const loadFile = (db, f) => {
  const r = spawnSync("psql", [...pgConn(), "-d", db, "-X", "-q", "-v", "ON_ERROR_STOP=1", "-f", join(ROOT, f)], { encoding: "utf8" });
  if (r.status !== 0) throw new Error(`${f} did not load: ${r.stderr}`);
};
const SERVER_UP = spawnSync("psql", [...pgConn(), "-d", "postgres", "-X", "-Atc", "select 1"], { encoding: "utf8" }).status === 0;

describe("end to end: OTTO-Command over the real 0559-0608, 0700 and 0721 SQL", { skip: SERVER_UP ? false : "no scratch PostgreSQL (PGHOST or /var/tmp:55432)" }, () => {
  const DB = `ottoq_oc_node_${process.pid}_${randomBytes(3).toString("hex")}`;
  const WA = `${DB}_wa`;
  const AV041 = "ee000000-0000-0000-0000-0000000000b2";
  const CHAIN = ["tests/fixtures/agent_gateway_stub_engine.sql", "tests/fixtures/owner_agent_stub_engine.sql",
    "db/migrations/0559_an_outside_agent_asks_through_one_door_and_a_person_decides.sql",
    "db/migrations/0560_the_fleet_owner_cockpit_reads_its_own_agent_requests.sql",
    "db/migrations/0605_an_owners_agent_sets_what_its_own_cars_need_and_the_runs_end_puts_it_back.sql",
    "db/migrations/0606_the_fleet_owner_cockpit_reads_what_its_agent_set.sql",
    "db/migrations/0607_any_agent_is_welcomed_and_the_demo_passcode_opens_the_fleet_until_the_run_ends.sql",
    "db/migrations/0608_the_crew_and_the_twin_see_what_every_owners_agent_set_with_its_confirmation_code.sql",
    "tests/fixtures/agent_signin_stub_auth.sql",
    "db/migrations/0700_an_owner_signs_in_and_connects_their_own_agent.sql"];
  const signedIn = "oqt_" + randomBytes(32).toString("hex");
  let session;
  let run;

  const sqlEngine = async (tokenHash, tool, args, transport, meta) => {
    const out = psql(DB, "SELECT ottoq_agent_call(NULLIF(:'h', ''), :'t', :'a'::jsonb, :'tr', :'m'::jsonb);",
      { h: tokenHash ?? "", t: tool, a: JSON.stringify(args), tr: transport, m: JSON.stringify(meta) });
    return JSON.parse(out.at(-1));
  };

  before(() => {
    for (const d of [DB, WA]) spawnSync("psql", [...pgConn(), "-d", "postgres", "-X", "-q", "-c", `CREATE DATABASE ${d}`], { encoding: "utf8" });
    // production's world step as 0718 left it (the live definition, md5 546fa1ab), which 0721's P1 reads
    loadFile(WA, "tests/fixtures/world_advance_stub.sql");
    loadFile(WA, "db/migrations/0718_production_runs_the_world_phases_the_twin_certifies.sql");
    const wa = spawnSync("psql", [...pgConn(), "-d", WA, "-X", "-A", "-t", "-c", "SELECT pg_get_functiondef('twin.ottoq_world_advance()'::regprocedure)"], { encoding: "utf8" }).stdout;
    for (const f of CHAIN) loadFile(DB, f);
    psql(DB, `SET check_function_bodies = off;\n${wa.replace(/\n$/, "")};`);
    assert.equal(psql(DB, "SELECT md5(pg_get_functiondef('twin.ottoq_world_advance()'::regprocedure));").at(-1), "546fa1ab9bedd29f7169ee6b4e7c090b");
    psql(DB, `INSERT INTO vehicles (id, fleet_operator_id, home_depot_id, current_depot_id, make, model, display_name, current_soc, current_state, target_soc, av_api_vehicle_id) VALUES
      ('${AV041}', '${TESLA}', '${TWIN_DEPOT_ID}', '${TWIN_DEPOT_ID}', 'Tesla', 'Model Y', 'Tesla-AV-041', 72, 'charging_dcfc', 100, 'twin-sim-041');
      INSERT INTO auth.users (id, email) VALUES ('c4a5e000-0000-4000-8000-00000000c4a5', 'chase@ottoyard.com');
      SELECT ottoq_owner_account_link('chase@ottoyard.com', '${TESLA}', 'the founder');
      SELECT ottoq_agent_set_passcode('harbor-quartz-42');`);
    loadFile(DB, "db/migrations/0721_a_signed_in_owner_changes_production_under_their_own_name.sql");
    // a connection the way 0700 makes one, with an access token the gateway can be handed
    psql(DB, `INSERT INTO ottoq_oauth_clients (client_id, client_name, grant_types) VALUES ('oqc_${"0".repeat(32)}', 'Hermes Agent', ARRAY['urn:ietf:params:oauth:grant-type:device_code']);
      INSERT INTO ottoq_oauth_tokens (token_hash, kind, principal_id, expires_at)
      SELECT '${sha(signedIn)}', 'access', ottoq_oauth_connect('c4a5e000-0000-4000-8000-00000000c4a5', 'oqc_${"0".repeat(32)}', 'ottoyard:owner', 'https://x/account/mcp', 'device_code'), now() + interval '1 hour';`);
    run = psql(DB, "SELECT gen_random_uuid();").at(-1);
    psql(DB, `UPDATE ottoq_sim_runs SET status = 'completed' WHERE status IN ('running', 'paused');
      INSERT INTO ottoq_sim_runs (sim_run_id, depot_id, status, started_at, sim_clock_current, sim_clock_end, run_by)
      VALUES ('${run}', '${TWIN_DEPOT_ID}', 'running', clock_timestamp(), '2026-10-14 14:00+00', '2026-10-15 14:00+00', 'production_live');`);
    const unlocked = JSON.parse(psql(DB, `SELECT ottoq_agent_call(NULL, 'enter_passcode', '{"passcode":"harbor-quartz-42","agent":"Grok"}'::jsonb, 'mcp', '{"ip":"192.0.2.5"}'::jsonb);`).at(-1));
    session = unlocked.data.session;
  });
  after(() => {
    for (const d of [DB, WA]) spawnSync("psql", [...pgConn(), "-d", "postgres", "-X", "-q", "-c", `DROP DATABASE IF EXISTS ${d} WITH (FORCE)`], { encoding: "utf8" });
  });

  test("a signed-in owner on a production run asks for a lower limit; OTTO-Q records a preview, and the confirm applies it bound to it", async () => {
    const words = "charge all my Teslas to 90% from now on";
    const { model } = scriptedModel([use(["set_charge_limit", { vehicles: "all", percent: 90 }]), say("I have set that up.")]);
    const gw = gateway(sqlEngine, ownerAskHandler({ model }));
    const listed = (await listTools(gw, "/account/mcp", signedIn)).result.tools;
    assert.equal(listed.map((t) => t.name).filter((n) => findTool(n).scope === "fleet")[0], ASK_TOOL_NAME);
    assert.equal(listed.find((t) => t.name === ASK_TOOL_NAME).annotations.destructiveHint, true);
    const asked = await callTool(gw, "/account/mcp", signedIn, ASK_TOOL_NAME, { text: words });
    assert.equal(asked.result.isError, false, JSON.stringify(asked));
    const data = asked.result.structuredContent;
    assert.equal(data.actions[0].outcome, "previewed", JSON.stringify(data.actions));
    assert.equal(data.actions[0].error.code, "confirm_required");
    assert.equal(data.actions[0].args.mode, undefined, "the model asked to apply, and the door sent it as asked");
    assert.match(data.answer, /^Not applied yet: This is a production run, so lowering how full a car charges applies only as the confirm of a preview/);
    assert.equal(psql(DB, `SELECT count(*) FROM ottoq_owner_settings WHERE sim_run_id = '${run}';`).at(-1), "0");
    const pid = data.actions[0].command_id;
    assert.equal(data.confirm[0].args.confirms_command_id, pid);
    const yes = await callTool(gw, "/account/mcp", signedIn, ASK_TOOL_NAME, { confirm: data.confirm });
    assert.equal(yes.result.isError, false, JSON.stringify(yes));
    const done = yes.result.structuredContent;
    assert.equal(done.actions[0].outcome, "applied", JSON.stringify(done.actions));
    assert.match(done.answer, /^Done\./);
    assert.match(done.answer, /Confirmation code: OQ-[0-9A-F]{4}-[0-9A-F]{4}\./);
    assert.match(done.answer, /until the production run ends/);
    const rows = psql(DB, `SELECT mode || '|' || outcome || '|' || coalesce(acting_person, '-') || '|' || coalesce(via, '-') || '|' || coalesce(args ->> 'note', '-') || '|' || coalesce(confirms_command_id::text, '-')
                            FROM ottoq_owner_commands WHERE sim_run_id = '${run}' ORDER BY created_at;`);
    assert.deepEqual(rows, [`preview|previewed|chase@ottoyard.com|ottocommand|${words}|-`, `apply|applied|chase@ottoyard.com|confirm|${words}|${pid}`]);
    assert.equal(psql(DB, `SELECT round(ottoq_effective_target_soc_at('${AV041}', now()));`).at(-1), "90");
    const ledger = psql(DB, "SELECT tool || '|' || transport || '|' || coalesce(error_code, '-') FROM ottoq_agent_call_ledger ORDER BY call_id DESC LIMIT 4;");
    assert.deepEqual(ledger, ["set_charge_limit|confirm|-", "handshake|ask|-", "set_charge_limit|ask|confirm_required", "handshake|ask|-"]);
    // the same confirm again applies nothing more
    const again = await callTool(gw, "/account/mcp", signedIn, ASK_TOOL_NAME, { confirm: data.confirm });
    assert.notEqual(again.result.structuredContent.actions[0].outcome, "applied", JSON.stringify(again));
    assert.equal(psql(DB, `SELECT count(*) FROM ottoq_owner_commands WHERE sim_run_id = '${run}' AND outcome = 'applied';`).at(-1), "1");
  });

  test("a passcode session asking on a production run is told why not and what to do, and nothing changes", async () => {
    const { model } = scriptedModel([use(["request_service", { vehicles: "all", service: "exterior_wash" }]), say("Done! Washes booked.")]);
    const gw = gateway(sqlEngine, ownerAskHandler({ model }));
    const asked = await callTool(gw, "/mcp", undefined, ASK_TOOL_NAME, { session, text: "wash all my cars" });
    assert.equal(asked.result.isError, false, JSON.stringify(asked));
    const data = asked.result.structuredContent;
    assert.equal(data.actions[0].outcome, "refused");
    assert.equal(data.actions[0].error.code, "production_needs_a_person");
    assert.match(data.answer, /^Not done: The live run at the twin depot is a production run, and a passcode session can read your cars there but not change them/);
    assert.equal(psql(DB, `SELECT count(*) FROM ottoq_owner_settings WHERE sim_run_id = '${run}' AND kind = 'service';`).at(-1), "0");
    assert.equal(psql(DB, `SELECT coalesce(acting_person, '-') || '|' || via FROM ottoq_owner_commands WHERE tool = 'request_service' ORDER BY created_at DESC LIMIT 1;`).at(-1), "-|ottocommand");
  });
});
