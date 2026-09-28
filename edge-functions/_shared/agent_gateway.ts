/**
 * The ottoq-agent-gateway's pure half (db/migrations/0550, AGENT_GATEWAY.md).
 *
 * Pure functions only -- no Deno, no network, no database -- so `node --test tests/*.test.mjs` imports this file
 * directly, exactly as it imports agent_dial_discipline.ts. The edge function (ottoq-agent-gateway/index.ts) is the
 * thin I/O shell around it.
 *
 * WHAT LIVES WHERE, and why the split is the security model:
 *   * the DATABASE decides who the caller is, what it may see and whether it may ask (public.ottoq_agent_call:
 *     token hash -> active principal -> rate limit -> capability -> tool -> call ledger). A guardrail in this file
 *     would be bypassed by anything that did not go through this file.
 *   * THIS FILE decides only the shape of the conversation: which HTTP paths and MCP methods exist, what a well-formed
 *     argument is (so an agent gets a precise error before the database is asked), and how an engine reply is
 *     rendered for REST, MCP or A2A discovery. It never widens scope: every tool schema rejects unknown properties,
 *     so a client cannot smuggle a fleet_operator_id, depot_id or principal into a call.
 *
 * Specs this implements, read 2026-09-28:
 *   MCP 2026-07-28 (stateless core; initialize retired; Mcp-Method / Mcp-Name mirrored headers; -32020 HeaderMismatch;
 *     -32022 UnsupportedProtocolVersion; 404 for an unknown method; 405 for GET/DELETE; 202 for a notification):
 *     https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http
 *     https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning
 *     https://modelcontextprotocol.io/specification/2026-07-28/server/tools
 *     https://modelcontextprotocol.io/specification/2026-07-28/server/utilities/caching
 *     https://modelcontextprotocol.io/specification/2026-07-28/server/discover
 *   and the initialize-based revisions for older clients (2025-11-25, 2025-06-18, 2025-03-26), which a dual-era server
 *   MAY serve on the same endpoint (versioning page, "Backward Compatibility with Initialization-Based Versions").
 *   A2A 1.0.0 Agent Card (supportedInterfaces, securitySchemes/securityRequirements, skills; /.well-known/agent-card.json):
 *     https://a2a-protocol.org/latest/specification/  (section 8; sample card 8.5)
 */

import { INERT_OPS } from "./agent_dial_discipline.ts";

export const GATEWAY_NAME = "ottoq-agent-gateway";
export const GATEWAY_TITLE = "OTTO-Q Agent Gateway";
export const GATEWAY_VERSION = "1.0.0";
export const TWIN_DEPOT_ID = "11111111-1111-1111-1111-111111111111";
/** The ONLY database function the gateway calls. Everything else is the database's business. */
export const ENGINE_RPC = "ottoq_agent_call";
/** 'oqa_' + 64 lowercase hex characters, as ottoq_agent_issue_token mints them. Anything else is refused before the database. */
export const TOKEN_PATTERN = /^oqa_[0-9a-f]{64}$/;
export const MAX_BODY_BYTES = 64 * 1024;

export const CAPABILITIES = ["read", "note", "request_recall", "request_ops_action", "request_adjustment"] as const;
export type Capability = (typeof CAPABILITIES)[number];

/** ottoq_apply_ops_action's whitelist, action -> the dial it sets. The database (0550's submit function) is the
 *  authority and refuses the two whose dial is not agent_writable; this copy only shapes the schema. */
export const OPS_ACTIONS = {
  raise_deploy_surge: "deploy_surge_catchup",
  extend_forecast_horizon: "forecast_horizon_min",
  enable_energy_reserve: "energy_reserve_shave",
} as const;

/** The ops actions an agent may ASK for: the whitelist minus the ones whose dial nothing reads (G175, INERT_OPS).
 *  Offering an agent an action the database will always refuse is a placebo, so the schema does not. */
export const ASKABLE_OPS_ACTIONS: readonly string[] = Object.keys(OPS_ACTIONS).filter((a) => !(a in INERT_OPS));

export const REQUEST_KIND_CAPABILITY = {
  recall_vehicle: "request_recall",
  ops_action: "request_ops_action",
  adjustment: "request_adjustment",
} as const;
export type RequestKind = keyof typeof REQUEST_KIND_CAPABILITY;

export const STALL_TYPES = ["dcfc", "l2", "wash_bay", "detail_bay", "service_bay", "staging", "parking", "safety"] as const;
export const VEHICLE_STATES = [
  "offline", "deployed", "en_route_to_depot", "arrived_at_gate", "staged_awaiting_service", "charging_dcfc",
  "charging_l2", "charge_complete_holding", "in_wash_bay", "in_detail_bay", "in_service_bay",
  "service_complete_holding", "staged_for_departure", "en_route_to_deployment", "emergency_staged", "tow_requested",
  "out_of_service",
] as const;
export const REQUEST_STATUSES = [
  "pending", "declined", "expired", "acknowledged", "applied", "refused_by_engine", "approved_no_engine_door",
  "approved_not_applied", "apply_failed",
] as const;
export const PRIORITIES = ["low", "normal", "high", "urgent"] as const;

// ─────────────────────────────────────────────────────────────────────────────────────────────── schemas ──

export type JsonSchema = {
  type?: string | string[];
  description?: string;
  enum?: readonly (string | number | boolean)[];
  minLength?: number;
  maxLength?: number;
  pattern?: string;
  minimum?: number;
  maximum?: number;
  format?: "uuid";
  properties?: Record<string, JsonSchema>;
  required?: readonly string[];
  additionalProperties?: boolean;
};

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const uuidProp = (description: string): JsonSchema => ({ type: "string", format: "uuid", description });
const TITLE: JsonSchema = { type: "string", minLength: 1, maxLength: 140, description: "One line a person reads first (1-140 characters)." };
const BODY: JsonSchema = { type: "string", maxLength: 4000, description: "Optional detail, at most 4000 characters." };
const PRIORITY: JsonSchema = { type: "string", enum: PRIORITIES, description: "low | normal (default) | high | urgent." };
const IDEMPOTENCY: JsonSchema = {
  type: "string", pattern: "^[A-Za-z0-9._:-]{1,100}$",
  description: "Optional. Resending with the same key returns the first request instead of asking twice.",
};
const EMPTY: JsonSchema = { type: "object", properties: {}, additionalProperties: false };

export type ToolAnnotations = {
  readOnlyHint: boolean;
  destructiveHint: boolean;
  idempotentHint: boolean;
  openWorldHint: boolean;
};

export type ToolDef = {
  name: string;
  title: string;
  description: string;
  /** null = any active token; 'any_request' = at least one request_* capability (checked per kind by the database). */
  capability: Capability | "any_request" | null;
  /** What the tool can change: nothing, or the agent's own request ledger. Never world state. */
  effect: "read" | "ledger_write";
  inputSchema: JsonSchema;
  annotations: ToolAnnotations;
  rest: { method: "GET" | "POST"; path: string };
  tags: readonly string[];
  examples: readonly string[];
};

const READ: ToolAnnotations = { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false };
const ASK: ToolAnnotations = { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false };

