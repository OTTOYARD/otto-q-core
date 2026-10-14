// ottoq-agent-gateway: the one door outside agents (a founder's personal agent, a fleet operator's agent, a depot's
// own) use to read the OTTOYARD twin depot and to ASK for changes. db/migrations/0559, AGENT_GATEWAY.md.
//
//   agent --Bearer oqa_...--> this function --sha256(token)--> public.ottoq_agent_call (service_role only)
//                                                               |-- resolves the principal, rate-limits, checks the
//                                                               |   capability, runs the tool, writes the call ledger
//                                                               '-- reads only; "asks" land in ottoq_agent_requests
//   a person (OTTO-PULSE crew / OrchestrAV fleet owner) --> ottoq_agent_request_decide --> OTTO-Q's own door
//
// An OWNER's agent (0605, PERSONAL_AGENT.md) can also set what its own cars need -- a charge limit inside its contract,
// a service, a hold, an undo -- and the engine applies it at its next tick. POST /v1/ask is that same door in plain
// English: OTTO-Command (../_shared/ottocommand_owner.ts) reads the owner's words and calls the same tools through the
// same engine call, with the owner's own token, so it can do nothing the token could not. 0721: the same door is the
// MCP tool ask_ottocommand (every token bound to a fleet), answered by the same handler, ledgered as transport 'ask'.
// 0721 (Chase 2026-10-14, 12:35 PM CT: "Search should cover OTTO-Q and web. It can be ask and tools as well."): the
// door also answers POST /v1/search and the MCP tool ottocommand_search (read-only: reads and the web, never a
// command), may search the web (untrusted: an ask that read it changes nothing), and records every model call in
// public.ottoq_model_call_ledger through ottoq_ottocommand_record_model_call, fire-and-forget.
//
// THIS FILE IS THE I/O SHELL ONLY. Routing, schemas, validation, MCP, OpenAPI and the A2A card live in
// ../_shared/agent_gateway.ts, which tests/agent_gateway.test.mjs imports directly. Scope, rate limits and the
// ledger live in the database, so nothing here can widen what a token may see or do.
//
// DEPLOY WITH JWT VERIFICATION OFF. Agent tokens are not Supabase JWTs, so the platform check would refuse every
// agent before this code runs (https://supabase.com/docs/guides/functions/auth-headers, read 2026-09-28):
//   supabase functions deploy ottoq-agent-gateway --project-ref gxdrcyphqjzjsuhxuqtg --no-verify-jwt
// The Bearer token IS the authentication: a missing or malformed one is refused here, an unknown or revoked one by
// the database, and every call that presents a well-formed token is ledgered, refusals included.
//
// Environment: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (injected by the platform). Optional:
//   AGENT_GATEWAY_PUBLIC_URL       the base URL advertised in the agent card (default: SUPABASE_URL/functions/v1/<name>)
//   AGENT_GATEWAY_ALLOWED_ORIGINS  comma-separated browser origins; unset = no browser may call it (agents are servers)
//   ANTHROPIC_API_KEY              the key OTTO-Command already uses; without it, POST /v1/ask and /v1/search answer
//                                  503 to a plain-English ask (a previewed plan's confirm still applies: it needs no model)
//   OTTOCOMMAND_OWNER_MODEL        0721: the model the owner door uses. Unset: the door's default model
//                                  (DEFAULT_OWNER_MODEL in ../_shared/ottocommand_owner.ts). ANTHROPIC_MODEL, the cockpit
//                                  seat's own setting, is no longer read here.
//   OTTOCOMMAND_EFFORT             0721: low (the default) | medium | high | xhigh | max. Low, because the whole ask must
//                                  end inside Hermes's 60-second MCP timeout.
//   OTTOCOMMAND_WEB_SEARCH         0721: on (the default) | off. Off: no web search in any ask or search.
//   OTTOCOMMAND_WEB_MAX_USES       0721: web searches per ask, default 3, clamped to 1..5.
//                                  A value the door cannot read makes a plain-English ask answer 503 ask_misconfigured,
//                                  naming the variable; confirms still apply.
//   AGENT_GATEWAY_OAUTH_ISSUER     0700: OTTOYARD's authorization server, where its RFC 8414 metadata is published
//                                  (default https://www.ottoyard.com, served by the OTTOYARD-SITE repository)
//   AGENT_GATEWAY_SIGNIN_URL       0700: the page a person signs in and approves an agent on
//                                  (default https://www.ottoyard.com/connect)
//
// 0700: an owner's own agent can also SIGN IN (OAuth 2.1: the device code grant, or a browser with PKCE) and use the
// signed-in MCP address, /account/mcp, with an access token; ../_shared/agent_signin.ts and PERSONAL_AGENT.md section 10.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { GATEWAY_NAME, handleGatewayRequest, postgrestEngine, postgrestModelLedger } from "../_shared/agent_gateway.ts";
import { postgrestOAuth, SIGNIN_ISSUER_DEFAULT, SIGNIN_PAGE_DEFAULT } from "../_shared/agent_signin.ts";
import { anthropicModel, ownerAskConfig, ownerAskHandler } from "../_shared/ottocommand_owner.ts";

