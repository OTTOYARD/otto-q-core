#!/usr/bin/env node
// scripts/agent-gateway-smoke.mjs -- the morning smoke test for the ottoq-agent-gateway (AGENT_GATEWAY.md, step 5).
//
//   GATEWAY_URL=https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-agent-gateway \
//   AGENT_TOKEN=oqa_... node scripts/agent-gateway-smoke.mjs [--no-note]
//
// Seven steps, each printed with what came back, stopping at the first failure (exit 1):
//   1. the public agent card            no token
//   2. a call with a wrong token        must be 401 -- proves the gateway authenticates at all
//   3. whoami                           who the token is and what it may do
//   4. depot status                     is a run live, and the sim clock
//   5. MCP: initialize + tools/list     the same door as an MCP client sees it
//   6. send a note (unless --no-note)   lands in the OTTO-PULSE agent inbox; changes nothing in the engine
//   7. read the note back               status pending until someone in PULSE acknowledges or dismisses it
//
// The token is read from the environment and never printed. The note carries an idempotency key per minute, so an
// accidental double run inside a minute replays the first note instead of sending two.
const BASE = (process.env.GATEWAY_URL ?? "").replace(/\/+$/, "");
const TOKEN = process.env.AGENT_TOKEN ?? "";
const SEND_NOTE = !process.argv.includes("--no-note");

if (!BASE || !TOKEN) {
  console.error("Set GATEWAY_URL (…/functions/v1/ottoq-agent-gateway) and AGENT_TOKEN (oqa_…).");
  process.exit(2);
}
if (!/^oqa_[0-9a-f]{64}$/.test(TOKEN)) {
  console.error("AGENT_TOKEN is not an agent token (expected oqa_ followed by 64 lowercase hex characters).");
  process.exit(2);
}

const ct = (d = new Date()) => d.toLocaleString("en-US", { timeZone: "America/Chicago", dateStyle: "medium", timeStyle: "short" }) + " CT";
let step = 0;

async function call(path, { method = "GET", token = TOKEN, body, headers = {} } = {}) {
  const started = Date.now();
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...(body ? { "Content-Type": "application/json" } : {}), ...headers },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(20_000),
  });
  const text = await res.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch { /* reported below */ }
  return { status: res.status, json, text, ms: Date.now() - started, headers: res.headers };
}

function check(label, ok, detail) {
  step += 1;
  console.log(`${ok ? "PASS" : "FAIL"}  ${step}. ${label}${detail ? ` -- ${detail}` : ""}`);
  if (!ok) process.exit(1);
}

console.log(`ottoq-agent-gateway smoke test, ${ct()} (${new Date().toISOString()} UTC)\n  ${BASE}\n`);

try {
  const card = await call("/.well-known/agent-card.json", { token: "" });
  check("agent card (public)", card.status === 200 && card.json?.name === "OTTO-Q Agent Gateway",
    `${card.status}, ${card.json?.skills?.length ?? 0} skills, ${card.ms} ms`);

  const stranger = await call("/v1/whoami", { token: "oqa_" + "0".repeat(64) });
  check("a wrong token is refused", stranger.status === 401 && stranger.json?.error?.code === "unauthenticated",
    `${stranger.status} ${stranger.json?.error?.code ?? stranger.text.slice(0, 80)}`);

  const who = await call("/v1/whoami");
  if (who.status === 503 && who.json?.error?.code === "gateway_not_enabled") {
    check("whoami", false, "the function is deployed but migration 0559 is not applied");
  }
  const me = who.json?.data;
  check("whoami", who.status === 200 && !!me?.principal?.name,
    `${me?.principal?.name} (${me?.principal?.kind}), sees ${me?.scope?.sees}; capabilities ${JSON.stringify(me?.capabilities)}`);

  const depot = await call("/v1/depot");
  const d = depot.json?.data;
  check("depot status", depot.status === 200,
    d?.live ? `run live, sim clock ${d?.run?.sim_clock} (SIMULATION time), tick ${d?.run?.tick}` : "no run is live right now (reads still work)");

  const init = await call("/mcp", {
    method: "POST",
    body: { jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "agent-gateway-smoke", version: "1" } } },
  });
  const list = await call("/mcp", {
    method: "POST",
    headers: { "MCP-Protocol-Version": "2025-06-18" },
    body: { jsonrpc: "2.0", id: 2, method: "tools/list" },
  });
  check("MCP initialize + tools/list", init.status === 200 && list.status === 200 && Array.isArray(list.json?.result?.tools),
    `protocol ${init.json?.result?.protocolVersion}; tools: ${(list.json?.result?.tools ?? []).map((t) => t.name).join(", ")}`);

  if (!SEND_NOTE) {
    console.log("\n--no-note: skipped steps 6-7. Done.");
    process.exit(0);
  }
  const minute = new Date().toISOString().slice(0, 16).replace(/[-:T]/g, "");
  const note = await call("/v1/notes", {
    method: "POST",
    headers: { "Idempotency-Key": `smoke-${minute}` },
    body: { title: "Agent gateway smoke test", body: `Sent by scripts/agent-gateway-smoke.mjs at ${ct()}. Acknowledge or dismiss it in OTTO-PULSE > OTTO-Q > Agents.`, priority: "low" },
  });
  const req = note.json?.data?.request;
  check("send a note", (note.status === 201 || note.status === 200) && !!req?.request_id,
    `${note.status === 200 ? "replayed" : "created"} request ${req?.request_id}, status ${req?.status}`);

  const back = await call(`/v1/requests/${req.request_id}`);
  const r = back.json?.data?.requests?.[0];
  check("read it back", back.status === 200 && r?.request_id === req.request_id,
    `status ${r?.status}${r?.decided_by ? `, decided by ${r.decided_by.kind}` : ", waiting for the crew"}; expires ${r?.expires_at} UTC`);

  console.log("\nAll steps passed. Open OTTO-PULSE > OTTO-Q > Agents to see the note, then run this again with --no-note");
  console.log("or GET /v1/requests to watch its status change once someone acknowledges it.");
} catch (e) {
  check("reach the gateway", false, `${e?.name ?? "error"}: ${e?.message ?? e}`);
}