export const TOOLS: readonly ToolDef[] = [
  {
    name: "whoami",
    title: "Who am I",
    description: "Your principal: kind, the depot and fleet you are scoped to, your capabilities and limits, and how a change you ask for gets decided.",
    capability: null, effect: "read", inputSchema: EMPTY, annotations: READ,
    rest: { method: "GET", path: "/v1/whoami" }, tags: ["identity"], examples: ["Who am I and what may I do?"],
  },
  {
    name: "depot_status",
    title: "Depot status",
    description: "Whether a run is live at your depot, its sim clock, tick, scenario and seed (ottoq_twin_run_context), and your vehicles by state. sim_clock is SIMULATION time.",
    capability: "read", effect: "read", inputSchema: EMPTY, annotations: READ,
    rest: { method: "GET", path: "/v1/depot" }, tags: ["depot", "run"], examples: ["Is a run live, and what time is it on the sim clock?"],
  },
  {
    name: "fleet_summary",
    title: "Fleet summary",
    description: "Your vehicles at the depot from the cockpits' own card feed (ottoq_depot_cards): state, SoC, stall, current and next step, open needs and the last OTTO-Q decision. A fleet-scoped token sees only its fleet.",
    capability: "read", effect: "read",
    inputSchema: {
      type: "object", additionalProperties: false,
      properties: {
        state: { type: "string", enum: VEHICLE_STATES, description: "Only vehicles in this state." },
        limit: { type: "integer", minimum: 1, maximum: 500, description: "At most this many vehicles (default 200)." },
      },
    },
    annotations: READ, rest: { method: "GET", path: "/v1/fleet" }, tags: ["fleet", "vehicles"],
    examples: ["Which of my vehicles are charging?", "{\"state\": \"staged_awaiting_service\"}"],
  },
  {
    name: "vehicle_card",
    title: "Vehicle card",
    description: "One vehicle's full work-order card (ottoq_vehicle_card). A vehicle outside your scope reads exactly like one that does not exist.",
    capability: "read", effect: "read",
    inputSchema: {
      type: "object", additionalProperties: false, required: ["vehicle_id"],
      properties: { vehicle_id: uuidProp("The vehicle's id, as fleet_summary gives it.") },
    },
    annotations: READ, rest: { method: "GET", path: "/v1/vehicles/{vehicle_id}" }, tags: ["vehicles"],
    examples: ["{\"vehicle_id\": \"<uuid from fleet_summary>\"}"],
  },
  {
    name: "recent_decisions",
    title: "Recent OTTO-Q decisions",
    description: "OTTO-Q's latest decisions on the live run (the cockpits' decision stream), filtered to your vehicles when you are fleet-scoped. at_sim is SIMULATION time.",
    capability: "read", effect: "read",
    inputSchema: {
      type: "object", additionalProperties: false,
      properties: {
        vehicle_id: uuidProp("Only this vehicle's decisions."),
        limit: { type: "integer", minimum: 1, maximum: 100, description: "At most this many (default 25)." },
      },
    },
    annotations: READ, rest: { method: "GET", path: "/v1/decisions" }, tags: ["decisions"],
    examples: ["What did OTTO-Q decide in the last few minutes?"],
  },
  {
    name: "stall_availability",
    title: "Stall availability (three gates)",
    description: "Stalls a vehicle could be offered now: the intersection of three gates -- the stall pointer is clear, the stall calendar is clear for the window on the run's SIM clock, and (dcfc, l2) the charger is not Faulted. Counts per gate are returned so no single gate is mistaken for availability.",
    capability: "read", effect: "read",
    inputSchema: {
      type: "object", additionalProperties: false,
      properties: {
        stall_type: { type: "string", enum: STALL_TYPES, description: "Only this stall type." },
        horizon_min: { type: "integer", minimum: 5, maximum: 240, description: "Window length in sim minutes (default 30)." },
      },
    },
    annotations: READ, rest: { method: "GET", path: "/v1/stalls" }, tags: ["stalls", "capacity"],
    examples: ["Is a fast charger free for the next 30 minutes?", "{\"stall_type\": \"dcfc\"}"],
  },
  {
    name: "list_requests",
    title: "My requests",
    description: "Your own notes and requests, newest first, with each one's status, the person's decision and note, and the engine's exact reply. applied means the engine door accepted it; refused_by_engine means it did not; approved_no_engine_door means OTTO-Q has no door for it and nothing changed.",
    capability: null, effect: "read",
    inputSchema: {
      type: "object", additionalProperties: false,
      properties: {
        status: { type: "string", enum: REQUEST_STATUSES, description: "Only requests in this status." },
        request_id: uuidProp("Just this request."),
        limit: { type: "integer", minimum: 1, maximum: 100, description: "At most this many (default 20)." },
      },
    },
    annotations: READ, rest: { method: "GET", path: "/v1/requests" }, tags: ["requests"],
    examples: ["Was my recall approved?", "{\"status\": \"pending\"}"],
  },
  {
    name: "send_note",
    title: "Send a note to the depot crew",
    description: "Delivers a note to the depot crew's agent inbox in OTTO-PULSE (and to the fleet owner's panel in OrchestrAV when it names one of their vehicles). A note changes nothing in the engine; the crew acknowledges or dismisses it.",
    capability: "note", effect: "ledger_write",
    inputSchema: {
      type: "object", additionalProperties: false, required: ["title"],
      properties: {
        title: TITLE, body: BODY, priority: PRIORITY, idempotency_key: IDEMPOTENCY,
        vehicle_id: uuidProp("Optional: the vehicle the note is about (must be in your scope)."),
        ttl_minutes: { type: "integer", minimum: 5, maximum: 10080, description: "How long it stays open (default 1440 = 24 h)." },
      },
    },
    annotations: ASK, rest: { method: "POST", path: "/v1/notes" }, tags: ["notes", "crew"],
    examples: ["{\"title\": \"Tire pressure warning on Waymo-AV-012\", \"priority\": \"high\"}"],
  },
  {
    name: "submit_request",
    title: "Ask for a change",
    description: `Asks for a change. A person approves or declines it; on approval it goes to OTTO-Q's own door and the engine may still refuse. kind=recall_vehicle (needs vehicle_id; the recall door), kind=ops_action (needs action: ${ASKABLE_OPS_ACTIONS.join(" or ")}; depot-wide, applies to the live run), kind=adjustment (needs adjustment, a short snake_case name such as charge_target; OTTO-Q has no door for these yet, so an approval is recorded and nothing in the engine changes). Nothing happens on your say-so alone.`,
    capability: "any_request", effect: "ledger_write",
    inputSchema: {
      type: "object", additionalProperties: false, required: ["kind", "title"],
      properties: {
        kind: { type: "string", enum: ["recall_vehicle", "ops_action", "adjustment"], description: "What you are asking for." },
        title: TITLE, body: BODY, priority: PRIORITY, idempotency_key: IDEMPOTENCY,
        vehicle_id: uuidProp("recall_vehicle: required. adjustment: optional. ops_action: not allowed."),
        action: { type: "string", enum: ASKABLE_OPS_ACTIONS, description: "ops_action only: which action. Only actions whose dial is agent-writable are offered." },
        args: {
          type: "object", additionalProperties: false, description: "ops_action only, optional.",
          properties: { value: { type: "number", description: "A requested value where the action takes one." } },
        },
        adjustment: { type: "string", pattern: "^[a-z][a-z0-9_]{1,48}$", description: "adjustment only: what you want changed, e.g. charge_target, hold_until." },
        value: { type: ["number", "string", "boolean"], description: "adjustment only, optional: the value you want (text at most 200 characters)." },
        ttl_minutes: { type: "integer", minimum: 5, maximum: 10080, description: "How long it waits for a decision (default 120)." },
      },
    },
    annotations: ASK, rest: { method: "POST", path: "/v1/requests" }, tags: ["requests", "recall", "ops"],
    examples: [
      "{\"kind\": \"recall_vehicle\", \"title\": \"Bring Waymo-AV-012 home: tire warning\", \"vehicle_id\": \"<uuid>\"}",
      "{\"kind\": \"ops_action\", \"title\": \"Peak coming: turn on the energy reserve\", \"action\": \"enable_energy_reserve\"}",
      "{\"kind\": \"adjustment\", \"title\": \"Cap Waymo-AV-012 at 90% tonight\", \"vehicle_id\": \"<uuid>\", \"adjustment\": \"charge_target\", \"value\": 90}",
    ],
  },
];