const SUPABASE_URL = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/+$/, "");
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const PUBLIC_URL = (Deno.env.get("AGENT_GATEWAY_PUBLIC_URL")
  ?? (SUPABASE_URL ? `${SUPABASE_URL}/functions/v1/${GATEWAY_NAME}` : `/${GATEWAY_NAME}`)).replace(/\/+$/, "");
const ALLOWED_ORIGINS = (Deno.env.get("AGENT_GATEWAY_ALLOWED_ORIGINS") ?? "")
  .split(",").map((s) => s.trim()).filter((s) => s.length > 0);

// Fail closed: without both variables there is no engine, and every authenticated path answers 500 not_configured.
const engine = SUPABASE_URL && SERVICE_KEY ? postgrestEngine({ supabaseUrl: SUPABASE_URL, serviceKey: SERVICE_KEY }) : null;

// 0700: OTTOYARD sign-in. The issuer and the sign-in page are public addresses, not secrets.
const signin = {
  config: {
    publicUrl: PUBLIC_URL,
    issuer: (Deno.env.get("AGENT_GATEWAY_OAUTH_ISSUER") ?? SIGNIN_ISSUER_DEFAULT).replace(/\/+$/, ""),
    signinPage: Deno.env.get("AGENT_GATEWAY_SIGNIN_URL") ?? SIGNIN_PAGE_DEFAULT,
  },
  rpc: SUPABASE_URL && SERVICE_KEY ? postgrestOAuth({ supabaseUrl: SUPABASE_URL, serviceKey: SERVICE_KEY }) : null,
};

// The owner door's model (0721): OTTOCOMMAND_OWNER_MODEL, or the door's default; its effort and web search from the
// environment, validated (ownerAskConfig). Every model call is recorded in the evidence ledger, fire-and-forget; the
// platform keeps the isolate alive for the write (EdgeRuntime.waitUntil) where it can.
const ANTHROPIC_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const CONFIG = ownerAskConfig((name) => Deno.env.get(name));
if (!CONFIG.ok) console.error(`${GATEWAY_NAME}: OTTO-Command is misconfigured: ${CONFIG.errors.join("; ")}`);
const runtime = (globalThis as { EdgeRuntime?: { waitUntil?: (p: Promise<unknown>) => void } }).EdgeRuntime;
const ask = ownerAskHandler({
  model: ANTHROPIC_KEY ? anthropicModel({ apiKey: ANTHROPIC_KEY, model: CONFIG.value.model, effort: CONFIG.value.effort }) : null,
  modelName: CONFIG.value.model,
  effort: CONFIG.value.effort,
  web: CONFIG.value.web,
  ledger: SUPABASE_URL && SERVICE_KEY ? postgrestModelLedger({ supabaseUrl: SUPABASE_URL, serviceKey: SERVICE_KEY }) : null,
  defer: typeof runtime?.waitUntil === "function" ? (p) => runtime.waitUntil?.(p) : undefined,
  configError: CONFIG.ok ? undefined : `OTTO-Command is misconfigured, so it answers no plain-English ask: ${CONFIG.errors.join("; ")}. Every tool works directly over MCP and REST.`,
});

Deno.serve((req: Request) => handleGatewayRequest(req, { publicUrl: PUBLIC_URL, allowedOrigins: ALLOWED_ORIGINS, engine, ask, signin }));
