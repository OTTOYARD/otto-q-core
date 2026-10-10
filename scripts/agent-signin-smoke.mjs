#!/usr/bin/env node
// The live smoke test for OTTOYARD sign-in (0700, PERSONAL_AGENT.md section 10): an agent signs in by device code,
// exactly as Hermes does, and its owner approves it the way the sign-in page does. Nothing is changed but a
// connection made and closed again.
//
//   1. the signed-in MCP address answers 401 with a challenge naming the protected-resource metadata;
//   2. that metadata names OTTOYARD's authorization server, and the server's metadata at the issuer (www.ottoyard.com)
//      is exactly what the gateway serves at /oauth/metadata (the site and the gateway agree);
//   3. a smoke client registers, asks for a device code, and polls (pending);
//   4. the owner signs in to Supabase Auth and approves the code through the page's own doors;
//   5. the poll connects: an access token and a refresh token;
//   6. MCP with the access token: initialize, tools/list, whoami ("signed in", the owner's account);
//   7. the owner disconnects the smoke connection, and the token is refused (401 with the challenge).
//
// Usage (the password is read from the environment and never printed):
//   OWNER_PASSWORD=... OTTOQ_PUBLISHABLE_KEY=... node scripts/agent-signin-smoke.mjs
// Optional: GATEWAY_URL, SUPABASE_URL, OAUTH_ISSUER, OWNER_EMAIL, SKIP_SITE=1 (before the site is deployed).

const SUPABASE_URL = (process.env.SUPABASE_URL ?? "https://gxdrcyphqjzjsuhxuqtg.supabase.co").replace(/\/+$/, "");
const GATEWAY = (process.env.GATEWAY_URL ?? `${SUPABASE_URL}/functions/v1/ottoq-agent-gateway`).replace(/\/+$/, "");
const ISSUER = (process.env.OAUTH_ISSUER ?? "https://www.ottoyard.com").replace(/\/+$/, "");
const EMAIL = process.env.OWNER_EMAIL ?? "chase@ottoyard.com";
const PASSWORD = process.env.OWNER_PASSWORD;
const KEY = process.env.OTTOQ_PUBLISHABLE_KEY;
const DEVICE = "urn:ietf:params:oauth:grant-type:device_code";
if (!PASSWORD || !KEY) {
  console.error("Set OWNER_PASSWORD and OTTOQ_PUBLISHABLE_KEY (the project's publishable/anon key).");
  process.exit(2);
}

let failed = 0;
const ok = (name, cond, detail = "") => { console.log(`${cond ? "PASS" : "FAIL"}  ${name}${detail ? `  (${detail})` : ""}`); if (!cond) failed++; return cond; };
const json = async (res) => { const t = await res.text(); try { return t ? JSON.parse(t) : null; } catch { return { _text: t.slice(0, 200) }; } };
const form = (o) => ({ method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body: new URLSearchParams(o).toString() });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const same = (a, b) => JSON.stringify(a, Object.keys(a ?? {}).sort()) === JSON.stringify(b, Object.keys(b ?? {}).sort());

// 1-2. discovery, as an MCP client does it
const challenge = await fetch(`${GATEWAY}/account/mcp`);
const www = challenge.headers.get("www-authenticate") ?? "";
ok("the signed-in MCP address answers 401 with a challenge", challenge.status === 401 && /resource_metadata="/.test(www), `${challenge.status}`);
const prmUrl = /resource_metadata="([^"]+)"/.exec(www)?.[1];
const prm = prmUrl ? await json(await fetch(prmUrl)) : null;
ok("the protected-resource metadata names OTTOYARD's authorization server", prm?.authorization_servers?.[0] === ISSUER, prm?.authorization_servers?.[0] ?? "none");
const gwMeta = await json(await fetch(`${GATEWAY}/oauth/metadata`));
if (process.env.SKIP_SITE !== "1") {
  const siteRes = await fetch(`${ISSUER}/.well-known/oauth-authorization-server`, { redirect: "manual" });
  const siteMeta = siteRes.ok ? await json(siteRes) : null;
  ok("the issuer serves the authorization server's metadata (no redirect)", siteRes.status === 200, `${siteRes.status}`);
  ok("the site's metadata is exactly the gateway's", same(siteMeta, gwMeta));
}