export function findTool(name: unknown): ToolDef | undefined {
  return typeof name === "string" ? TOOLS.find((t) => t.name === name) : undefined;
}

/** The request kinds a set of capabilities allows. */
export function allowedKinds(capabilities: readonly string[]): RequestKind[] {
  return (Object.keys(REQUEST_KIND_CAPABILITY) as RequestKind[]).filter((k) => capabilities.includes(REQUEST_KIND_CAPABILITY[k]));
}

/** The tools a principal can use, with submit_request's `kind` narrowed to the kinds it may ask for. */
export function toolsFor(capabilities: readonly string[]): ToolDef[] {
  const out: ToolDef[] = [];
  for (const t of TOOLS) {
    if (t.capability === null || (t.capability !== "any_request" && capabilities.includes(t.capability))) {
      out.push(t);
    } else if (t.capability === "any_request") {
      const kinds = allowedKinds(capabilities);
      if (kinds.length === 0) continue;
      const props = { ...(t.inputSchema.properties ?? {}), kind: { ...(t.inputSchema.properties?.kind ?? {}), enum: kinds } };
      out.push({ ...t, inputSchema: { ...t.inputSchema, properties: props } });
    }
  }
  return out;
}

// ───────────────────────────────────────────────────────────────────────────────────────────── validation ──

export type ValidationError = { path: string; message: string };
export type Validated = { ok: true; value: Record<string, unknown> } | { ok: false; errors: ValidationError[] };

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);

function typeOk(t: string, v: unknown): boolean {
  switch (t) {
    case "string": return typeof v === "string";
    case "integer": return typeof v === "number" && Number.isInteger(v);
    case "number": return typeof v === "number" && Number.isFinite(v);
    case "boolean": return typeof v === "boolean";
    case "object": return isObject(v);
    case "array": return Array.isArray(v);
    case "null": return v === null;
    default: return false;
  }
}

/** The subset of JSON Schema the tool schemas use. Unknown keywords are ignored, never trusted. */
export function validateAgainst(schema: JsonSchema, value: unknown, path = "$"): ValidationError[] {
  const errs: ValidationError[] = [];
  if (schema.type !== undefined) {
    const types = Array.isArray(schema.type) ? schema.type : [schema.type];
    if (!types.some((t) => typeOk(t, value))) {
      return [{ path, message: `must be ${types.join(" or ")}` }];
    }
  }
  if (schema.enum !== undefined && !schema.enum.includes(value as string | number | boolean)) {
    errs.push({ path, message: `must be one of ${schema.enum.join(", ")}` });
  }
  if (typeof value === "string") {
    if (schema.minLength !== undefined && [...value].length < schema.minLength) errs.push({ path, message: `must be at least ${schema.minLength} characters` });
    if (schema.maxLength !== undefined && [...value].length > schema.maxLength) errs.push({ path, message: `must be at most ${schema.maxLength} characters` });
    if (schema.pattern !== undefined && !new RegExp(schema.pattern).test(value)) errs.push({ path, message: `must match ${schema.pattern}` });
    if (schema.format === "uuid" && !UUID_RE.test(value)) errs.push({ path, message: "must be a UUID" });
  }
  if (typeof value === "number") {
    if (schema.minimum !== undefined && value < schema.minimum) errs.push({ path, message: `must be at least ${schema.minimum}` });
    if (schema.maximum !== undefined && value > schema.maximum) errs.push({ path, message: `must be at most ${schema.maximum}` });
  }
  if (isObject(value) && (schema.properties || schema.required || schema.additionalProperties === false)) {
    for (const key of schema.required ?? []) {
      if (value[key] === undefined || value[key] === null) errs.push({ path: `${path}.${key}`, message: "is required" });
    }
    for (const [key, v] of Object.entries(value)) {
      const sub = schema.properties?.[key];
      if (!sub) {
        if (schema.additionalProperties === false) errs.push({ path: `${path}.${key}`, message: "is not a known argument" });
        continue;
      }
      if (v === undefined || v === null) continue;
      errs.push(...validateAgainst(sub, v, `${path}.${key}`));
    }
  }
  return errs;
}

/** Validate a tool's arguments: its schema, then the cross-field rules the database also enforces. */
export function validateToolArgs(tool: ToolDef, args: unknown): Validated {
  const value = args === undefined || args === null ? {} : args;
  if (!isObject(value)) return { ok: false, errors: [{ path: "$", message: "arguments must be a JSON object" }] };
  const errors = validateAgainst(tool.inputSchema, value);
  if (tool.name === "submit_request" && errors.length === 0) {
    const kind = value.kind as RequestKind;
    if (kind === "recall_vehicle" && !value.vehicle_id) errors.push({ path: "$.vehicle_id", message: "is required for recall_vehicle" });
    if (kind === "ops_action" && !value.action) errors.push({ path: "$.action", message: "is required for ops_action" });
    if (kind === "ops_action" && value.vehicle_id) errors.push({ path: "$.vehicle_id", message: "is not allowed for ops_action (it is depot-wide)" });
    if (kind === "adjustment" && !value.adjustment) errors.push({ path: "$.adjustment", message: "is required for adjustment" });
    if (kind !== "ops_action" && (value.action !== undefined || value.args !== undefined)) errors.push({ path: "$.action", message: "is only for ops_action" });
    if (kind !== "adjustment" && (value.adjustment !== undefined || value.value !== undefined)) errors.push({ path: "$.adjustment", message: "is only for adjustment" });
    if (typeof value.value === "string" && [...value.value].length > 200) errors.push({ path: "$.value", message: "must be at most 200 characters" });
  }
  return errors.length ? { ok: false, errors } : { ok: true, value };
}

/** REST query strings are text; coerce each parameter to its schema type, refusing unknown parameters. */
export function argsFromQuery(tool: ToolDef, query: URLSearchParams): Validated {
  const out: Record<string, unknown> = {};
  const errors: ValidationError[] = [];
  for (const [key, raw] of query.entries()) {
    if (raw === "") continue;
    const sub = tool.inputSchema.properties?.[key];
    if (!sub) { errors.push({ path: `$.${key}`, message: "is not a known parameter" }); continue; }
    const t = Array.isArray(sub.type) ? sub.type[0] : sub.type;
    if (t === "integer") {
      if (!/^-?[0-9]{1,9}$/.test(raw)) { errors.push({ path: `$.${key}`, message: "must be a whole number" }); continue; }
      out[key] = Number(raw);
    } else if (t === "boolean") {
      if (raw !== "true" && raw !== "false") { errors.push({ path: `$.${key}`, message: "must be true or false" }); continue; }
      out[key] = raw === "true";
    } else {
      out[key] = raw;
    }
  }
  return errors.length ? { ok: false, errors } : { ok: true, value: out };
}

