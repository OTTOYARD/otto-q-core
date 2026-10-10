// OTTOYARD sign-in for an owner's own agent (otto-q-core 0660) through the gateway: the OAuth 2.1 endpoints, the
// signed-in MCP address, and the whole device sign-in over the real SQL.
//
//   1. documents      the protected-resource metadata points at OTTOYARD's authorization server; its metadata lists
//                     the gateway's endpoints; the 401 challenge names the metadata and the scope.
//   2. the address    /account/mcp sends anyone without an access token to sign in (401 + WWW-Authenticate), refuses
//                     an agent key or a passcode session there, and serves an access token through the one door; an
//                     expired or closed token is answered 401 invalid_token so the client refreshes.
//   3. the endpoints  registration, device authorization (the sign-in page's address added), the token endpoint (every
//                     secret hashed before the database sees it, PKCE S256 computed), revocation (always 200), the
//                     browser authorization (to the sign-in page, or back to the agent with the error).
//   4. end to end     (skips without a scratch server) the HTTP handler over the REAL 0559-0608 + 0660 SQL: an agent
//                     registers, asks for a device code, polls, its person approves on the page's doors, it connects,
//                     lists its tools and reads its fleet over MCP, refreshes, and is disconnected.
import assert from "node:assert/strict";
import { createHash, randomBytes } from "node:crypto";
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test, { after, before, describe } from "node:test";

import { handleGatewayRequest, TWIN_DEPOT_ID } from "../edge-functions/_shared/agent_gateway.ts";
import {
  ACCESS_TOKEN_PATTERN,
  accountChallenge,
  authorizationServerMetadata,
  DEVICE_GRANT,
  isSigninPath,
  parseForm,
  pkceS256,
  protectedResourceMetadata,
  resourceIsOurs,
} from "../edge-functions/_shared/agent_signin.ts";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const BASE = "https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-agent-gateway";
const ISSUER = "https://www.ottoyard.com";
const PAGE = "https://www.ottoyard.com/connect";
const CFG = { publicUrl: BASE, issuer: ISSUER, signinPage: PAGE };
const sha = (t) => createHash("sha256").update(t, "utf8").digest("hex");
const ACCESS = "oqt_" + "7".repeat(64);
const STALE = "oqt_" + "8".repeat(64);
const bodyOf = async (res) => { const t = await res.text(); return t ? JSON.parse(t) : null; };
const mcpBody = (method, params = {}, id = 1) => ({ jsonrpc: "2.0", id, method, params: { ...params, _meta: { "io.modelcontextprotocol/protocolVersion": "2026-07-28" } } });
const mcpHeaders = (method, name) => ({ "mcp-protocol-version": "2026-07-28", "mcp-method": method, ...(name ? { "mcp-name": name } : {}) });

/** A stand-in for public.ottoq_agent_call: an access token is an owner key; a stale one is answered as the database does. */
function fakeEngine() {
  const calls = [];
  const engine = async (tokenHash, tool, args, transport, meta) => {
    calls.push({ tokenHash, tool, args, transport, meta });
    if (tokenHash === sha(STALE)) return { ok: false, http_status: 401, tool, call_id: calls.length, error: { code: "token_expired", message: "This sign-in token expired." } };
    if (tokenHash !== sha(ACCESS)) return { ok: false, http_status: 401, tool, call_id: calls.length, error: { code: "unauthenticated", message: "The token is unknown or has been revoked." } };
    const principal = { name: "oauth.hermes-agent.0a1b2c3d", kind: "personal", capabilities: ["note", "owner_settings", "read"] };
    if (tool === "handshake") return { ok: true, http_status: 200, tool, call_id: calls.length, principal, data: { scope: { fleet_operator: { id: "33333333-3333-3333-3333-333333333333", name: "Tesla Robotaxi TN" } } } };
    return { ok: true, http_status: 200, tool, call_id: calls.length, principal, data: { echo: { tool, args } } };
  };
  return { engine, calls };
}

/** A stand-in for public.ottoq_agent_oauth that records what it was sent. */
function fakeOAuth(reply = () => ({ ok: true, http_status: 200, body: {} })) {
  const calls = [];
  const rpc = async (op, args, meta) => { calls.push({ op, args, meta }); return reply(op, args, meta); };
  return { rpc, calls };
}

