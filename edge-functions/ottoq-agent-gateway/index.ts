// ottoq-agent-gateway: the one door outside agents (a founder's personal agent, a fleet operator's agent, a depot's
// own) use to read the OTTOYARD twin depot and to ASK for changes. db/migrations/0555, AGENT_GATEWAY.md.
//
//   agent --Bearer oqa_...--> this function --sha256(token)--> public.ottoq_agent_call (service_role only)
//                                                               |-- resolves the principal, rate-limits, checks the
//                                                               |   capability, runs the tool, writes the call ledger
//                                                               '-- reads only; "asks" land in ottoq_agent_requests
//   a person (OTTO-PULSE crew / OrchestrAV fleet owner) --> ottoq_agent_request_decide --> OTTO-Q's own door
//
// THIS FILE IS THE I/O SHELL ONLY. Routing, schemas, validation, MCP and the A2A card live in
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
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { GATEWAY_NAME, handleGatewayRequest, postgrestEngine } from "../_shared/agent_gateway.ts";

const SUPABASE_URL = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/+$/, "");
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const PUBLIC_URL = (Deno.env.get("AGENT_GATEWAY_PUBLIC_URL")
  ?? (SUPABASE_URL ? `${SUPABASE_URL}/functions/v1/${GATEWAY_NAME}` : `/${GATEWAY_NAME}`)).replace(/\/+$/, "");
const ALLOWED_ORIGINS = (Deno.env.get("AGENT_GATEWAY_ALLOWED_ORIGINS") ?? "")
  .split(",").map((s) => s.trim()).filter((s) => s.length > 0);

// Fail closed: without both variables there is no engine, and every authenticated path answers 500 not_configured.
const engine = SUPABASE_URL && SERVICE_KEY ? postgrestEngine({ supabaseUrl: SUPABASE_URL, serviceKey: SERVICE_KEY }) : null;

Deno.serve((req: Request) => handleGatewayRequest(req, { publicUrl: PUBLIC_URL, allowedOrigins: ALLOWED_ORIGINS, engine }));