// ─────────────────────────────────────────────────────────────────────────────────────── http plumbing ──

/** The function's path with the Supabase prefix removed: '/functions/v1/ottoq-agent-gateway/v1/fleet' -> '/v1/fleet'. */
export function gatewayPath(pathname: string): string {
  const p = pathname.replace(/^\/functions\/v1/, "").replace(new RegExp(`^/${GATEWAY_NAME}`), "");
  return p === "" ? "/" : p;
}

export function bearerToken(authorization: string | null | undefined): string | null {
  const m = /^Bearer[ ]+(\S+)[ ]*$/i.exec(authorization ?? "");
  return m ? m[1] : null;
}

export function isWellFormedToken(token: string | null | undefined): boolean {
  return typeof token === "string" && TOKEN_PATTERN.test(token);
}

/** sha256 as lowercase hex -- the same digest ottoq_agent_issue_token stores (encode(sha256(convert_to(t,'UTF8')),'hex')). */
export async function sha256Hex(text: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(buf), (b) => b.toString(16).padStart(2, "0")).join("");
}

/** No Origin (a server-side agent) is allowed; a browser Origin must be on the configured list. MCP requires the
 *  check (DNS-rebinding), and agents are servers: by default no browser may call the gateway at all. */
export function originAllowed(origin: string | null | undefined, allowed: readonly string[]): boolean {
  if (!origin) return true;
  return allowed.includes(origin);
}

export function firstForwardedFor(header: string | null | undefined): string | undefined {
  const first = (header ?? "").split(",")[0]?.trim();
  return first ? first.slice(0, 64) : undefined;
}

export type HeaderGetter = { get(name: string): string | null };
export type HttpOut = { status: number; headers: Record<string, string>; body: unknown | null };

/** What public.ottoq_agent_call returns (and what the shell reports when it could not reach it). */
export type EngineOutcome = {
  ok: boolean;
  http_status: number;
  tool?: string;
  call_id?: number | null;
  principal?: { name: string; kind: string; capabilities: string[] };
  data?: unknown;
  error?: { code: string; message: string; hint?: string; retry_after_s?: number };
};
export type EngineCall = (tool: string, args: Record<string, unknown>, meta: Record<string, unknown>) => Promise<EngineOutcome>;

export const WWW_AUTHENTICATE = `Bearer realm="${GATEWAY_NAME}", error="invalid_token"`;

function errorHeaders(status: number, retryAfter?: number): Record<string, string> {
  if (status === 401) return { "WWW-Authenticate": WWW_AUTHENTICATE };
  // Only the rate limit says when to come back. The pending-request cap is also a 429, and waiting does not clear it
  // (a person deciding does), so it carries no Retry-After.
  if (status === 429 && retryAfter !== undefined) return { "Retry-After": String(retryAfter) };
  return {};
}

/** A failure the MCP transport reports as an HTTP error rather than as a tool result: the caller is not
 *  authenticated, is over its rate limit, or the engine could not be reached. Anything else a tool refuses is
 *  the tool's answer (isError), which an agent reads and acts on. */
export function isTransportFailure(outcome: EngineOutcome): boolean {
  return outcome.http_status === 401
    || (outcome.http_status === 429 && outcome.error?.code === "rate_limited")
    || outcome.http_status >= 502;
}

/** After a flagged refusal: the database answered with something other than the expected invalid_arguments
 *  (unknown token, rate limit, missing capability, unreachable engine), which then takes precedence. */
function isRefusalOtherThanArguments(r: EngineOutcome): boolean {
  return !r.ok && !(r.http_status === 400 && r.error?.code === "invalid_arguments");
}

// ──────────────────────────────────────────────────────────────────────────────────────────────── REST ──

export type RestRoute = { tool: string; pathArgs: Record<string, string> } | { error: "not_found" | "method_not_allowed"; allow?: string[] };

export function routeRest(method: string, path: string): RestRoute {
  const m = method.toUpperCase();
  const p = path.length > 1 ? path.replace(/\/+$/, "") : path;
  const table: Array<{ re: RegExp; methods: Record<string, string>; keys?: string[] }> = [
    { re: /^\/v1\/whoami$/, methods: { GET: "whoami" } },
    { re: /^\/v1\/depot$/, methods: { GET: "depot_status" } },
    { re: /^\/v1\/fleet$/, methods: { GET: "fleet_summary" } },
    { re: /^\/v1\/vehicles\/([^/]+)$/, methods: { GET: "vehicle_card" }, keys: ["vehicle_id"] },
    { re: /^\/v1\/decisions$/, methods: { GET: "recent_decisions" } },
    { re: /^\/v1\/stalls$/, methods: { GET: "stall_availability" } },
    { re: /^\/v1\/requests$/, methods: { GET: "list_requests", POST: "submit_request" } },
    { re: /^\/v1\/requests\/([^/]+)$/, methods: { GET: "list_requests" }, keys: ["request_id"] },
    { re: /^\/v1\/notes$/, methods: { POST: "send_note" } },
    { re: /^\/v1\/tools$/, methods: { GET: "tools_catalog" } },
  ];
  for (const r of table) {
    const hit = r.re.exec(p);
    if (!hit) continue;
    const tool = r.methods[m];
    if (!tool) return { error: "method_not_allowed", allow: Object.keys(r.methods) };
    const pathArgs: Record<string, string> = {};
    (r.keys ?? []).forEach((k, i) => {
      // A malformed escape is left as written; the argument's own schema (a UUID) then refuses it.
      try { pathArgs[k] = decodeURIComponent(hit[i + 1]); } catch { pathArgs[k] = hit[i + 1]; }
    });
    return { tool, pathArgs };
  }
  return { error: "not_found" };
}

export function restIndex(baseUrl: string) {
  return {
    name: GATEWAY_TITLE,
    version: GATEWAY_VERSION,
    about: "Read the OTTOYARD twin depot and ASK for changes. A person approves or declines every request; OTTO-Q's own doors decide what can happen. Send Authorization: Bearer <token>.",
    documentation: "https://github.com/OTTOYARD/otto-q-core/blob/main/AGENT_GATEWAY.md",
    mcp: `${baseUrl}/mcp`,
    agent_card: `${baseUrl}/.well-known/agent-card.json`,
    endpoints: TOOLS.map((t) => ({ method: t.rest.method, path: t.rest.path, tool: t.name, capability: t.capability, title: t.title }))
      .concat([{ method: "GET", path: "/v1/tools", tool: "tools_catalog", capability: null, title: "The tools your token may use, with JSON schemas" }]),
  };
}

/** Render an engine outcome as the REST envelope ({data, meta} / {error, meta}), like otto-q-api's. */
export function restResponse(outcome: EngineOutcome): HttpOut {
  const meta = { tool: outcome.tool ?? null, call_id: outcome.call_id ?? null };
  if (outcome.ok) {
    return {
      status: outcome.http_status,
      headers: {},
      body: { data: outcome.data ?? null, meta: { ...meta, principal: outcome.principal ? { name: outcome.principal.name, kind: outcome.principal.kind } : null } },
    };
  }
  const err = outcome.error ?? { code: "error", message: "The request failed." };
  return { status: outcome.http_status, headers: errorHeaders(outcome.http_status, err.retry_after_s), body: { error: err, meta } };
}

