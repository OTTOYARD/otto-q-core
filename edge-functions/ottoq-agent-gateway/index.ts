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
// same engine call, with the owner's own token, so it can do nothing the token could not.
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
//   ANTHROPIC_API_KEY              the key OTTO-Command already uses; without it, POST /v1/ask answers 503 to a
//                                  plain-English ask (a previewed plan's confirm still applies: it needs no model)
//   OTTOCOMMAND_OWNER_MODEL        the model the owner door uses; falls back to ANTHROPIC_MODEL (OTTO-Command's own
//                                  setting). With neither set, a plain-English ask answers 503 ask_not_configured.
//   AGENT_GATEWAY_OAUTH_ISSUER     0660: OTTOYARD's authorization server, where its RFC 8414 metadata is published
//                                  (default https://www.ottoyard.com, served by the OTTOYARD-SITE repository)
//   AGENT_GATEWAY_SIGNIN_URL       0660: the page a person signs in and approves an agent on
//                                  (default https://www.ottoyard.com/connect)
//
// 0660: an owner's own agent can also SIGN IN (OAuth 2.1: the device code grant, or a browser with PKCE) and use the
// signed-in MCP address, /account/mcp, with an access token; ../_shared/agent_signin.ts and PERSONAL_AGENT.md section 10.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { GATEWAY_NAME, handleGatewayRequest, postgrestEngine } from "../_shared/agent_gateway.ts";
import { postgrestOAuth, SIGNIN_ISSUER_DEFAULT, SIGNIN_PAGE_DEFAULT } from "../_shared/agent_signin.ts";
import { anthropicModel, ownerAskHandler } from "../_shared/ottocommand_owner.ts";

const SUPABASE_URL = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/+$/, "");
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const PUBLIC_URL = (Deno.env.get("AGENT_GATEWAY_PUBLIC_URL")
  ?? (SUPABASE_URL ? `${SUPABASE_URL}/functions/v1/${GATEWAY_NAME}` : `/${GATEWAY_NAME}`)).replace(/\/+$/, "");
const ALLOWED_ORIGINS = (Deno.env.get("AGENT_GATEWAY_ALLOWED_ORIGINS") ?? "")
  .split(",").map((s) => s.trim()).filter((s) => s.length > 0);

// Fail closed: without both variables there is no engine, and every authenticated path answers 500 not_configured.
const engine = SUPABASE_URL && SERVICE_KEY ? postgrestEngine({ supabaseUrl: SUPABASE_URL, serviceKey: SERVICE_KEY }) : null;

// 0660: OTTOYARD sign-in. The issuer and the sign-in page are public addresses, not secrets.
const signin = {
  config: {
    publicUrl: PUBLIC_URL,
    issuer: (Deno.env.get("AGENT_GATEWAY_OAUTH_ISSUER") ?? SIGNIN_ISSUER_DEFAULT).replace(/\/+$/, ""),
    signinPage: Deno.env.get("AGENT_GATEWAY_SIGNIN_URL") ?? SIGNIN_PAGE_DEFAULT,
  },
  rpc: SUPABASE_URL && SERVICE_KEY ? postgrestOAuth({ supabaseUrl: SUPABASE_URL, serviceKey: SERVICE_KEY }) : null,
};

// The owner door's model. Its name is the deployment's choice, never a constant in this repository.
const ANTHROPIC_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const OWNER_MODEL = (Deno.env.get("OTTOCOMMAND_OWNER_MODEL") ?? Deno.env.get("ANTHROPIC_MODEL") ?? "").trim();
const ask = ownerAskHandler({
  model: ANTHROPIC_KEY && OWNER_MODEL ? anthropicModel({ apiKey: ANTHROPIC_KEY, model: OWNER_MODEL }) : null,
  modelName: OWNER_MODEL || undefined,
});

Deno.serve((req: Request) => handleGatewayRequest(req, { publicUrl: PUBLIC_URL, allowedOrigins: ALLOWED_ORIGINS, engine, ask, signin }));