// 3. a smoke client registers and asks for a device code
const reg = await json(await fetch(gwMeta.registration_endpoint, { method: "POST", headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ client_name: "OTTOYARD smoke test", grant_types: [DEVICE, "refresh_token"], response_types: [],
                         redirect_uris: ["http://127.0.0.1:8420/callback"], token_endpoint_auth_method: "none" }) }));
ok("registration", /^oqc_[0-9a-f]{32}$/.test(reg?.client_id ?? ""));
const dev = await json(await fetch(gwMeta.device_authorization_endpoint, form({ client_id: reg.client_id, resource: prm.resource })));
ok("device authorization", /^[A-Z]{4}-[A-Z]{4}$/.test(dev?.user_code ?? "") && dev?.verification_uri === `${ISSUER}/connect`,
   `${dev?.user_code} at ${dev?.verification_uri}`);
const poll = async () => json(await fetch(gwMeta.token_endpoint, form({ grant_type: DEVICE, client_id: reg.client_id, device_code: dev.device_code, resource: prm.resource })));
ok("a poll before approval is pending", (await poll())?.error === "authorization_pending");

// 4. the owner, as the sign-in page does it
const auth = await json(await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, { method: "POST",
  headers: { apikey: KEY, "Content-Type": "application/json" }, body: JSON.stringify({ email: EMAIL, password: PASSWORD }) }));
if (!ok("the owner signs in to OTTOYARD", typeof auth?.access_token === "string")) process.exit(1);
const door = async (fn, args = {}) => json(await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, { method: "POST",
  headers: { apikey: KEY, Authorization: `Bearer ${auth.access_token}`, "Content-Type": "application/json" }, body: JSON.stringify(args) }));
const look = await door("ottoq_oauth_device_lookup", { p_user_code: dev.user_code });
ok("the page shows which agent is asking", look?.ok && look.agent === "OTTOYARD smoke test", `${look?.agent ?? look?.message} for ${look?.fleet?.name}`);
const yes = await door("ottoq_oauth_device_decide", { p_user_code: dev.user_code, p_decision: "approve" });
ok("the owner approves", yes?.outcome === "approved");

// 5. the next poll connects
await sleep((dev.interval ?? 5) * 1000 + 500);
const tok = await poll();
ok("the poll after approval connects", /^oqt_[0-9a-f]{64}$/.test(tok?.access_token ?? "") && /^oqr_[0-9a-f]{64}$/.test(tok?.refresh_token ?? ""),
   tok?.error ?? `expires_in ${tok?.expires_in}`);

// 6. MCP with the access token
const mcp = async (method, params, id) => fetch(`${GATEWAY}/account/mcp`, { method: "POST",
  headers: { Authorization: `Bearer ${tok.access_token}`, "Content-Type": "application/json", Accept: "application/json, text/event-stream",
             "mcp-protocol-version": "2025-06-18" },
  body: JSON.stringify({ jsonrpc: "2.0", id, method, params }) });
const init = await json(await mcp("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "ottoyard-smoke", version: "1" } }, 1));
ok("MCP initialize", init?.result?.serverInfo?.name === "ottoq-agent-gateway");
const list = await json(await mcp("tools/list", {}, 2));
const names = (list?.result?.tools ?? []).map((t) => t.name);
ok("MCP tools/list has the owner's tools", names.includes("my_fleet") && names.includes("set_charge_limit"), `${names.length} tools`);
const who = await json(await mcp("tools/call", { name: "whoami", arguments: {} }, 3));
const p = who?.result?.structuredContent?.principal ?? {};
ok("whoami: signed in, to the owner's account", p.via === "signed in" && p.account === EMAIL.toLowerCase(), `${p.via} / ${p.account}`);

// 7. the owner disconnects the smoke connection
const me = await door("ottoq_account_me");
const conn = (me?.connections ?? []).find((c) => c.agent === "OTTOYARD smoke test" && c.state === "connected");
const off = conn ? await door("ottoq_account_disconnect", { p_connection_id: conn.id }) : null;
ok("the owner disconnects it", off?.ok === true);
const after = await mcp("tools/list", {}, 4);
ok("its token is refused, with the challenge", after.status === 401 && /error="invalid_token"/.test(after.headers.get("www-authenticate") ?? ""));

console.log(failed === 0 ? "\nALL PASSED" : `\n${failed} FAILED`);
process.exit(failed === 0 ? 0 : 1);