export async function handleRest(
  req: { method: string; path: string; query: URLSearchParams; headers: HeaderGetter; bodyText: string },
  call: EngineCall,
): Promise<HttpOut> {
  const route = routeRest(req.method, req.path);
  if ("error" in route) {
    if (route.error === "method_not_allowed") {
      return { status: 405, headers: { Allow: (route.allow ?? []).join(", ") }, body: { error: { code: "method_not_allowed", message: `Use ${(route.allow ?? []).join(" or ")} here.` } } };
    }
    return { status: 404, headers: {}, body: { error: { code: "not_found", message: "No such endpoint. GET /v1 lists them." } } };
  }
  if (route.tool === "tools_catalog") {
    const who = await call("handshake", {}, {});
    if (!who.ok) return restResponse(who);
    const tools = toolsFor(who.principal?.capabilities ?? []).map((t) => ({
      name: t.name, title: t.title, description: t.description, method: t.rest.method, path: t.rest.path, input_schema: t.inputSchema,
    }));
    return { status: 200, headers: {}, body: { data: { tools }, meta: { tool: "tools_catalog", call_id: who.call_id ?? null } } };
  }
  const tool = findTool(route.tool);
  if (!tool) return { status: 404, headers: {}, body: { error: { code: "not_found", message: "No such tool." } } };

  // Arguments the schema refuses still go to the database first, flagged, so the refusal is authenticated,
  // rate-limited and ledgered there: an unknown token gets its 401, not a lesson in the schema.
  const refuse = async (code: string, message: string, details?: ValidationError[]): Promise<HttpOut> => {
    const r = await call(tool.name, {}, { gateway_refusal: "invalid_arguments" });
    if (isRefusalOtherThanArguments(r)) return restResponse(r);
    return { status: 400, headers: {}, body: { error: details ? { code, message, details } : { code, message }, meta: { tool: tool.name, call_id: r.call_id ?? null } } };
  };

  let args: Record<string, unknown>;
  if (req.method.toUpperCase() === "GET") {
    const q = argsFromQuery(tool, req.query);
    if (!q.ok) return refuse("invalid_arguments", "The query parameters are not valid.", q.errors);
    args = { ...q.value, ...route.pathArgs };
  } else {
    let parsed: unknown = {};
    if (req.bodyText.trim() !== "") {
      try { parsed = JSON.parse(req.bodyText); } catch {
        return refuse("invalid_json", "The body is not valid JSON.");
      }
    }
    if (!isObject(parsed)) return refuse("invalid_arguments", "The body must be a JSON object.");
    args = { ...parsed };
    const idem = req.headers.get("idempotency-key");
    if (idem && args.idempotency_key === undefined) args.idempotency_key = idem;
  }
  const v = validateToolArgs(tool, args);
  if (!v.ok) return refuse("invalid_arguments", "The arguments are not valid.", v.errors);
  return restResponse(await call(tool.name, v.value, {}));
}

// ───────────────────────────────────────────────────────────────────────────────────────────────── MCP ──

export const MCP_MODERN_VERSION = "2026-07-28";
/** Modern first, then the initialize-based revisions this dual-era server still serves. */
export const MCP_SUPPORTED_VERSIONS = ["2026-07-28", "2025-11-25", "2025-06-18", "2025-03-26"] as const;
/** A request with neither the header nor _meta is treated as the oldest supported revision (transports page). */
export const MCP_DEFAULT_LEGACY_VERSION = "2025-03-26";
export const JSONRPC = {
  PARSE_ERROR: -32700,
  INVALID_REQUEST: -32600,
  METHOD_NOT_FOUND: -32601,
  INVALID_PARAMS: -32602,
  INTERNAL_ERROR: -32603,
  UNAUTHORIZED: -32001,
  RATE_LIMITED: -32002,
  HEADER_MISMATCH: -32020,
  UNSUPPORTED_PROTOCOL_VERSION: -32022,
} as const;

export const MCP_INSTRUCTIONS =
  "You are connected to OTTO-Q, the orchestration engine for the OTTOYARD Nashville Flagship twin depot. Reads are live. " +
  "Every change you ask for (send_note, submit_request) is a REQUEST: a person approves or declines it, and OTTO-Q's own " +
  "doors decide whether it can happen. Never report a change as done until list_requests shows status 'applied' with the " +
  "engine's reply. Times named sim_* or labelled SIMULATION are simulation time; created_at and expires_at are real time (UTC).";

type RpcId = string | number | null;
const rpcError = (id: RpcId, code: number, message: string, data?: unknown) =>
  ({ jsonrpc: "2.0", id, error: data === undefined ? { code, message } : { code, message, data } });
const rpcResult = (id: RpcId, result: unknown) => ({ jsonrpc: "2.0", id, result });
const JSON_HEADERS = { "Content-Type": "application/json" };

/** Decode an Mcp-Name / Mcp-Param value: plain header-safe ASCII, or the =?base64?...?= sentinel. null = invalid. */
export function decodeHeaderValue(v: string): string | null {
  const m = /^=\?base64\?([A-Za-z0-9+/=]*)\?=$/.exec(v);
  if (m) {
    try {
      const bin = atob(m[1]);
      return new TextDecoder("utf-8", { fatal: true }).decode(Uint8Array.from(bin, (c) => c.charCodeAt(0)));
    } catch {
      return null;
    }
  }
  return /^[\x20-\x7e\t]*$/.test(v) && v === v.trim() ? v : null;
}

/** The tools/list entries for a principal: name, title, description, inputSchema, annotations. */
export function mcpToolList(capabilities: readonly string[]) {
  return toolsFor(capabilities).map((t) => ({
    name: t.name,
    title: t.title,
    description: t.description,
    inputSchema: t.inputSchema,
    annotations: { title: t.title, ...t.annotations },
  }));
}

function toolCallResult(modern: boolean, data: unknown, isError: boolean) {
  const structured = isObject(data) ? data : { value: data };
  return {
    ...(modern ? { resultType: "complete" } : {}),
    content: [{ type: "text", text: JSON.stringify(structured, null, 2) }],
    structuredContent: structured,
    isError,
  };
}

function engineFailure(id: RpcId, outcome: EngineOutcome): HttpOut {
  const err = outcome.error ?? { code: "error", message: "The request failed." };
  if (outcome.http_status === 401) {
    return { status: 401, headers: { ...JSON_HEADERS, ...errorHeaders(401) }, body: rpcError(id, JSONRPC.UNAUTHORIZED, err.message, { code: err.code }) };
  }
  if (outcome.http_status === 429 && err.code === "rate_limited") {
    return { status: 429, headers: { ...JSON_HEADERS, ...errorHeaders(429, err.retry_after_s ?? 60) }, body: rpcError(id, JSONRPC.RATE_LIMITED, err.message, { code: err.code, retry_after_s: err.retry_after_s ?? 60 }) };
  }
  // The engine could not be reached or answered out of contract: an HTTP 5xx, so a client retries or reports it.
  const status = outcome.http_status >= 502 ? outcome.http_status : 200;
  return { status, headers: JSON_HEADERS, body: rpcError(id, JSONRPC.INTERNAL_ERROR, err.message, { code: err.code, call_id: outcome.call_id ?? null }) };
}

/**
 * One POST to the MCP endpoint. Dual-era: a request carrying `_meta["io.modelcontextprotocol/protocolVersion"]` (or the
 * MCP-Protocol-Version header) of 2026-07-28 is served statelessly with the mirrored-header checks; `initialize` and
 * header-less requests are served as the negotiated initialize-based revision. No sessions are minted in either era.
 */