function gateway({ engine = fakeEngine().engine, rpc = fakeOAuth().rpc, signin = true } = {}) {
  return async (path, { method = "GET", token, headers = {}, body, raw } = {}) => {
    const h = new Headers({ ...(raw === undefined ? { "content-type": "application/json" } : {}), ...headers });
    if (token !== undefined) h.set("authorization", `Bearer ${token}`);
    const init = { method, headers: h };
    if (raw !== undefined) init.body = raw;
    else if (body !== undefined) init.body = JSON.stringify(body);
    return handleGatewayRequest(new Request(`${BASE}${path}`, init),
      { publicUrl: BASE, allowedOrigins: [], engine, signin: signin ? { config: CFG, rpc } : null });
  };
}
const form = (o) => new URLSearchParams(o).toString();
const FORM = { "content-type": "application/x-www-form-urlencoded" };

// ═══════════════════════════════════════════════════════════════════════════════════════════ 1. documents ══

describe("documents", () => {
  test("the protected resource names OTTOYARD's authorization server, one scope, header bearer", () => {
    assert.deepEqual(protectedResourceMetadata(CFG), {
      resource: `${BASE}/account/mcp`, authorization_servers: [ISSUER], scopes_supported: ["fleet"],
      bearer_methods_supported: ["header"], resource_name: "OTTOYARD", resource_documentation: PAGE });
  });

  test("the authorization server's metadata: the issuer is ottoyard.com, the endpoints are the gateway's, the device grant is listed", () => {
    const m = authorizationServerMetadata(CFG);
    assert.equal(m.issuer, ISSUER);
    for (const k of ["authorization_endpoint", "token_endpoint", "device_authorization_endpoint", "registration_endpoint", "revocation_endpoint"]) {
      assert.ok(m[k].startsWith(`${BASE}/oauth/`), k);
    }
    assert.ok(m.grant_types_supported.includes(DEVICE_GRANT));
    assert.deepEqual(m.code_challenge_methods_supported, ["S256"]);
    assert.deepEqual(m.token_endpoint_auth_methods_supported, ["none"]);
    assert.equal(m.authorization_response_iss_parameter_supported, true);
  });

  test("the challenge names the metadata and the scope, and invalid_token only when a token was presented", () => {
    assert.equal(accountChallenge(BASE, false), `Bearer resource_metadata="${BASE}/.well-known/oauth-protected-resource/account/mcp", scope="fleet"`);
    assert.match(accountChallenge(BASE, true), /, error="invalid_token"$/);
  });

  test("the documents are served without a key, open to any origin, cacheable", async () => {
    const gw = gateway();
    for (const p of ["/.well-known/oauth-protected-resource/account/mcp", "/.well-known/oauth-protected-resource"]) {
      const res = await gw(p, { headers: { origin: "https://example.com" } });
      assert.equal(res.status, 200);
      assert.equal(res.headers.get("access-control-allow-origin"), "*");
      assert.deepEqual(await bodyOf(res), protectedResourceMetadata(CFG));
    }
    const meta = await gw("/oauth/metadata");
    assert.deepEqual(await bodyOf(meta), authorizationServerMetadata(CFG));
    assert.equal((await gw("/oauth/metadata", { method: "POST" })).status, 405);
  });

  test("without a sign-in configuration the paths answer 404", async () => {
    assert.equal((await gateway({ signin: false })("/oauth/metadata")).status, 404);
    assert.ok(isSigninPath("/oauth/token") && !isSigninPath("/mcp") && !isSigninPath("/account/mcp"));
  });

  test("parseForm reads a form once per key, or a JSON object; resourceIsOurs accepts the address or nothing", async () => {
    assert.deepEqual(parseForm("a=1&b=two%20words", "application/x-www-form-urlencoded"), { a: "1", b: "two words" });
    assert.equal(parseForm("a=1&a=2", "application/x-www-form-urlencoded"), null);
    assert.deepEqual(parseForm('{"a":"1","n":2}', "application/json"), { a: "1" });
    assert.ok(resourceIsOurs(undefined, BASE) && resourceIsOurs(`${BASE}/account/mcp/`, BASE) && resourceIsOurs(BASE.toUpperCase().replace("/FUNCTIONS/V1/OTTOQ-AGENT-GATEWAY", "/functions/v1/ottoq-agent-gateway") + "/account/mcp", BASE));
    assert.ok(!resourceIsOurs("https://evil.example/account/mcp", BASE));
    // RFC 7636 Appendix B's own example
    assert.equal(await pkceS256("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM");
  });
});

// ════════════════════════════════════════════════════════════════════════════════════════════ 2. the address ══

describe("the signed-in MCP address", () => {
  test("no token: 401 with the challenge, for GET (how a client discovers) and POST, and the database is never asked", async () => {
    const { engine, calls } = fakeEngine();
    const gw = gateway({ engine });
    for (const method of ["GET", "POST"]) {
      const res = await gw("/account/mcp", { method, headers: mcpHeaders("initialize"), body: method === "POST" ? mcpBody("initialize") : undefined });
      assert.equal(res.status, 401, method);
      assert.equal(res.headers.get("www-authenticate"), accountChallenge(BASE, false));
      assert.equal((await bodyOf(res)).error.data.code, "sign_in_required");
    }
    assert.equal(calls.length, 0);
  });

  test("an agent key or a passcode session is not an access token here", async () => {
    const { engine, calls } = fakeEngine();
    const gw = gateway({ engine });
    for (const token of ["oqa_" + "1".repeat(64), "oqs_" + "5".repeat(64), "nonsense"]) {
      const res = await gw("/account/mcp", { method: "POST", token, headers: mcpHeaders("tools/list"), body: mcpBody("tools/list") });
      assert.equal(res.status, 401, token);
      assert.equal(res.headers.get("www-authenticate"), accountChallenge(BASE, true));
    }
    assert.equal(calls.length, 0);
  });

  test("an access token reaches the one door, hashed; its tools are the owner's", async () => {
    const { engine, calls } = fakeEngine();
    const gw = gateway({ engine });
    const res = await gw("/account/mcp", { method: "POST", token: ACCESS, headers: mcpHeaders("tools/list"), body: mcpBody("tools/list") });
    assert.equal(res.status, 200);
    const names = (await bodyOf(res)).result.tools.map((t) => t.name);
    assert.ok(names.includes("my_fleet") && names.includes("set_charge_limit"));
    assert.ok(!names.includes("enter_passcode"));
    assert.equal(calls[0].tokenHash, sha(ACCESS));
    assert.equal(calls[0].transport, "mcp");
    assert.ok(!JSON.stringify(calls).includes(ACCESS));
  });

  test("an expired token: 401 invalid_token with the challenge, so the client refreshes", async () => {
    const gw = gateway();
    const res = await gw("/account/mcp", { method: "POST", token: STALE, headers: mcpHeaders("tools/list"), body: mcpBody("tools/list") });
    assert.equal(res.status, 401);
    assert.equal(res.headers.get("www-authenticate"), accountChallenge(BASE, true));
  });

  test("the passcode door at /mcp is unchanged: no key is still welcomed", async () => {
    const gw = gateway();
    const res = await gw("/mcp", { method: "POST", headers: { "mcp-protocol-version": "2025-06-18" }, body: { jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-06-18" } } });
    assert.equal(res.status, 200);
    assert.match((await bodyOf(res)).result.instructions, /passcode/);
  });

  test("an access token also works on REST, as a Bearer", async () => {
    const { engine, calls } = fakeEngine();
    const res = await gateway({ engine })("/v1/me/fleet", { token: ACCESS });
    assert.equal(res.status, 200);
    assert.equal(calls[0].tool, "my_fleet");
    assert.ok(ACCESS_TOKEN_PATTERN.test(ACCESS));
  });
});

// ══════════════════════════════════════════════════════════════════════════════════════════ 3. the endpoints ══

describe("the sign-in endpoints", () => {
  test("registration passes the agent's JSON to the database and answers its status, never cached", async () => {
    const { rpc, calls } = fakeOAuth(() => ({ ok: true, http_status: 201, body: { client_id: "oqc_" + "a".repeat(32), client_name: "Hermes Agent" } }));
    const res = await gateway({ rpc })("/oauth/register", { method: "POST", body: { client_name: "Hermes Agent", grant_types: [DEVICE_GRANT, "refresh_token"] },
      headers: { "x-forwarded-for": "203.0.113.4, 10.0.0.1", "user-agent": "hermes/1" } });
    assert.equal(res.status, 201);
    assert.equal(res.headers.get("cache-control"), "no-store");
    assert.equal(calls[0].op, "register");
    assert.equal(calls[0].args.client_name, "Hermes Agent");
    assert.equal(calls[0].meta.ip, "203.0.113.4");
    assert.equal((await gateway({ rpc })("/oauth/register", { method: "POST", raw: "not json", headers: { "content-type": "application/json" } })).status, 400);
  });

  test("a device request: the resource checked, the canonical resource sent, the sign-in page added to the answer", async () => {
    const { rpc, calls } = fakeOAuth(() => ({ ok: true, http_status: 200, body: { device_code: "oqd_" + "d".repeat(64), user_code: "BCDF-GHJK", expires_in: 600, interval: 5 } }));
    const gw = gateway({ rpc });
    const res = await gw("/oauth/device", { method: "POST", raw: form({ client_id: "oqc_x", resource: `${BASE}/account/mcp` }), headers: FORM });
    const b = await bodyOf(res);
    assert.equal(res.status, 200);
    assert.equal(b.verification_uri, PAGE);
    assert.equal(b.verification_uri_complete, `${PAGE}?code=BCDF-GHJK`);
    assert.equal(calls[0].args.resource, `${BASE}/account/mcp`);
    const wrong = await gw("/oauth/device", { method: "POST", raw: form({ client_id: "oqc_x", resource: "https://evil.example/mcp" }), headers: FORM });
    assert.equal(wrong.status, 400);
    assert.equal((await bodyOf(wrong)).error, "invalid_target");
    assert.equal(calls.length, 1);
  });

  test("the token endpoint hashes every secret and computes PKCE before the database sees anything", async () => {
    const { rpc, calls } = fakeOAuth((op, args) => ({ ok: false, http_status: 400, body: { error: "authorization_pending", error_description: "wait" } }));
    const gw = gateway({ rpc });
    const device = "oqd_" + randomBytes(32).toString("hex");
    const code = "oqg_" + randomBytes(32).toString("hex");
    const refresh = "oqr_" + randomBytes(32).toString("hex");
    const verifier = randomBytes(40).toString("base64url");
    const r1 = await gw("/oauth/token", { method: "POST", raw: form({ grant_type: DEVICE_GRANT, client_id: "oqc_x", device_code: device }), headers: FORM });
    assert.equal(r1.status, 400);
    assert.equal((await bodyOf(r1)).error, "authorization_pending");
    assert.equal(r1.headers.get("cache-control"), "no-store");
    await gw("/oauth/token", { method: "POST", raw: form({ grant_type: "authorization_code", client_id: "oqc_x", code, code_verifier: verifier, redirect_uri: "http://127.0.0.1:8420/callback" }), headers: FORM });
    await gw("/oauth/token", { method: "POST", raw: form({ grant_type: "refresh_token", client_id: "oqc_x", refresh_token: refresh }), headers: FORM });
    assert.equal(calls[0].args.device_code_hash, sha(device));
    assert.equal(calls[1].args.code_hash, sha(code));
    assert.equal(calls[1].args.code_challenge_s256, createHash("sha256").update(verifier).digest("base64url"));
    assert.equal(calls[2].args.refresh_token_hash, sha(refresh));
    const sent = JSON.stringify(calls);
    for (const secret of [device, code, refresh, verifier]) assert.ok(!sent.includes(secret), "a raw secret reached the database call");
  });

  test("a malformed secret is refused at the edge, without asking the database", async () => {
    const { rpc, calls } = fakeOAuth();
    const gw = gateway({ rpc });
    for (const f of [{ grant_type: DEVICE_GRANT, client_id: "c", device_code: "short" },
                     { grant_type: "authorization_code", client_id: "c", code: "oqg_" + "1".repeat(64) },
                     { grant_type: "refresh_token", client_id: "c", refresh_token: "oqa_" + "1".repeat(64) }]) {
      const res = await gw("/oauth/token", { method: "POST", raw: form(f), headers: FORM });
      assert.equal(res.status, 400);
      assert.equal((await bodyOf(res)).error, "invalid_grant");
    }
    assert.equal(calls.length, 0);
  });

  test("revocation answers 200 known or not, and sends only the token's hash", async () => {
    const { rpc, calls } = fakeOAuth();
    const res = await gateway({ rpc })("/oauth/revoke", { method: "POST", raw: form({ token: ACCESS }), headers: FORM });
    assert.equal(res.status, 200);
    assert.deepEqual(calls[0].args, { token_hash: sha(ACCESS), token_type_hint: undefined });
  });

  test("the browser authorization: to the sign-in page with the request, or back to the agent with its error", async () => {
    let reply = { ok: true, http_status: 200, body: { request_id: "8b9f7c3e-1d2a-4f5b-9c6d-7e8f9a0b1c2d" } };
    const { rpc, calls } = fakeOAuth(() => reply);
    const gw = gateway({ rpc });
    const q = "?" + form({ client_id: "oqc_x", redirect_uri: "http://127.0.0.1:8420/callback", response_type: "code", code_challenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", code_challenge_method: "S256", state: "s1" });
    const ok = await gw("/oauth/authorize" + q);
    assert.equal(ok.status, 302);
    assert.equal(ok.headers.get("location"), `${PAGE}?request=8b9f7c3e-1d2a-4f5b-9c6d-7e8f9a0b1c2d`);
    assert.equal(calls[0].args.issuer, ISSUER);
    assert.equal(calls[0].args.resource, `${BASE}/account/mcp`);
    reply = { ok: false, http_status: 400, body: { error: "invalid_request", error_description: "PKCE is required" }, redirect_uri: "http://127.0.0.1:8420/callback", state: "s1" };
    const back = new URL((await gw("/oauth/authorize" + q)).headers.get("location"));
    assert.equal(back.origin + back.pathname, "http://127.0.0.1:8420/callback");
    assert.deepEqual(Object.fromEntries(back.searchParams), { error: "invalid_request", error_description: "PKCE is required", state: "s1", iss: ISSUER });
    reply = { ok: false, http_status: 400, body: { error: "invalid_client", error_description: "Unknown client_id" } };
    const shown = await gw("/oauth/authorize" + q);
    assert.equal(shown.status, 400);
    assert.match(await shown.text(), /could not start this sign-in: Unknown client_id/);
  });
});

// ═══════════════════════════════════════════════════════════════════════════════════════════ 4. end to end ══

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

describe("end to end: an agent signs in by device code and uses its owner's fleet, over the real 0559-0608 + 0660 SQL", { skip: SERVER_UP ? false : "no scratch PostgreSQL (PGHOST or /var/tmp:55432)" }, () => {
  const DB = `ottoq_signin_${process.pid}_${randomBytes(3).toString("hex")}`;
  const FILES = ["tests/fixtures/agent_gateway_stub_engine.sql", "tests/fixtures/owner_agent_stub_engine.sql",
    "db/migrations/0559_an_outside_agent_asks_through_one_door_and_a_person_decides.sql",
    "db/migrations/0560_the_fleet_owner_cockpit_reads_its_own_agent_requests.sql",
    "db/migrations/0605_an_owners_agent_sets_what_its_own_cars_need_and_the_runs_end_puts_it_back.sql",
    "db/migrations/0606_the_fleet_owner_cockpit_reads_what_its_agent_set.sql",
    "db/migrations/0607_any_agent_is_welcomed_and_the_demo_passcode_opens_the_fleet_until_the_run_ends.sql",
    "db/migrations/0608_the_crew_and_the_twin_see_what_every_owners_agent_set_with_its_confirmation_code.sql",
    "tests/fixtures/agent_signin_stub_auth.sql",
    "db/migrations/0660_an_owner_signs_in_and_connects_their_own_agent.sql"];
  const TESLA = "33333333-3333-3333-3333-333333333333";
  const CHASE = "c4a5e000-0000-4000-8000-00000000c4a5";
  const AV041 = "a0000000-0000-4000-8000-000000000041";
  const sqlEngine = async (tokenHash, tool, args, transport, meta) => JSON.parse(psql(DB,
    "SELECT ottoq_agent_call(NULLIF(:'h', ''), :'t', :'a'::jsonb, :'tr', :'m'::jsonb);",
    { h: tokenHash ?? "", t: tool, a: JSON.stringify(args), tr: transport, m: JSON.stringify(meta) }).at(-1));
  const sqlOAuth = async (op, args, meta) => JSON.parse(psql(DB, "SELECT ottoq_agent_oauth(:'o', :'a'::jsonb, :'m'::jsonb);",
    { o: op, a: JSON.stringify(args), m: JSON.stringify(meta) }).at(-1));
  /** What the sign-in page does as the signed-in person: PostgREST runs the door with the person's JWT claims. */
  const asPerson = (uid, sql, vars = {}) => JSON.parse(psql(DB,
    `SELECT set_config('request.jwt.claims', :'c', false); SET ROLE authenticated; ${sql}`,
    { c: JSON.stringify({ sub: uid, role: "authenticated" }), ...vars }).at(-1));

  before(() => {
    spawnSync("psql", [...pgConn(), "-d", "postgres", "-X", "-q", "-c", `CREATE DATABASE ${DB}`], { encoding: "utf8" });
    for (const f of FILES) {
      const r = spawnSync("psql", [...pgConn(), "-d", DB, "-X", "-q", "-v", "ON_ERROR_STOP=1", "-f", join(ROOT, f)], { encoding: "utf8" });
      if (r.status !== 0) throw new Error(`${f} did not load: ${r.stderr}`);
    }
    psql(DB, `INSERT INTO auth.users (id, email) VALUES ('${CHASE}', 'chase@ottoyard.com');
      INSERT INTO vehicles (id, fleet_operator_id, home_depot_id, current_depot_id, make, model, display_name, current_soc, current_state, target_soc, av_api_vehicle_id)
      VALUES ('${AV041}', '${TESLA}', '${TWIN_DEPOT_ID}', '${TWIN_DEPOT_ID}', 'Tesla', 'Model Y', 'Tesla-AV-041', 72, 'charging_dcfc', 100, 'twin-sim-041');
      SELECT ottoq_owner_account_link('chase@ottoyard.com', '${TESLA}', 'e2e');`);
  });
  after(() => {
    spawnSync("psql", [...pgConn(), "-d", "postgres", "-X", "-q", "-c", `DROP DATABASE IF EXISTS ${DB} WITH (FORCE)`], { encoding: "utf8" });
  });

  test("register, device code, approve on the page, connect, read the fleet over MCP, refresh, disconnect", async () => {
    const gw = gateway({ engine: sqlEngine, rpc: sqlOAuth });
    // discovery, as an MCP client does it
    const challenge = await gw("/account/mcp");
    assert.equal(challenge.status, 401);
    const prmUrl = /resource_metadata="([^"]+)"/.exec(challenge.headers.get("www-authenticate"))[1];
    const prm = await bodyOf(await gw(new URL(prmUrl).pathname.replace("/functions/v1/ottoq-agent-gateway", "")));
    assert.deepEqual(prm.authorization_servers, [ISSUER]);
    // registration (what Hermes sends for its device login)
    const reg = await bodyOf(await gw("/oauth/register", { method: "POST", body: { client_name: "Hermes Agent",
      redirect_uris: ["http://127.0.0.1:8420/callback"], grant_types: [DEVICE_GRANT, "refresh_token"], response_types: [],
      token_endpoint_auth_method: "none", application_type: "native" } }));
    assert.match(reg.client_id, /^oqc_[0-9a-f]{32}$/);
    const dev = await bodyOf(await gw("/oauth/device", { method: "POST", raw: form({ client_id: reg.client_id, resource: prm.resource }), headers: FORM }));
    assert.match(dev.user_code, /^[BCDFGHJKLMNPQRSTVWXZ]{4}-[BCDFGHJKLMNPQRSTVWXZ]{4}$/);
    assert.equal(dev.verification_uri, PAGE);
    const poll = async () => { const r = await gw("/oauth/token", { method: "POST", headers: FORM,
      raw: form({ grant_type: DEVICE_GRANT, client_id: reg.client_id, device_code: dev.device_code, resource: prm.resource }) }); return { status: r.status, body: await bodyOf(r) }; };
    assert.equal((await poll()).body.error, "authorization_pending");
    assert.equal((await poll()).body.error, "slow_down");
    // the person, signed in on the page: an account with no fleet link is turned away, Chase's sees Hermes and approves
    const stranger = asPerson("d0000000-0000-4000-8000-0000000000d0", "SELECT ottoq_oauth_device_lookup(:'u');", { u: dev.user_code });
    assert.equal(stranger.code, "not_linked");
    const look = asPerson(CHASE, "SELECT ottoq_oauth_device_lookup(:'u');", { u: dev.user_code.toLowerCase() });
    assert.equal(look.agent, "Hermes Agent");
    assert.equal(look.fleet.name, "Tesla Robotaxi TN");
    const ok = asPerson(CHASE, "SELECT ottoq_oauth_device_decide(:'u', 'approve');", { u: dev.user_code });
    assert.equal(ok.outcome, "approved");
    psql(DB, "UPDATE ottoq_oauth_device_codes SET last_polled_at = now() - interval '10 seconds' WHERE user_code = :'u';", { u: dev.user_code });
    const tok = await poll();
    assert.equal(tok.status, 200);
    assert.match(tok.body.access_token, ACCESS_TOKEN_PATTERN);
    assert.equal(tok.body.token_type, "Bearer");
    assert.equal(tok.body.expires_in, 3600);
    assert.equal((await poll()).body.error, "invalid_grant", "a device code connects once");
    // MCP with the access token: the owner's tools, the owner's fleet, whoami says how it got in
    const mcp = async (method, params, token = tok.body.access_token) => gw("/account/mcp", { method: "POST", token,
      headers: mcpHeaders(method, method === "tools/call" ? params.name : undefined), body: mcpBody(method, params) });
    const tools = (await bodyOf(await mcp("tools/list", {}))).result.tools.map((t) => t.name);
    assert.ok(tools.includes("my_fleet") && tools.includes("request_service"));
    const fleet = (await bodyOf(await mcp("tools/call", { name: "my_fleet", arguments: {} }))).result;
    assert.equal(fleet.isError, false);
    const who = (await bodyOf(await mcp("tools/call", { name: "whoami", arguments: {} }))).result.structuredContent;
    assert.equal(who.principal.via, "signed in");
    assert.equal(who.principal.account, "chase@ottoyard.com");
    // the account page lists the connection
    const me = asPerson(CHASE, "SELECT ottoq_account_me();");
    assert.equal(me.connections.length, 1);
    assert.equal(me.connections[0].state, "connected");
    // refresh rotates; the old access token keeps working until its hour is up
    const ref = await bodyOf(await gw("/oauth/token", { method: "POST", headers: FORM,
      raw: form({ grant_type: "refresh_token", client_id: reg.client_id, refresh_token: tok.body.refresh_token }) }));
    assert.notEqual(ref.refresh_token, tok.body.refresh_token);
    assert.equal((await mcp("tools/list", {}, ref.access_token)).status, 200);
    // the owner disconnects it on the page: the token stops, refreshing is refused, the address says sign in again
    const off = asPerson(CHASE, "SELECT ottoq_account_disconnect(:'id'::uuid);", { id: me.connections[0].id });
    assert.equal(off.ok, true);
    const after = await mcp("tools/list", {}, ref.access_token);
    assert.equal(after.status, 401);
    assert.match(after.headers.get("www-authenticate"), /error="invalid_token"/);
    const again = await bodyOf(await gw("/oauth/token", { method: "POST", headers: FORM,
      raw: form({ grant_type: "refresh_token", client_id: reg.client_id, refresh_token: ref.refresh_token }) }));
    assert.equal(again.error, "invalid_grant");
    // and the ledger holds every sign-in call, never a raw secret
    const ledger = psql(DB, "SELECT string_agg(detail::text || coalesce(error_code, ''), ' ') FROM ottoq_agent_call_ledger WHERE transport IN ('oauth', 'web');").at(-1);
    for (const s of [dev.device_code, tok.body.access_token, tok.body.refresh_token, ref.refresh_token]) assert.ok(!ledger.includes(s));
  });
});