export async function handleMcp(req: { method: string; headers: HeaderGetter; bodyText: string }, call: EngineCall): Promise<HttpOut> {
  const reply = (status: number, body: unknown, extra: Record<string, string> = {}): HttpOut => ({ status, headers: { ...JSON_HEADERS, ...extra }, body });
  const method = req.method.toUpperCase();
  if (method !== "POST") {
    return reply(405, rpcError(null, JSONRPC.INVALID_REQUEST, "The MCP endpoint accepts POST only: no GET stream and no sessions."), { Allow: "POST" });
  }
  let msg: unknown;
  try { msg = JSON.parse(req.bodyText); } catch { return reply(400, rpcError(null, JSONRPC.PARSE_ERROR, "Parse error: the body is not JSON.")); }
  if (Array.isArray(msg)) return reply(400, rpcError(null, JSONRPC.INVALID_REQUEST, "JSON-RPC batches are not supported: send one message per POST."));
  if (!isObject(msg) || msg.jsonrpc !== "2.0") return reply(400, rpcError(null, JSONRPC.INVALID_REQUEST, "Not a JSON-RPC 2.0 message."));
  const hasId = Object.prototype.hasOwnProperty.call(msg, "id");
  const id: RpcId = typeof msg.id === "string" || typeof msg.id === "number" ? msg.id : null;
  if (typeof msg.method !== "string") return reply(400, rpcError(id, JSONRPC.INVALID_REQUEST, "A client sends requests and notifications only."));
  if (hasId && id === null) return reply(400, rpcError(null, JSONRPC.INVALID_REQUEST, "id must be a string or a number."));
  if (msg.params !== undefined && !isObject(msg.params)) return reply(400, rpcError(id, JSONRPC.INVALID_REQUEST, "params must be an object."));
  const params: Record<string, unknown> = isObject(msg.params) ? msg.params : {};
  const meta: Record<string, unknown> = isObject(params._meta) ? params._meta : {};

  const headerVersion = req.headers.get("mcp-protocol-version");
  const bodyVersion = typeof meta["io.modelcontextprotocol/protocolVersion"] === "string" ? meta["io.modelcontextprotocol/protocolVersion"] as string : null;
  if (headerVersion !== null && bodyVersion !== null && headerVersion !== bodyVersion) {
    return reply(400, rpcError(id, JSONRPC.HEADER_MISMATCH, `Header mismatch: MCP-Protocol-Version ${headerVersion} does not match _meta ${bodyVersion}.`));
  }
  // A notification changes nothing here. It is still authenticated (an unknown token reaches nothing, not even a
  // 202), then accepted with no body.
  if (!hasId) {
    const who = await call("handshake", {}, { mcp_method: msg.method });
    if (!who.ok) return engineFailure(null, who);
    return { status: 202, headers: {}, body: null };
  }

  const isInitialize = msg.method === "initialize";
  const version = headerVersion ?? bodyVersion ?? (isInitialize ? null : MCP_DEFAULT_LEGACY_VERSION);
  if (version !== null && !(MCP_SUPPORTED_VERSIONS as readonly string[]).includes(version)) {
    return reply(400, rpcError(id, JSONRPC.UNSUPPORTED_PROTOCOL_VERSION, "Unsupported protocol version",
      { supported: [...MCP_SUPPORTED_VERSIONS], requested: version }));
  }
  const modern = version === MCP_MODERN_VERSION;

  // Mirrored headers: required in the modern era, and never allowed to disagree with the body in either.
  const hMethod = req.headers.get("mcp-method");
  if ((modern && hMethod === null) || (hMethod !== null && hMethod !== msg.method)) {
    return reply(400, rpcError(id, JSONRPC.HEADER_MISMATCH, hMethod === null
      ? "Header mismatch: Mcp-Method is required."
      : `Header mismatch: Mcp-Method ${hMethod} does not match body method ${msg.method}.`));
  }
  if (modern && bodyVersion === null) {
    return reply(400, rpcError(id, JSONRPC.HEADER_MISMATCH, "Header mismatch: the request _meta lacks io.modelcontextprotocol/protocolVersion."));
  }
  if (msg.method === "tools/call") {
    const hName = req.headers.get("mcp-name");
    if (modern && hName === null) return reply(400, rpcError(id, JSONRPC.HEADER_MISMATCH, "Header mismatch: Mcp-Name is required for tools/call."));
    if (hName !== null) {
      const decoded = decodeHeaderValue(hName);
      if (decoded === null || decoded !== params.name) {
        return reply(400, rpcError(id, JSONRPC.HEADER_MISMATCH, `Header mismatch: Mcp-Name does not match body name ${String(params.name)}.`));
      }
    }
  }

  const clientInfo = isObject(meta["io.modelcontextprotocol/clientInfo"]) ? meta["io.modelcontextprotocol/clientInfo"] as Record<string, unknown>
    : isObject(params.clientInfo) ? params.clientInfo : {};
  const callMeta = {
    mcp_method: msg.method,
    mcp_version: version ?? (typeof params.protocolVersion === "string" ? params.protocolVersion : ""),
    client: [clientInfo.name, clientInfo.version].filter((x) => typeof x === "string").join("/") || undefined,
  };
  const serverInfo = { name: GATEWAY_NAME, title: GATEWAY_TITLE, version: GATEWAY_VERSION };
  const modernFields = modern ? { resultType: "complete" } : {};

  switch (msg.method) {
    case "initialize": {
      const legacy = MCP_SUPPORTED_VERSIONS.filter((v) => v !== MCP_MODERN_VERSION) as string[];
      const requested = typeof params.protocolVersion === "string" ? params.protocolVersion : null;
      const who = await call("handshake", {}, callMeta);
      if (!who.ok) return engineFailure(id, who);
      return reply(200, rpcResult(id, {
        protocolVersion: requested !== null && legacy.includes(requested) ? requested : legacy[0],
        capabilities: { tools: { listChanged: false } },
        serverInfo,
        instructions: MCP_INSTRUCTIONS,
      }));
    }
    case "server/discover": {
      const who = await call("handshake", {}, callMeta);
      if (!who.ok) return engineFailure(id, who);
      return reply(200, rpcResult(id, {
        resultType: "complete",
        supportedVersions: [...MCP_SUPPORTED_VERSIONS],
        capabilities: { tools: { listChanged: false } },
        _meta: { "io.modelcontextprotocol/serverInfo": serverInfo },
        instructions: MCP_INSTRUCTIONS,
        ttlMs: 3_600_000,
        cacheScope: "public",
      }));
    }
    case "ping": {
      const who = await call("handshake", {}, callMeta);
      if (!who.ok) return engineFailure(id, who);
      return reply(200, rpcResult(id, { ...modernFields }));
    }
    case "tools/list": {
      if (params.cursor !== undefined) return reply(200, rpcError(id, JSONRPC.INVALID_PARAMS, "Invalid cursor: every tool is returned on one page."));
      const who = await call("handshake", {}, callMeta);
      if (!who.ok) return engineFailure(id, who);
      // The list varies by the token's capabilities, so it may be cached only for this token.
      return reply(200, rpcResult(id, {
        ...modernFields,
        tools: mcpToolList(who.principal?.capabilities ?? []),
        ...(modern ? { ttlMs: 300_000, cacheScope: "private" } : {}),
      }));
    }
    case "tools/call": {
      const refusal = { ...callMeta, gateway_refusal: "invalid_arguments" };
      const tool = findTool(params.name);
      if (!tool) {
        // Asked of the database too (it answers 404 unknown_tool after authenticating), so the attempt is ledgered.
        const r = await call(typeof params.name === "string" ? params.name.slice(0, 64) : "", {}, refusal);
        if (isTransportFailure(r)) return engineFailure(id, r);
        return reply(200, rpcError(id, JSONRPC.INVALID_PARAMS, `Unknown tool: ${String(params.name)}`));
      }
      const v = validateToolArgs(tool, params.arguments);
      if (!v.ok) {
        const r = await call(tool.name, {}, refusal);
        if (isTransportFailure(r)) return engineFailure(id, r);
        const error = isRefusalOtherThanArguments(r)
          ? (r.error ?? { code: "error", message: "The request failed." })
          : { code: "invalid_arguments", message: "The arguments are not valid.", details: v.errors };
        return reply(200, rpcResult(id, toolCallResult(modern, { error, call_id: r.call_id ?? null }, true)));
      }
      const outcome = await call(tool.name, v.value, callMeta);
      if (isTransportFailure(outcome)) return engineFailure(id, outcome);
      if (!outcome.ok) {
        return reply(200, rpcResult(id, toolCallResult(modern, { error: outcome.error ?? { code: "error", message: "The request failed." }, call_id: outcome.call_id ?? null }, true)));
      }
      return reply(200, rpcResult(id, toolCallResult(modern, outcome.data, false)));
    }
    default:
      return reply(modern ? 404 : 200, rpcError(id, JSONRPC.METHOD_NOT_FOUND, `Method not found: ${msg.method}`));
  }
}

// ─────────────────────────────────────────────────────────────────────────────────────────────── A2A ──

/** A2A 1.0 Agent Card for DISCOVERY. The gateway does not implement A2A's SendMessage/Task operations; its two
 *  interfaces are declared as custom bindings (MCP Streamable HTTP and the REST API), which A2A allows by URI. */
export function agentCard(baseUrl: string) {
  return {
    name: GATEWAY_TITLE,
    description:
      "Read the OTTOYARD Nashville Flagship twin depot through OTTO-Q, and ask for changes. Every change is a request a " +
      "person approves or declines; OTTO-Q's own doors decide what can happen. Discovery card only: the gateway speaks " +
      "MCP and a REST API, not A2A task messaging.",
    supportedInterfaces: [
      { url: `${baseUrl}/mcp`, protocolBinding: "https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http", protocolVersion: MCP_MODERN_VERSION },
      { url: `${baseUrl}/v1`, protocolBinding: "https://github.com/OTTOYARD/otto-q-core/blob/main/AGENT_GATEWAY.md#rest-api", protocolVersion: "1.0" },
    ],
    provider: { organization: "OTTOYARD", url: "https://ottoyard.com" },
    version: GATEWAY_VERSION,
    documentationUrl: "https://github.com/OTTOYARD/otto-q-core/blob/main/AGENT_GATEWAY.md",
    capabilities: { streaming: false, pushNotifications: false, extendedAgentCard: false },
    securitySchemes: {
      ottoqAgentToken: {
        httpAuthSecurityScheme: {
          scheme: "Bearer",
          bearerFormat: "opaque: oqa_ + 64 hex",
          description: "An agent token issued by ottoq_agent_issue_token. Its scope (depot, fleet, capabilities) is fixed at issue and enforced by the database.",
        },
      },
    },
    securityRequirements: [{ schemes: { ottoqAgentToken: { list: [] } } }],
    defaultInputModes: ["application/json"],
    defaultOutputModes: ["application/json"],
    skills: TOOLS.map((t) => ({
      id: t.name,
      name: t.title,
      description: t.description,
      tags: [...t.tags],
      examples: [...t.examples],
      inputModes: ["application/json"],
      outputModes: ["application/json"],
    })),
  };
}

// ───────────────────────────────────────────────────────────────────────────── the engine, over PostgREST ──

/** One call into the database: token hash, tool, validated arguments, transport, and small request metadata. */
export type EngineRpc = (
  tokenHash: string,
  tool: string,
  args: Record<string, unknown>,
  transport: "rest" | "mcp",
  meta: Record<string, unknown>,
) => Promise<EngineOutcome>;

/**
 * public.ottoq_agent_call over PostgREST with the service key -- the gateway's ONLY way into the database. The key
 * goes in `apikey`, and also as a Bearer only when it is a JWT (the legacy service_role key): the new sb_secret_ keys
 * are not JWTs and are sent in `apikey` alone (https://supabase.com/docs/guides/functions/auth-headers, read
 * 2026-09-28).
 */
export function postgrestEngine(o: { supabaseUrl: string; serviceKey: string; fetchImpl?: typeof fetch; timeoutMs?: number }): EngineRpc {
  const endpoint = `${o.supabaseUrl.replace(/\/+$/, "")}/rest/v1/rpc/${ENGINE_RPC}`;
  const headers: Record<string, string> = { "Content-Type": "application/json", Accept: "application/json", apikey: o.serviceKey };
  if (/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(o.serviceKey)) headers.Authorization = `Bearer ${o.serviceKey}`;
  const doFetch = o.fetchImpl ?? fetch;
  const timeoutMs = o.timeoutMs ?? 15_000;

  return async (tokenHash, tool, args, transport, meta) => {
    let res: Response;
    try {
      res = await doFetch(endpoint, {
        method: "POST",
        headers,
        body: JSON.stringify({ p_token_hash: tokenHash, p_tool: tool, p_args: args, p_transport: transport, p_meta: meta }),
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch (e) {
      const name = (e as { name?: string } | null)?.name;
      if (name === "TimeoutError" || name === "AbortError") {
        return { ok: false, http_status: 504, tool, call_id: null, error: { code: "engine_timeout",
          message: "OTTO-Q did not answer in time, so the outcome is unknown. Check list_requests before asking again, or resend with the same idempotency_key." } };
      }
      return { ok: false, http_status: 503, tool, call_id: null, error: { code: "engine_unreachable", message: "OTTO-Q could not be reached. Nothing was recorded; try again shortly." } };
    }
    const text = await res.text();
    let body: unknown = null;
    try { body = text ? JSON.parse(text) : null; } catch { body = null; }
    if (res.ok && isObject(body) && typeof body.ok === "boolean" && typeof body.http_status === "number") {
      return body as EngineOutcome;
    }
    const pgCode = isObject(body) && typeof body.code === "string" ? body.code : "";
    if (res.status === 404 || pgCode === "PGRST202" || pgCode === "42883") {
      return { ok: false, http_status: 503, tool, call_id: null, error: { code: "gateway_not_enabled",
        message: "Agent access is built but not enabled yet: its database half (migration 0550) is not applied." } };
    }
    if (res.status === 401 || res.status === 403 || pgCode === "42501") {
      return { ok: false, http_status: 502, tool, call_id: null, error: { code: "engine_misconfigured", message: "The gateway could not authenticate to OTTO-Q." } };
    }
    return { ok: false, http_status: 502, tool, call_id: null, error: { code: "engine_error", message: "OTTO-Q answered outside the gateway's contract." } };
  };
}

// ─────────────────────────────────────────────────────── the whole request, as one web-standard handler ──

export type GatewayOptions = {
  /** The base URL agents use (https://<ref>.supabase.co/functions/v1/ottoq-agent-gateway), no trailing slash. */
  publicUrl: string;
  /** Browser origins allowed to call the authenticated endpoints. Empty (the default) = no browser at all. */
  allowedOrigins: readonly string[];
  /** null when the deployment lacks SUPABASE_URL or the service key: authenticated paths then answer 500. */
  engine: EngineRpc | null;
};

export const CORS_ALLOW_HEADERS = "authorization, content-type, idempotency-key, mcp-protocol-version, mcp-method, mcp-name";
const CORS_EXPOSE_HEADERS = "www-authenticate, retry-after, x-ottoq-gateway";
const CARD_PATHS = new Set(["/.well-known/agent-card.json", "/.well-known/agent.json"]);

function baseHeaders(): Record<string, string> {
  return {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "X-OTTOQ-Gateway": `${GATEWAY_NAME}/${GATEWAY_VERSION}`,
  };
}

function toResponse(out: HttpOut, extra: Record<string, string> = {}): Response {
  const headers: Record<string, string> = { ...baseHeaders(), ...out.headers, ...extra };
  if (out.body === null) {
    delete headers["Content-Type"];
    return new Response(null, { status: out.status, headers });
  }
  return new Response(JSON.stringify(out.body), { status: out.status, headers });
}

/** Read at most `limit` bytes of a body. null = it was longer (the rest is not read). */
export async function readBodyBounded(body: ReadableStream<Uint8Array> | null, limit: number): Promise<string | null> {
  if (!body) return "";
  const reader = body.getReader();
  const chunks: Uint8Array[] = [];
  let n = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    n += value.byteLength;
    if (n > limit) {
      try { await reader.cancel(); } catch { /* the stream is abandoned either way */ }
      return null;
    }
    chunks.push(value);
  }
  const all = new Uint8Array(n);
  let off = 0;
  for (const c of chunks) { all.set(c, off); off += c.byteLength; }
  return new TextDecoder().decode(all);
}

/**
 * Every request the edge function receives. Order matters and is the security model's outer half:
 *   1. the public discovery documents (agent card, endpoint index) -- no token, no database;
 *   2. the Origin check (a browser origin not on the list is refused; agents send none);
 *   3. a well-formed Bearer token, or 401 before the database is asked;
 *   4. a bounded body (64 KiB);
 *   5. the token's SHA-256 -- the raw token never leaves this function -- and then REST or MCP, each of which asks
 *      the database, which resolves the principal, rate-limits, checks the capability and writes the call ledger.
 */
export async function handleGatewayRequest(req: Request, opts: GatewayOptions): Promise<Response> {
  const url = new URL(req.url);
  const rawPath = gatewayPath(url.pathname);
  const path = rawPath.length > 1 ? rawPath.replace(/\/+$/, "") : rawPath;
  const method = req.method.toUpperCase();
  const origin = req.headers.get("origin");
  const isMcp = path === "/mcp";
  const cors: Record<string, string> = origin && opts.allowedOrigins.includes(origin)
    ? { "Access-Control-Allow-Origin": origin, "Access-Control-Expose-Headers": CORS_EXPOSE_HEADERS, Vary: "Origin" }
    : {};
  const refuse = (status: number, code: string, message: string, headers: Record<string, string> = {}): Response => {
    const body = isMcp
      ? rpcError(null, status === 401 ? JSONRPC.UNAUTHORIZED : status >= 500 ? JSONRPC.INTERNAL_ERROR : JSONRPC.INVALID_REQUEST, message, { code })
      : { error: { code, message }, meta: { tool: null, call_id: null } };
    return toResponse({ status, headers, body }, cors);
  };

  try {
    // 1. public discovery
    if (CARD_PATHS.has(path)) {
      const pub = { "Access-Control-Allow-Origin": "*" };
      if (method === "OPTIONS") return toResponse({ status: 204, headers: { ...pub, "Access-Control-Allow-Methods": "GET, OPTIONS", Allow: "GET, HEAD, OPTIONS" }, body: null });
      if (method !== "GET" && method !== "HEAD") return toResponse({ status: 405, headers: { Allow: "GET, HEAD, OPTIONS" }, body: { error: { code: "method_not_allowed", message: "Use GET." } } });
      const res = toResponse({ status: 200, headers: { ...pub, "Cache-Control": "public, max-age=300" }, body: agentCard(opts.publicUrl) });
      return method === "HEAD" ? new Response(null, { status: 200, headers: res.headers }) : res;
    }
    if ((path === "/" || path === "/v1") && method === "GET") {
      return toResponse({ status: 200, headers: {}, body: restIndex(opts.publicUrl) });
    }

    // 2. browsers: only listed origins; agents send no Origin
    if (!originAllowed(origin, opts.allowedOrigins)) {
      return refuse(403, "origin_not_allowed", "This origin may not call the gateway. Agents call it server-side, without an Origin.");
    }
    if (method === "OPTIONS") {
      return toResponse({ status: 204, body: null, headers: {
        Allow: "GET, POST, OPTIONS",
        ...(origin ? { "Access-Control-Allow-Methods": "GET, POST, OPTIONS", "Access-Control-Allow-Headers": CORS_ALLOW_HEADERS, "Access-Control-Max-Age": "600" } : {}),
      } }, cors);
    }

    // 3. a well-formed token, before anything else is read
    const token = bearerToken(req.headers.get("authorization"));
    if (token === null || !isWellFormedToken(token)) {
      return refuse(401, "unauthenticated", "Send Authorization: Bearer <agent token>. Tokens are issued by the depot; see the documentation.",
        { "WWW-Authenticate": WWW_AUTHENTICATE });
    }
    if (!opts.engine) return refuse(500, "not_configured", "The gateway is deployed without its database connection.");
    const engine = opts.engine;

    // 4. a bounded body (only POST carries one)
    let bodyText = "";
    if (method === "POST") {
      const declared = Number(req.headers.get("content-length") ?? "0");
      if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) return refuse(413, "body_too_large", `The body is limited to ${MAX_BODY_BYTES} bytes.`);
      const read = await readBodyBounded(req.body, MAX_BODY_BYTES);
      if (read === null) return refuse(413, "body_too_large", `The body is limited to ${MAX_BODY_BYTES} bytes.`);
      bodyText = read;
    }

    // 5. hash, then the conversation
    const tokenHash = await sha256Hex(token);
    const userAgent = req.headers.get("user-agent");
    const baseMeta: Record<string, unknown> = {
      http_method: method,
      path: path.slice(0, 200),
      ip: firstForwardedFor(req.headers.get("x-forwarded-for")),
      client: userAgent ? userAgent.slice(0, 120) : undefined,
    };
    const call: EngineCall = (tool, args, meta) => {
      const merged: Record<string, unknown> = { ...baseMeta };
      for (const [k, v] of Object.entries(meta)) if (v !== undefined && v !== null && v !== "") merged[k] = v;
      for (const k of Object.keys(merged)) if (merged[k] === undefined) delete merged[k];
      return engine(tokenHash, tool, args, isMcp ? "mcp" : "rest", merged);
    };
    const out = isMcp
      ? await handleMcp({ method, headers: req.headers, bodyText }, call)
      : await handleRest({ method, path, query: url.searchParams, headers: req.headers, bodyText }, call);
    return toResponse(out, cors);
  } catch (e) {
    console.error(`${GATEWAY_NAME}: unhandled`, (e as Error)?.name ?? "error", (e as Error)?.message?.slice(0, 200) ?? "");
    return refuse(500, "internal_error", "The gateway hit an internal error.");
  }
}
