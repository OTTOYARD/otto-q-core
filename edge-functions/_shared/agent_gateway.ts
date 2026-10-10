/**
 * The ottoq-agent-gateway's pure half (db/migrations/0559, AGENT_GATEWAY.md).
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
 * 0605 (PERSONAL_AGENT.md): an OWNER's agent -- a token bound to one fleet and carrying owner_settings -- can also set
 * what its own cars need: a charge limit inside its contract, a service, a hold, an undo. The database checks each one
 * against the contract and OTTO-Q's rules, records it (refusals included), and the engine applies it at its next tick;
 * nothing an agent sends moves a car. POST /v1/ask is the same door in plain English: OTTO-Command reads the owner's
 * words and calls these same tools with the owner's own token, so it can do nothing the token could not
 * (./ottocommand_owner.ts).
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
import { ACCESS_TOKEN_PATTERN, ACCOUNT_MCP_PATH, accountChallenge, handleSignin, isSigninPath, type OAuthRpc,
         type SigninConfig } from "./agent_signin.ts";

export const GATEWAY_NAME = "ottoq-agent-gateway";
export const GATEWAY_TITLE = "OTTO-Q Agent Gateway";
export const GATEWAY_VERSION = "1.0.0";
export const TWIN_DEPOT_ID = "11111111-1111-1111-1111-111111111111";
/** The ONLY database function the gateway calls. Everything else is the database's business. */
export const ENGINE_RPC = "ottoq_agent_call";
/** 'oqa_' + 64 lowercase hex characters, as ottoq_agent_issue_token mints them. Anything else is refused before the database. */
/** An agent key (oqa_, issued by ottoq_agent_issue_token), a passcode session key (oqs_, from enter_passcode, 0607), or an
 *  access token of an agent signed in to an owner's account (oqt_, from the sign-in token endpoint, 0660). */
export const TOKEN_PATTERN = /^oq[ast]_[0-9a-f]{64}$/;
/** A passcode session key: the only kind an agent may also send as a tool's `session` argument, never a long-lived key. */
export const SESSION_PATTERN = /^oqs_[0-9a-f]{64}$/;
export const MAX_BODY_BYTES = 64 * 1024;

export const CAPABILITIES = ["read", "note", "request_recall", "request_ops_action", "request_adjustment", "owner_settings"] as const;
export type Capability = (typeof CAPABILITIES)[number];

// ── 0607: the passcode door ──
/** What a passcode session holds: exactly an owner key's capabilities (a CHECK in the database pins it). */
export const PASSCODE_CAPABILITIES = ["read", "note", "owner_settings"] as const;
/** The tools a caller without a key is offered, in order: the two public ones, then what a session can do. */
export const PASSCODE_TOOL_NAMES: readonly string[] = ["welcome", "enter_passcode", "whoami", "my_fleet", "my_vehicle",
  "my_settings", "my_commands", "set_charge_limit", "clear_charge_limit", "request_service", "cancel_service", "hold_vehicle",
  "release_hold", "undo_command", "depot_status", "send_note"];

/** 0605: the owner's reads and commands, exactly as public.ottoq_agent_call names them. */
export const OWNER_READS = ["my_fleet", "my_vehicle", "my_settings", "my_commands"] as const;
export const OWNER_COMMANDS = [
  "set_charge_limit", "clear_charge_limit", "request_service", "cancel_service", "hold_vehicle", "release_hold", "undo_command",
] as const;
/** public.ottoq_owner_requestable_services(): what an owner may ask for. Charging, the readiness check, triage, fault
 *  repair and the depot's own walkaround are OTTO-Q's, not an owner's. A contract may block some of these too. */
export const OWNER_SERVICES = [
  "exterior_wash", "interior_deep_clean", "interior_tidy", "interior_inspection", "sensor_clean", "sensor_calibration",
  "software_update", "remote_diagnostics", "mechanical_pm", "cosmetic_repair", "item_retrieval",
] as const;
export const SERVICE_WHEN = ["now", "next_return", "every_return"] as const;
/** ottoq_owner_commands.outcome */
export const OWNER_OUTCOMES = ["applied", "previewed", "no_change", "refused"] as const;

/** ottoq_apply_ops_action's whitelist, action -> the dial it sets. The database (0559's submit function) is the
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
  items?: JsonSchema;
  minItems?: number;
  maxItems?: number;
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
  /** What the tool can change: nothing; the agent's own request ledger; or (0605) the settings of the owner's OWN cars,
   *  which the engine applies at its next tick; or (0607) open a passcode session for the caller. Never a car's
   *  movement, a stall, a booking or a charge session. */
  effect: "read" | "ledger_write" | "owner_setting" | "session";
  /** 0607: callable with no key at all (welcome, enter_passcode). */
  public?: true;
  /** 'fleet' = only for a token bound to one fleet (the database refuses any other with fleet_scope_required). */
  scope?: "fleet";
  inputSchema: JsonSchema;
  annotations: ToolAnnotations;
  rest: { method: "GET" | "POST"; path: string };
  tags: readonly string[];
  examples: readonly string[];
};

const READ: ToolAnnotations = { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false };
const ASK: ToolAnnotations = { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false };
/** An owner command changes the owner's own settings, so it is not read-only. It is not destructive in MCP's sense:
 *  nothing it replaces is lost (the ledger is append-only, undo_command restores what a command replaced, and the run's
 *  end lifts everything). Idempotent where sending the same arguments again changes nothing more -- every command but
 *  hold_vehicle, whose for_minutes counts from the clock at the time it is sent. */
const SET: ToolAnnotations = { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false };
const SET_ONCE: ToolAnnotations = { ...SET, idempotentHint: false };

// ── 0605: the owner's arguments ──
const VEHICLES: JsonSchema = {
  type: ["string", "array"], minLength: 1, maxLength: 80, minItems: 1, maxItems: 100,
  items: { type: "string", minLength: 1, maxLength: 80 },
  description: "Which of your cars: \"all\", one name, or a list of up to 100 names, said the way a person says them " +
    "(\"Tesla-AV-045\", \"Tesla 45\", \"AV-045\", \"RT-003\"). Names are matched only inside your own fleet; a name that " +
    "matches none or several of your cars is refused, and the refusal lists your cars' names.",
};
const MODE: JsonSchema = {
  type: "string", enum: ["apply", "preview"],
  description: "apply (the default) makes the change. preview changes nothing and answers with the exact plan, its " +
    "plan_hash and a ready-to-send confirm; send that confirm to apply exactly what was shown.",
};
const PLAN_HASH: JsonSchema = {
  type: "string", pattern: "^[0-9a-f]{32}$",
  description: "Optional, with mode apply: the plan_hash a preview returned. OTTO-Q then applies only that plan; if a " +
    "setting moved in between, it refuses with plan_changed and the new plan.",
};
const OWNER_IDEMPOTENCY: JsonSchema = {
  type: "string", pattern: "^[A-Za-z0-9._:-]{1,100}$",
  description: "Optional. Sending the same command again with the same key returns the first receipt instead of acting " +
    "twice; the same key with a different command is refused (idempotency_key_reused).",
};
const OWNER_NOTE: JsonSchema = {
  type: "string", maxLength: 500,
  description: "Optional: why, in your person's words (at most 500 characters). Shown on the receipt and in OrchestrAV.",
};
const COMMAND_OPTIONS: Record<string, JsonSchema> = {
  mode: MODE, expect_plan_hash: PLAN_HASH, idempotency_key: OWNER_IDEMPOTENCY, note: OWNER_NOTE,
};
const RECEIPT =
  " Answers with a receipt: outcome (applied, previewed, no_change or refused), a plain-English summary, and an " +
  "OrchestrAV link to see it. Relay the summary and the link to your person; a change is done only when outcome is " +
  "applied. Lasts until the demo run ends or you undo it.";
const serviceProp = (description: string): JsonSchema => ({ type: "string", enum: OWNER_SERVICES, description });
const SERVICE_GUIDE =
  "exterior_wash (external cleaning, a wash bay), interior_deep_clean (a full detail), interior_tidy (a quick clean), " +
  "interior_inspection, sensor_clean (cameras and sensors), sensor_calibration, software_update, remote_diagnostics, " +
  "mechanical_pm (a service-bay visit with a technician), cosmetic_repair, item_retrieval (an item left in the car)";

const SESSION_PROP: JsonSchema = {
  type: "string", pattern: "^oqs_[0-9a-f]{64}$",
  description: "The session key enter_passcode gave you. Send it with every call. If OTTOYARD says the session ended " +
    "(a stop or reset of the demo ends every session) or expired, call enter_passcode again for a new one.",
};

export const TOOLS: readonly ToolDef[] = [
  {
    name: "welcome",
    title: "Welcome to OTTOYARD",
    description: "Start here. With no key: what OTTOYARD is, what its demo passcode opens (a fleet's cars at the twin " +
      "depot: how full they charge, which services they get, when they may leave), whether a demo run is live, and the " +
      "exact next call (enter_passcode). Connected: who you are, until when, and what to try. Changes nothing.",
    capability: null, effect: "read", public: true,
    inputSchema: {
      type: "object", additionalProperties: false,
      properties: { agent: { type: "string", minLength: 1, maxLength: 80, description: "Optional: your name. Not needed here; give it to enter_passcode." } },
    },
    annotations: READ, rest: { method: "GET", path: "/v1/welcome" }, tags: ["start", "identity"],
    examples: ["Hi OTTOYARD, what can I do here?", "Connect me to OTTOYARD."],
  },
  {
    name: "enter_passcode",
    title: "Enter OTTOYARD's passcode",
    description: "Open a session with OTTOYARD's demo passcode, which your person gives you, and your own name. Answers " +
      "with a session key: send it as the `session` argument on every other OTTOYARD tool (on the REST API, as " +
      "Authorization: Bearer), and never show it to anyone. The session reads and adjusts one fleet's cars until the demo " +
      "run ends or for a few hours. A wrong passcode is refused in plain English; repeated wrong tries make you wait.",
    capability: null, effect: "session", public: true,
    inputSchema: {
      type: "object", additionalProperties: false, required: ["passcode"],
      properties: {
        passcode: { type: "string", minLength: 1, maxLength: 200, description: "OTTOYARD's demo passcode, exactly as your person gave it." },
        agent: { type: "string", minLength: 1, maxLength: 80, description: "Your name, as your person would recognize it (\"Hermes\", \"Grok\"). Shown on receipts and in OrchestrAV." },
      },
    },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
    rest: { method: "POST", path: "/v1/passcode" }, tags: ["start", "session"],
    examples: ["{\"passcode\": \"<from your person>\", \"agent\": \"Hermes\"}"],
  },
  {
    name: "whoami",
    title: "Who am I",
    description: "Your principal: kind, the depot and fleet you are scoped to, your capabilities and limits, and how a change you ask for gets decided. An owner's token also gets an owner block: its cars, its contract's charge-limit range, the services it may order, and its OrchestrAV link.",
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
  // ── 0605: an owner's agent, on its own cars. Everything below needs a token bound to one fleet. ──
  {
    name: "my_fleet",
    title: "My cars",
    description: "Your cars at the depot, in plain English (summary) and as data (cars): how many are charging, in a bay, waiting or out on the road, their average charge, the settings you have in force, which will be ready next, and the OrchestrAV link to watch them. Start here for anything about your cars. Times marked \"sim time\" are the simulation's clock, in Nashville time.",
    capability: "read", effect: "read", scope: "fleet", inputSchema: EMPTY, annotations: READ,
    rest: { method: "GET", path: "/v1/me/fleet" }, tags: ["owner", "fleet"],
    examples: ["How are my Teslas doing?", "Which of my cars will be ready next?"],
  },
  {
    name: "my_vehicle",
    title: "One of my cars",
    description: "One of your cars in plain English: where it is and what it is doing, its charge and the target it charges to, what is still to do before it leaves (your orders marked), any hold you set, when OTTO-Q plans it to be ready, and OTTO-Q's last decision for it.",
    capability: "read", effect: "read", scope: "fleet",
    inputSchema: {
      type: "object", additionalProperties: false, required: ["vehicle"],
      properties: { vehicle: { type: "string", minLength: 1, maxLength: 80, description: "The car, as a person says it: \"Tesla-AV-045\", \"Tesla 45\", \"RT-003\"." } },
    },
    annotations: READ, rest: { method: "GET", path: "/v1/me/vehicles/{vehicle}" }, tags: ["owner", "vehicles"],
    examples: ["Where is Tesla 45 and when will it be ready?", "{\"vehicle\": \"Tesla-RT-003\"}"],
  },
  {
    name: "my_settings",
    title: "My settings in force",
    description: "Everything you have in force on the current demo run, car by car: charge limits, holds and service orders, each with the command that set it. Everything lifts when the run ends.",
    capability: "read", effect: "read", scope: "fleet", inputSchema: EMPTY, annotations: READ,
    rest: { method: "GET", path: "/v1/me/settings" }, tags: ["owner", "settings"],
    examples: ["What have I set on my cars?"],
  },
  {
    name: "my_commands",
    title: "My commands",
    description: "Your commands, newest first: each one's outcome, its plain-English receipt, the cars it touched, and whether it was undone or lifted when its run ended.",
    capability: null, effect: "read", scope: "fleet",
    inputSchema: {
      type: "object", additionalProperties: false,
      properties: {
        command_id: uuidProp("Just this command."),
        outcome: { type: "string", enum: OWNER_OUTCOMES, description: "Only commands with this outcome." },
        limit: { type: "integer", minimum: 1, maximum: 50, description: "At most this many (default 10)." },
      },
    },
    annotations: READ, rest: { method: "GET", path: "/v1/me/commands" }, tags: ["owner", "commands"],
    examples: ["Did my last change go through?", "{\"outcome\": \"refused\"}"],
  },
  {
    name: "set_charge_limit",
    title: "Set how full my cars charge",
    description: "Set the most your cars charge to, for example 90 instead of the full 100, so they can get back to work sooner. Only inside your contract's range (whoami: owner.charge_limit_pct); outside it is refused. A car charging now stops at the new limit; a car already above it is not drained." + RECEIPT,
    capability: "owner_settings", effect: "owner_setting", scope: "fleet",
    inputSchema: {
      type: "object", additionalProperties: false, required: ["vehicles", "percent"],
      properties: {
        vehicles: VEHICLES,
        percent: { type: "integer", minimum: 1, maximum: 100, description: "The most a car charges to, in percent, e.g. 90." },
        ...COMMAND_OPTIONS,
      },
    },
    annotations: SET, rest: { method: "POST", path: "/v1/me/charge-limit" }, tags: ["owner", "charging"],
    examples: ["{\"vehicles\": \"all\", \"percent\": 90}", "{\"vehicles\": [\"Tesla-AV-045\"], \"percent\": 85, \"mode\": \"preview\"}"],
  },
  {
    name: "clear_charge_limit",
    title: "Charge my cars full again",
    description: "Lift your charge limit so these cars charge to the full target again." + RECEIPT,
    capability: "owner_settings", effect: "owner_setting", scope: "fleet",
    inputSchema: {
      type: "object", additionalProperties: false, required: ["vehicles"],
      properties: { vehicles: VEHICLES, ...COMMAND_OPTIONS },
    },
    annotations: SET, rest: { method: "POST", path: "/v1/me/charge-limit/clear" }, tags: ["owner", "charging"],
    examples: ["{\"vehicles\": \"all\"}"],
  },
  {
    name: "request_service",
    title: "Order a service for my cars",
    description: "Order a service for your cars: " + SERVICE_GUIDE + ". when: now (this visit, or the next one for a car that is out), next_return, or every_return (a standing order; include_current_visit false starts it from the next return). OTTO-Q decides when and where: bay work comes after the charge, work at the car runs during it, and no car leaves with an ordered service undone. So \"a service bay right after charging\" is mechanical_pm, when now. Your contract may block some services." + RECEIPT,
    capability: "owner_settings", effect: "owner_setting", scope: "fleet",
    inputSchema: {
      type: "object", additionalProperties: false, required: ["vehicles", "service"],
      properties: {
        vehicles: VEHICLES,
        service: serviceProp("The service to order."),
        when: { type: "string", enum: SERVICE_WHEN, description: "now (default), next_return or every_return." },
        include_current_visit: { type: "boolean", description: "every_return only: true (default) includes the visit under way now; false starts from the next return." },
        ...COMMAND_OPTIONS,
      },
    },
    annotations: SET, rest: { method: "POST", path: "/v1/me/services" }, tags: ["owner", "services"],
    examples: [
      "{\"vehicles\": [\"Tesla-AV-045\"], \"service\": \"mechanical_pm\"}",
      "{\"vehicles\": \"all\", \"service\": \"exterior_wash\", \"when\": \"every_return\"}",
    ],
  },
  {
    name: "cancel_service",
    title: "Withdraw my service orders",
    description: "Withdraw your service orders on these cars: one service, or every order you placed on them if service is omitted. Only what you ordered comes off: a service OTTO-Q found a car to need stays, and a service already under way finishes." + RECEIPT,
    capability: "owner_settings", effect: "owner_setting", scope: "fleet",
    inputSchema: {
      type: "object", additionalProperties: false, required: ["vehicles"],
      properties: { vehicles: VEHICLES, service: serviceProp("Optional: just this service's order."), ...COMMAND_OPTIONS },
    },
    annotations: SET, rest: { method: "POST", path: "/v1/me/services/cancel" }, tags: ["owner", "services"],
    examples: ["{\"vehicles\": \"all\", \"service\": \"exterior_wash\"}"],
  },
  {
    name: "hold_vehicle",
    title: "Keep my cars at the depot until a time",
    description: "Keep cars at the depot until a time: until is a time of day on the sim clock (\"06:00\", \"6:00 AM\", taken as its next occurrence) or an ISO timestamp (Nashville time when it has no offset); or for_minutes, 1 to 1440. Give exactly one. At most 24 sim hours. A hold only delays a departure: it never moves a car, and a car that is ready waits in staging without keeping a charger." + RECEIPT,
    capability: "owner_settings", effect: "owner_setting", scope: "fleet",
    inputSchema: {
      type: "object", additionalProperties: false, required: ["vehicles"],
      properties: {
        vehicles: VEHICLES,
        until: { type: "string", minLength: 1, maxLength: 40, description: "\"06:00\", \"6:00 AM\" or an ISO timestamp." },
        for_minutes: { type: "integer", minimum: 1, maximum: 1440, description: "Or: hold for this many sim minutes." },
        ...COMMAND_OPTIONS,
      },
    },
    annotations: SET_ONCE, rest: { method: "POST", path: "/v1/me/holds" }, tags: ["owner", "holds"],
    examples: ["{\"vehicles\": [\"Tesla-RT-003\"], \"until\": \"6:00 AM\"}", "{\"vehicles\": \"all\", \"for_minutes\": 90}"],
  },
  {
    name: "release_hold",
    title: "Let my held cars go",
    description: "Lift your hold so these cars may leave as soon as they are ready." + RECEIPT,
    capability: "owner_settings", effect: "owner_setting", scope: "fleet",
    inputSchema: {
      type: "object", additionalProperties: false, required: ["vehicles"],
      properties: { vehicles: VEHICLES, ...COMMAND_OPTIONS },
    },
    annotations: SET, rest: { method: "POST", path: "/v1/me/holds/release" }, tags: ["owner", "holds"],
    examples: ["{\"vehicles\": [\"Tesla-RT-003\"]}"],
  },
  {
    name: "undo_command",
    title: "Undo one of my commands",
    description: "Reverse one of your applied commands by its command_id (from its receipt or my_commands): what it set is withdrawn, and anything it replaced comes back. A command whose run has ended was already lifted with it." + RECEIPT,
    capability: "owner_settings", effect: "owner_setting", scope: "fleet",
    inputSchema: {
      type: "object", additionalProperties: false, required: ["command_id"],
      properties: { command_id: uuidProp("The command to undo."), ...COMMAND_OPTIONS },
    },
    annotations: SET, rest: { method: "POST", path: "/v1/me/undo" }, tags: ["owner", "commands"],
    examples: ["{\"command_id\": \"<command_id from a receipt>\"}"],
  },
];

export function findTool(name: unknown): ToolDef | undefined {
  return typeof name === "string" ? TOOLS.find((t) => t.name === name) : undefined;
}

/** The request kinds a set of capabilities allows. */
export function allowedKinds(capabilities: readonly string[]): RequestKind[] {
  return (Object.keys(REQUEST_KIND_CAPABILITY) as RequestKind[]).filter((k) => capabilities.includes(REQUEST_KIND_CAPABILITY[k]));
}

/** What a token is, as far as choosing its tools goes. `passcode` (0607): the caller has no key yet, so enter_passcode
 *  is offered; a caller that has a key or a session never needs it. */
export type ToolScope = { fleetBound?: boolean; passcode?: boolean };

/** The tools a principal can use, with submit_request's `kind` narrowed to the kinds it may ask for. A fleet-scoped
 *  tool is offered only to a token bound to one fleet: offering one the database will always refuse is a placebo. */
export function toolsFor(capabilities: readonly string[], scope: ToolScope = {}): ToolDef[] {
  const out: ToolDef[] = [];
  for (const t of TOOLS) {
    if (t.scope === "fleet" && !scope.fleetBound) continue;
    if (t.name === "enter_passcode" && !scope.passcode) continue;
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

/** A tool as a caller WITHOUT a key sees it (0607): a `session` argument first and required, since the session key that
 *  enter_passcode returns is the only credential such a caller has. The two public tools are left as they are. */
export function withSessionArg(t: ToolDef): ToolDef {
  if (t.public) return t;
  return {
    ...t,
    inputSchema: {
      ...t.inputSchema,
      properties: { session: SESSION_PROP, ...(t.inputSchema.properties ?? {}) },
      required: ["session", ...(t.inputSchema.required ?? [])],
    },
  };
}

/** The tools a caller without a key is offered (0607): welcome and enter_passcode, then what a passcode session can do,
 *  each with its `session` argument. The same for every such caller, so it may be cached publicly. */
export function passcodeTools(): ToolDef[] {
  const offered = toolsFor(PASSCODE_CAPABILITIES, { fleetBound: true, passcode: true });
  return PASSCODE_TOOL_NAMES.map((n) => offered.find((t) => t.name === n)).filter((t): t is ToolDef => !!t).map(withSessionArg);
}

/** A token's capabilities and fleet binding, read from a handshake (its data is whoami's). */
export function principalScope(outcome: EngineOutcome): { capabilities: string[]; fleetBound: boolean } {
  const data = isObject(outcome.data) ? outcome.data : {};
  const scope = isObject(data.scope) ? data.scope : {};
  return { capabilities: outcome.principal?.capabilities ?? [], fleetBound: isObject(scope.fleet_operator) };
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
  if (Array.isArray(value)) {
    if (schema.minItems !== undefined && value.length < schema.minItems) errs.push({ path, message: `must have at least ${schema.minItems} item${schema.minItems === 1 ? "" : "s"}` });
    if (schema.maxItems !== undefined && value.length > schema.maxItems) errs.push({ path, message: `must have at most ${schema.maxItems} items` });
    if (schema.items !== undefined) value.forEach((v, i) => errs.push(...validateAgainst(schema.items as JsonSchema, v, `${path}[${i}]`)));
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
  if (errors.length === 0 && (OWNER_COMMANDS as readonly string[]).includes(tool.name)) {
    // the rules the database also enforces, so an agent hears them before it asks
    if (tool.name === "hold_vehicle" && (value.until === undefined) === (value.for_minutes === undefined)) {
      errors.push({ path: "$.until", message: "give exactly one of until or for_minutes" });
    }
    if (tool.name === "request_service" && value.include_current_visit !== undefined && value.when !== "every_return") {
      errors.push({ path: "$.include_current_visit", message: "is only for when = every_return" });
    }
    if (value.expect_plan_hash !== undefined && value.mode === "preview") {
      errors.push({ path: "$.expect_plan_hash", message: "is for mode apply: it binds the apply to a plan a preview showed" });
    }
    if (Array.isArray(value.vehicles)) {
      const all = value.vehicles.filter((v) => typeof v === "string" && /^\s*(all|all cars|every car|fleet|my fleet)\s*$/i.test(v));
      if (all.length > 0 && value.vehicles.length > 1) errors.push({ path: "$.vehicles", message: "\"all\" stands alone: send \"all\" or a list of names" });
    }
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
    // 0607: the two doors a caller without a key may use
    { re: /^\/v1\/welcome$/, methods: { GET: "welcome" } },
    { re: /^\/v1\/passcode$/, methods: { POST: "enter_passcode" } },
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
    // 0605: an owner's agent, on its own cars
    { re: /^\/v1\/me\/fleet$/, methods: { GET: "my_fleet" } },
    { re: /^\/v1\/me\/vehicles\/([^/]+)$/, methods: { GET: "my_vehicle" }, keys: ["vehicle"] },
    { re: /^\/v1\/me\/settings$/, methods: { GET: "my_settings" } },
    { re: /^\/v1\/me\/commands$/, methods: { GET: "my_commands" } },
    { re: /^\/v1\/me\/commands\/([^/]+)$/, methods: { GET: "my_commands" }, keys: ["command_id"] },
    { re: /^\/v1\/me\/charge-limit$/, methods: { POST: "set_charge_limit" } },
    { re: /^\/v1\/me\/charge-limit\/clear$/, methods: { POST: "clear_charge_limit" } },
    { re: /^\/v1\/me\/services$/, methods: { POST: "request_service" } },
    { re: /^\/v1\/me\/services\/cancel$/, methods: { POST: "cancel_service" } },
    { re: /^\/v1\/me\/holds$/, methods: { POST: "hold_vehicle" } },
    { re: /^\/v1\/me\/holds\/release$/, methods: { POST: "release_hold" } },
    { re: /^\/v1\/me\/undo$/, methods: { POST: "undo_command" } },
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
    about: "Read the OTTOYARD twin depot and ASK for changes. A person approves or declines every request; OTTO-Q's own doors decide what can happen. A vehicle owner's token can also set what its own cars need (/v1/me/...), inside its contract, and OTTO-Q applies it at its next tick. Send Authorization: Bearer <key>. No key? GET /v1/welcome, then POST /v1/passcode with OTTOYARD's demo passcode for a session key.",
    documentation: "https://github.com/OTTOYARD/otto-q-core/blob/main/AGENT_GATEWAY.md",
    owner_guide: "https://github.com/OTTOYARD/otto-q-core/blob/main/PERSONAL_AGENT.md",
    mcp: `${baseUrl}/mcp`,
    //: 0660: the MCP address for an agent signed in to an owner's OTTOYARD account (OAuth 2.1; PERSONAL_AGENT.md section 10)
    mcp_signed_in: `${baseUrl}${ACCOUNT_MCP_PATH}`,
    openapi: `${baseUrl}/v1/openapi.json`,
    agent_card: `${baseUrl}/.well-known/agent-card.json`,
    endpoints: TOOLS.map((t) => ({ method: t.rest.method, path: t.rest.path, tool: t.name, capability: t.capability, title: t.title }))
      .concat([
        { method: "GET", path: "/v1/tools", tool: "tools_catalog", capability: null, title: "The tools your token may use, with JSON schemas" },
        { method: "POST", path: "/v1/ask", tool: "ask", capability: "read", title: "Ask OTTO-Command in plain English (an owner's token)" },
      ]),
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
  // A refused owner command was RECORDED (0605): its receipt -- the summary, the refusal, the command_id -- comes back
  // beside the error, so an agent can relay why in OTTO-Q's own words.
  const body = outcome.data !== undefined && outcome.data !== null ? { error: err, data: outcome.data, meta } : { error: err, meta };
  return { status: outcome.http_status, headers: errorHeaders(outcome.http_status, err.retry_after_s), body };
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
    const { capabilities, fleetBound } = principalScope(who);
    const tools = toolsFor(capabilities, { fleetBound }).map((t) => ({
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
  "A change you ask for with send_note or submit_request is a REQUEST: a person approves or declines it, and OTTO-Q's own " +
  "doors decide whether it can happen; never report one as done until list_requests shows status 'applied' with the " +
  "engine's reply. If your token belongs to a vehicle owner (whoami shows an owner block), the owner commands " +
  "(set_charge_limit, clear_charge_limit, request_service, cancel_service, hold_vehicle, release_hold, undo_command) set " +
  "what YOUR cars need: OTTO-Q checks each one against your contract and its own rules, applies it at its next tick, and " +
  "answers with a plain-English summary, a confirmation code and an OrchestrAV link to relay to your person. Such a change is done only when " +
  "its outcome is 'applied'; mode 'preview' shows the plan first. Nothing you send moves a car: OTTO-Q decides when and " +
  "where, and the car's own driving system moves it. Times named sim_* or marked 'sim time' are simulation time; " +
  "created_at and expires_at are real time (UTC), and *_local times are Nashville time.";

/** What a caller WITHOUT a key is told on connecting (0607): the welcome, and how the passcode and the session work. */
export const MCP_PASSCODE_INSTRUCTIONS =
  "You are connected to OTTOYARD: the agent door of OTTO-Q, the engine that orchestrates the OTTOYARD Nashville Flagship " +
  "depot's live digital twin. Start with the welcome tool. To read and adjust a fleet's cars you need OTTOYARD's demo " +
  "passcode: ask your person for it, then call enter_passcode with it and your own name. It answers with a session key: " +
  "send it as the `session` argument on every other tool, and never show it to anyone. OTTO-Q checks every change against " +
  "the owner's contract and its own rules. A change that does not fit comes back refused, with the reason in plain " +
  "English; one that fits comes back with a confirmation code and an OrchestrAV link: relay both to your person. Nothing " +
  "you send moves a car: OTTO-Q decides when and where, and the car's own driving system moves it. Everything set in a " +
  "session lasts until the demo run ends; a stop or reset of the twin ends the session too, and enter_passcode opens a " +
  "new one. Times marked 'sim time' are simulation time; 'CT' is Nashville real time.";

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

const mcpTool = (t: ToolDef) => ({
  name: t.name,
  title: t.title,
  description: t.description,
  inputSchema: t.inputSchema,
  annotations: { title: t.title, ...t.annotations },
});

/** The tools/list entries for a principal: name, title, description, inputSchema, annotations. */
export function mcpToolList(capabilities: readonly string[], scope: ToolScope = {}) {
  return toolsFor(capabilities, scope).map(mcpTool);
}

/** The tools/list a caller without a key gets (0607): the same for everyone. */
export function mcpPasscodeToolList() {
  return passcodeTools().map(mcpTool);
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

/** How a request without a key reaches the MCP endpoint (0607): `call` is bound to no key at all, and `bindSession` binds
 *  a call to the session key a tool's `session` argument carries. */
export type McpOptions = { anonymous?: boolean; bindSession?: (sessionKey: string) => Promise<EngineCall> };

const withoutSession = (args: unknown): unknown => {
  if (!isObject(args) || !("session" in args)) return args;
  const { session: _session, ...rest } = args;
  return rest;
};

/**
 * One POST to the MCP endpoint. Dual-era: a request carrying `_meta["io.modelcontextprotocol/protocolVersion"]` (or the
 * MCP-Protocol-Version header) of 2026-07-28 is served statelessly with the mirrored-header checks; `initialize` and
 * header-less requests are served as the negotiated initialize-based revision. No sessions are minted in either era.
 * 0607: with no Authorization header at all the endpoint is the passcode door: the welcome, enter_passcode, and every
 * other tool with its `session` argument. A session problem is then a tool result the agent can read and act on (call
 * enter_passcode again), never an HTTP 401 that a client could take as "this server needs OAuth".
 */
export async function handleMcp(req: { method: string; headers: HeaderGetter; bodyText: string }, call: EngineCall,
                                opts: McpOptions = {}): Promise<HttpOut> {
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
    if (opts.anonymous) return { status: 202, headers: {}, body: null };
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
  if (opts.anonymous) return mcpWithoutKey({ id, method: msg.method, params, modern, callMeta, serverInfo, call, bindSession: opts.bindSession });

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
      // The list varies by the token's capabilities and fleet, so it may be cached only for this token.
      const { capabilities, fleetBound } = principalScope(who);
      return reply(200, rpcResult(id, {
        ...modernFields,
        tools: mcpToolList(capabilities, { fleetBound }),
        ...(modern ? { ttlMs: 300_000, cacheScope: "private" } : {}),
      }));
    }
    case "tools/call": {
      const refusal = { ...callMeta, gateway_refusal: "invalid_arguments" };
      const tool = findTool(params.name);
      // 0607: a `session` argument means nothing beside a key in the Authorization header; it is dropped, not refused
      params.arguments = withoutSession(params.arguments);
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
        // A refused owner command carries its recorded receipt (0605): the agent relays the refusal in OTTO-Q's words.
        const failed: Record<string, unknown> = { error: outcome.error ?? { code: "error", message: "The request failed." }, call_id: outcome.call_id ?? null };
        if (outcome.data !== undefined && outcome.data !== null) failed.data = outcome.data;
        return reply(200, rpcResult(id, toolCallResult(modern, failed, true)));
      }
      return reply(200, rpcResult(id, toolCallResult(modern, outcome.data, false)));
    }
    default:
      return reply(modern ? 404 : 200, rpcError(id, JSONRPC.METHOD_NOT_FOUND, `Method not found: ${msg.method}`));
  }
}

/** The MCP endpoint for a caller with no key (0607). initialize, discovery, ping and tools/list need no database; a tool
 *  call reaches it through the same single door as every other call, bound to no key (welcome, enter_passcode) or to the
 *  session key the call carries. */
async function mcpWithoutKey(x: {
  id: RpcId; method: string; params: Record<string, unknown>; modern: boolean; callMeta: Record<string, unknown>;
  serverInfo: Record<string, string>; call: EngineCall; bindSession?: (sessionKey: string) => Promise<EngineCall>;
}): Promise<HttpOut> {
  const reply = (status: number, body: unknown): HttpOut => ({ status, headers: JSON_HEADERS, body });
  const modernFields = x.modern ? { resultType: "complete" } : {};
  const result = (data: unknown, isError: boolean) => reply(200, rpcResult(x.id, toolCallResult(x.modern, data, isError)));
  const failed = (r: EngineOutcome) => {
    const out: Record<string, unknown> = { error: r.error ?? { code: "error", message: "The request failed." }, call_id: r.call_id ?? null };
    if (r.data !== undefined && r.data !== null) out.data = r.data;
    return result(out, true);
  };
  switch (x.method) {
    case "initialize": {
      const legacy = MCP_SUPPORTED_VERSIONS.filter((v) => v !== MCP_MODERN_VERSION) as string[];
      const requested = typeof x.params.protocolVersion === "string" ? x.params.protocolVersion : null;
      return reply(200, rpcResult(x.id, {
        protocolVersion: requested !== null && legacy.includes(requested) ? requested : legacy[0],
        capabilities: { tools: { listChanged: false } },
        serverInfo: x.serverInfo,
        instructions: MCP_PASSCODE_INSTRUCTIONS,
      }));
    }
    case "server/discover":
      return reply(200, rpcResult(x.id, {
        resultType: "complete",
        supportedVersions: [...MCP_SUPPORTED_VERSIONS],
        capabilities: { tools: { listChanged: false } },
        _meta: { "io.modelcontextprotocol/serverInfo": x.serverInfo },
        instructions: MCP_PASSCODE_INSTRUCTIONS,
        ttlMs: 3_600_000,
        cacheScope: "public",
      }));
    case "ping":
      return reply(200, rpcResult(x.id, { ...modernFields }));
    case "tools/list":
      if (x.params.cursor !== undefined) return reply(200, rpcError(x.id, JSONRPC.INVALID_PARAMS, "Invalid cursor: every tool is returned on one page."));
      return reply(200, rpcResult(x.id, {
        ...modernFields,
        tools: mcpPasscodeToolList(),
        ...(x.modern ? { ttlMs: 300_000, cacheScope: "public" } : {}),
      }));
    case "tools/call": {
      const refusal = { ...x.callMeta, gateway_refusal: "invalid_arguments" };
      const tool = findTool(x.params.name);
      if (!tool) return reply(200, rpcError(x.id, JSONRPC.INVALID_PARAMS, `Unknown tool: ${String(x.params.name)}. Start with welcome.`));
      const raw = x.params.arguments === undefined ? {} : x.params.arguments;
      if (tool.public) {
        const v = validateToolArgs(tool, raw);
        if (!v.ok) {
          const r = await x.call(tool.name, {}, refusal);
          if (r.http_status >= 502) return engineFailure(x.id, r);
          return result({ error: { code: "invalid_arguments", message: "The arguments are not valid.", details: v.errors }, call_id: r.call_id ?? null }, true);
        }
        const out = await x.call(tool.name, v.value, x.callMeta);
        if (out.http_status >= 502) return engineFailure(x.id, out);
        return out.ok ? result(out.data, false) : failed(out);
      }
      const session = isObject(raw) ? raw.session : undefined;
      if (typeof session !== "string" || !SESSION_PATTERN.test(session) || !x.bindSession) {
        // asked of the database with no key, so the attempt is ledgered and the answer is its own: connect first
        const r = await x.call(tool.name, {}, refusal);
        if (r.http_status >= 502) return engineFailure(x.id, r);
        if (typeof session === "string" && session !== "" && !SESSION_PATTERN.test(session)) {
          return result({ error: { code: "invalid_session", message: "That is not a session key OTTOYARD issues (oqs_ and 64 hex). Call enter_passcode for a new one." }, call_id: r.call_id ?? null }, true);
        }
        return failed(r);
      }
      const bound = await x.bindSession(session);
      const v = validateToolArgs(tool, withoutSession(raw));
      if (!v.ok) {
        const r = await bound(tool.name, {}, refusal);
        if (r.http_status >= 502) return engineFailure(x.id, r);
        if (isRefusalOtherThanArguments(r)) return failed(r);
        return result({ error: { code: "invalid_arguments", message: "The arguments are not valid.", details: v.errors }, call_id: r.call_id ?? null }, true);
      }
      const out = await bound(tool.name, v.value, x.callMeta);
      if (out.http_status >= 502) return engineFailure(x.id, out);
      return out.ok ? result(out.data, false) : failed(out);
    }
    default:
      return reply(x.modern ? 404 : 200, rpcError(x.id, JSONRPC.METHOD_NOT_FOUND, `Method not found: ${x.method}`));
  }
}

// ─────────────────────────────────────────────────────────────────────────────────────────────── A2A ──

/** A2A 1.0 Agent Card for DISCOVERY. The gateway does not implement A2A's SendMessage/Task operations; its two
 *  interfaces are declared as custom bindings (MCP Streamable HTTP and the REST API), which A2A allows by URI. */
export function agentCard(baseUrl: string) {
  return {
    name: GATEWAY_TITLE,
    description:
      "Read the OTTOYARD Nashville Flagship twin depot through OTTO-Q, and ask for changes. A change to the depot is a " +
      "request a person approves or declines; OTTO-Q's own doors decide what can happen. A vehicle owner's agent can also " +
      "set what its own cars need (charge limit, services, holds), inside its contract, applied at OTTO-Q's next tick and " +
      "never moving a car. Any agent can start with the welcome tool: OTTOYARD's demo passcode (enter_passcode) opens a " +
      "session on a fleet's cars until the demo run ends. Discovery card only: the gateway speaks MCP, a REST API " +
      "(OpenAPI at /v1/openapi.json) and a plain-English door (POST /v1/ask), not A2A task messaging.",
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
          bearerFormat: "opaque: oqa_ or oqs_ + 64 hex",
          description: "An agent key issued by ottoq_agent_issue_token (oqa_), or a passcode session key from enter_passcode (oqs_, which also travels as a tool's `session` argument over MCP). Its scope (depot, fleet, capabilities) is fixed at issue and enforced by the database. welcome and enter_passcode need neither.",
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

// ─────────────────────────────────────────────────────────────────────────────────────────── OpenAPI ──

/** The REST table's second routes for a tool, beside the tool's own path. */
const EXTRA_REST_PATHS: ReadonlyArray<{ tool: string; path: string }> = [
  { tool: "list_requests", path: "/v1/requests/{request_id}" },
  { tool: "my_commands", path: "/v1/me/commands/{command_id}" },
];

const ERROR_RESPONSES: Record<string, string> = {
  "400": "The arguments are not valid; error.details names each problem.",
  "401": "No key, or an unknown or revoked one, or a passcode session that ended with its demo run or expired.",
  "403": "The key lacks the capability, or is not bound to a fleet; or (enter_passcode) the passcode is not right.",
  "404": "Not found, or outside the token's scope: the two read the same.",
  "409": "A conflict with the request's current state (a request already decided).",
  "422": "Refused. For an owner command OTTO-Q RECORDED the refusal and changed nothing; data carries the receipt with the reason. Also: an idempotency key reused for a different command.",
  "429": "Over the key's rate limit (see Retry-After), too many requests awaiting a decision, or too many wrong passcodes.",
  "503": "OTTO-Q could not be reached, this part of the gateway is not switched on yet, or the demo passcode is off.",
};

const ref = (name: string) => ({ $ref: `#/components/schemas/${name}` });
const errorResponses = () => Object.fromEntries(Object.entries(ERROR_RESPONSES).map(([code, description]) =>
  [code, { description, content: { "application/json": { schema: ref("Error") } } }]));

function openApiOperation(t: ToolDef, path: string): Record<string, unknown> {
  const keys = [...path.matchAll(/\{(\w+)\}/g)].map((m) => m[1]);
  const props = t.inputSchema.properties ?? {};
  const required = t.inputSchema.required ?? [];
  const parameters: Record<string, unknown>[] = keys.map((k) => ({
    name: k, in: "path", required: true, description: props[k]?.description, schema: props[k] ?? { type: "string" },
  }));
  const op: Record<string, unknown> = {
    operationId: path === t.rest.path ? t.name : `${t.name}_by_${keys.join("_")}`,
    summary: t.title,
    description: t.description,
    tags: [t.tags[0]],
    "x-ottoq-tool": t.name,
    "x-ottoq-capability": t.capability,
    "x-ottoq-effect": t.effect,
    ...(t.scope ? { "x-ottoq-scope": t.scope } : {}),
    // 0607: the two doors a caller without a key uses
    ...(t.public ? { security: [] } : {}),
  };
  if (t.rest.method === "GET") {
    for (const [k, schema] of Object.entries(props)) {
      if (!keys.includes(k)) parameters.push({ name: k, in: "query", required: required.includes(k), description: schema.description, schema });
    }
  } else {
    const bodyProps = Object.fromEntries(Object.entries(props).filter(([k]) => !keys.includes(k)));
    const bodyRequired = required.filter((k) => !keys.includes(k));
    op.requestBody = {
      required: bodyRequired.length > 0,
      content: { "application/json": { schema: { type: "object", additionalProperties: false, properties: bodyProps, ...(bodyRequired.length ? { required: bodyRequired } : {}) } } },
    };
    if ("idempotency_key" in props) {
      parameters.push({ name: "Idempotency-Key", in: "header", required: false, description: "The same as the idempotency_key argument; the body's wins when both are sent.", schema: props.idempotency_key });
    }
  }
  if (parameters.length) op.parameters = parameters;
  const okStatus = t.effect === "read" ? "200" : "201";
  const dataSchema = t.effect === "owner_setting" ? ref("OwnerReceipt") : {};
  op.responses = {
    [okStatus]: { description: t.effect === "read" ? "The answer." : "Recorded.", content: { "application/json": { schema: { allOf: [ref("Ok"), { type: "object", properties: { data: dataSchema } }] } } } },
    ...(t.effect !== "read" && t.effect !== "session" ? { "200": { description: "A duplicate (the same idempotency key), or an owner command that previewed or changed nothing.", content: { "application/json": { schema: ref("Ok") } } } } : {}),
    ...errorResponses(),
  };
  return op;
}

/** OpenAPI 3.1 for the REST API, generated from the same catalog MCP serves, so the two cannot drift. Public, like the
 *  agent card: it describes the door, not what any token may see. */
export function openApiDocument(baseUrl: string) {
  const paths: Record<string, Record<string, unknown>> = {};
  const add = (t: ToolDef, path: string) => { (paths[path] ??= {})[t.rest.method.toLowerCase()] = openApiOperation(t, path); };
  for (const t of TOOLS) add(t, t.rest.path);
  for (const extra of EXTRA_REST_PATHS) {
    const t = findTool(extra.tool);
    if (t) add(t, extra.path);
  }
  paths["/v1/tools"] = { get: {
    operationId: "tools_catalog", summary: "The tools your token may use", tags: ["identity"],
    description: "Each tool your token may use, with its REST method and path and its JSON input schema.",
    responses: { "200": { description: "The catalog.", content: { "application/json": { schema: ref("Ok") } } }, ...errorResponses() },
  } };
  paths["/v1/ask"] = { post: {
    operationId: "ask", summary: "Ask OTTO-Command in plain English", tags: ["owner"],
    description: "For an owner's token. Send your person's words; OTTO-Command reads them, calls the owner tools with YOUR token (so it can do nothing your token could not), and answers in plain English with OTTO-Q's receipts and the OrchestrAV link. dry_run runs every change as a preview, enforced in code. To apply a previewed plan exactly, send the confirm objects it returned (no model is involved).",
    requestBody: { required: true, content: { "application/json": { schema: ref("AskRequest") } } },
    responses: { "200": { description: "The answer.", content: { "application/json": { schema: ref("AskResponse") } } }, ...errorResponses() },
  } };
  return {
    openapi: "3.1.0",
    jsonSchemaDialect: "https://json-schema.org/draft/2020-12/schema",
    info: {
      title: GATEWAY_TITLE,
      version: GATEWAY_VERSION,
      summary: "Read the OTTOYARD twin depot through OTTO-Q; ask for changes; set what your own cars need. No key? GET /v1/welcome, then POST /v1/passcode.",
      description: "Generated from the gateway's tool catalog, the same one its MCP endpoint serves. Every call is answered by the database, which resolves the token, rate-limits it, checks its capability and scope, and writes the call ledger.",
    },
    servers: [{ url: baseUrl }],
    security: [{ agentToken: [] }],
    tags: [...new Set(TOOLS.map((t) => t.tags[0]))].map((name) => ({ name })),
    paths,
    components: {
      securitySchemes: {
        agentToken: { type: "http", scheme: "bearer", bearerFormat: "oqa_ or oqs_ + 64 hex", description: "An agent key issued by ottoq_agent_issue_token (oqa_), or a passcode session key from POST /v1/passcode (oqs_; it ends with the demo run). Its depot, fleet and capabilities are fixed at issue and enforced by the database." },
      },
      schemas: {
        Meta: { type: "object", properties: {
          tool: { type: ["string", "null"] }, call_id: { type: ["integer", "null"], description: "This call's row in the gateway's call ledger." },
          principal: { type: ["object", "null"], properties: { name: { type: "string" }, kind: { type: "string" } } },
        } },
        Ok: { type: "object", required: ["data", "meta"], properties: { data: {}, meta: ref("Meta") } },
        Error: { type: "object", required: ["error", "meta"], properties: {
          error: { type: "object", required: ["code", "message"], properties: {
            code: { type: "string" }, message: { type: "string" }, hint: { type: "string" }, retry_after_s: { type: "integer" },
            details: { type: "array", items: { type: "object", properties: { path: { type: "string" }, message: { type: "string" } } } },
          } },
          data: { description: "For a refused owner command: its recorded receipt (OwnerReceipt)." },
          meta: ref("Meta"),
        } },
        OwnerReceipt: { type: "object", required: ["outcome", "summary", "command"], properties: {
          outcome: { type: "string", enum: OWNER_OUTCOMES },
          duplicate: { type: "boolean", description: "true when this answers a resent idempotency key." },
          summary: { type: "string", description: "OTTO-Q's plain-English account of what changed, or why not. Relay it." },
          link: { type: "string", format: "uri", description: "Where to see it in OrchestrAV." },
          refusal: { type: "object", properties: { code: { type: "string" }, message: { type: "string" }, hint: { type: "string" } } },
          command: { type: "object", description: "The recorded command: command_id, tool, mode, outcome, cars, vehicles, effects (per car: before, after, now), args, plan_hash, sim_clock, created_at, undone_at, lifted_at." },
          confirm: { type: "object", description: "After a preview: the exact tool and arguments that apply this plan.", properties: { tool: { type: "string" }, args: { type: "object" } } },
          undo: { type: "object", description: "After an apply: the call that reverses it.", properties: { tool: { type: "string" }, args: { type: "object" } } },
          expires: { type: "string" },
        } },
        AskRequest: askInputSchema(),
        AskResponse: { type: "object", required: ["data", "meta"], properties: {
          data: { type: "object", properties: {
            answer: { type: "string", description: "Plain English, ready to forward." },
            answered_by: { type: "string" },
            dry_run: { type: "boolean" },
            actions: { type: "array", description: "Each command made, with OTTO-Q's receipt. The authoritative record of what changed.", items: { type: "object" } },
            reads: { type: "array", items: { type: "string" } },
            link: { type: ["string", "null"], description: "The OrchestrAV link to open." },
            incomplete: { type: "boolean", description: "true when OTTO-Command could not finish its reply; actions still says what was done." },
          } },
          meta: ref("Meta"),
        } },
      },
    },
  };
}

// ─────────────────────────────────────────────────────────────────────────────────────────── POST /v1/ask ──

export const ASK_MAX_TEXT = 2000;
export const ASK_MAX_HISTORY = 12;
export const ASK_MAX_CONFIRMS = 10;

/** POST /v1/ask's body. One schema for the door's own check and for the OpenAPI document. */
export function askInputSchema(): JsonSchema {
  return {
    type: "object", additionalProperties: false,
    properties: {
      text: { type: "string", minLength: 1, maxLength: ASK_MAX_TEXT, description: "Your person's words, as they said them." },
      dry_run: { type: "boolean", description: "Every change runs as a preview and nothing is applied. Enforced in code, not in the prompt." },
      history: {
        type: "array", maxItems: ASK_MAX_HISTORY, description: "Earlier turns of this conversation, oldest first.",
        items: {
          type: "object", additionalProperties: false, required: ["role", "text"],
          properties: { role: { type: "string", enum: ["user", "assistant"] }, text: { type: "string", minLength: 1, maxLength: ASK_MAX_TEXT * 2 } },
        },
      },
      confirm: {
        type: "array", minItems: 1, maxItems: ASK_MAX_CONFIRMS,
        description: "Instead of text: the confirm objects a dry run returned. Each is applied exactly as previewed, with no model involved.",
        items: {
          type: "object", additionalProperties: false, required: ["tool", "args"],
          properties: {
            tool: { type: "string", enum: OWNER_COMMANDS },
            args: { type: "object" },
            note: { type: "string", maxLength: 500, description: "The preview's own note; sent back as it came, and ignored." },
          },
        },
      },
      idempotency_key: {
        type: "string", pattern: "^[A-Za-z0-9._:-]{1,60}$",
        description: "Resend the same ask with the same key and each command it makes replays its first receipt instead of acting twice.",
      },
    },
  };
}

/** What the gateway hands its plain-English door: the authenticated handshake (whoami), the engine call already bound to
 *  the caller's token hash (transport 'ask'), and the body. The door itself is injected (./ottocommand_owner.ts), so this
 *  file holds no model code and a test can stand one in. */
export type AskContext = { who: EngineOutcome; call: EngineCall; bodyText: string; headers: HeaderGetter };
export type AskHandler = (ctx: AskContext) => Promise<HttpOut>;

/** POST /v1/ask: authenticate first (an unknown token learns nothing, not even whether the door is switched on), then
 *  hand over to the injected door. */
export async function handleAsk(req: { method: string; headers: HeaderGetter; bodyText: string }, call: EngineCall,
                                ask: AskHandler | null | undefined): Promise<HttpOut> {
  if (req.method.toUpperCase() !== "POST") {
    return { status: 405, headers: { Allow: "POST" }, body: { error: { code: "method_not_allowed", message: "Use POST." }, meta: { tool: "ask", call_id: null } } };
  }
  const who = await call("handshake", {}, {});
  if (!who.ok) return restResponse(who);
  if (!ask) {
    return { status: 503, headers: {}, body: { error: { code: "ask_not_configured",
      message: "The plain-English door is built but not switched on: the gateway has no model configured. Every tool works directly over MCP and REST." },
      meta: { tool: "ask", call_id: who.call_id ?? null } } };
  }
  return ask({ who, call, bodyText: req.bodyText, headers: req.headers });
}

// ───────────────────────────────────────────────────────────────────────────── the engine, over PostgREST ──

/** One call into the database: token hash, tool, validated arguments, transport, and small request metadata. */
export type EngineRpc = (
  /** null: the caller sent no key (0607's welcome and enter_passcode, and the database's "connect first" answer). */
  tokenHash: string | null,
  tool: string,
  args: Record<string, unknown>,
  transport: "rest" | "mcp" | "ask",
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
        message: "Agent access is built but not enabled yet: its database half (migration 0559) is not applied." } };
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
  /** POST /v1/ask's plain-English door (./ottocommand_owner.ts). Absent or null: the door answers 503 ask_not_configured. */
  ask?: AskHandler | null;
  /** 0660: OTTOYARD sign-in (./agent_signin.ts): the OAuth endpoints and the signed-in MCP address. Absent: those paths
   *  answer 404 and /account/mcp refuses every request. */
  signin?: { config: SigninConfig; rpc: OAuthRpc | null } | null;
};

export const CORS_ALLOW_HEADERS = "authorization, content-type, idempotency-key, mcp-protocol-version, mcp-method, mcp-name";
const CORS_EXPOSE_HEADERS = "www-authenticate, retry-after, x-ottoq-gateway";
const CARD_PATHS = new Set(["/.well-known/agent-card.json", "/.well-known/agent.json"]);
const OPENAPI_PATH = "/v1/openapi.json";

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
 *   1. the public discovery documents (agent card, OpenAPI, endpoint index) -- no token, no database;
 *   2. the Origin check (a browser origin not on the list is refused; agents send none);
 *   3. a well-formed Bearer key or session key, or 401 before the database is asked -- except (0607) a request with no
 *      Authorization header at all to the MCP endpoint, GET /v1/welcome or POST /v1/passcode: the passcode door;
 *   4. a bounded body (64 KiB);
 *   5. the token's SHA-256 -- the raw token never leaves this function -- and then REST, MCP or the plain-English door,
 *      each of which asks the database, which resolves the principal, rate-limits, checks the capability and writes
 *      the call ledger. The plain-English door reaches the engine only through that same call, with the same token.
 * 0660: the sign-in endpoints (/oauth/*, the protected-resource metadata) come first, open to any origin (they carry
 * no ambient credentials); the signed-in MCP address (/account/mcp) takes only an access token, and answers anything
 * else with a 401 that tells an MCP client where to sign in (RFC 9728).
 */
export async function handleGatewayRequest(req: Request, opts: GatewayOptions): Promise<Response> {
  const url = new URL(req.url);
  const rawPath = gatewayPath(url.pathname);
  const path = rawPath.length > 1 ? rawPath.replace(/\/+$/, "") : rawPath;
  const method = req.method.toUpperCase();
  const origin = req.headers.get("origin");
  const isAccountMcp = path === ACCOUNT_MCP_PATH;
  const isMcp = path === "/mcp" || isAccountMcp;
  const isAsk = path === "/v1/ask";
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
    // 0. OTTOYARD sign-in (0660): its documents and endpoints, before the Origin and key checks
    if (isSigninPath(path)) {
      if (!opts.signin) return refuse(404, "not_found", "Sign-in is not configured on this gateway.");
      const userAgent = req.headers.get("user-agent");
      return await handleSignin(req, path, opts.signin.config, opts.signin.rpc, {
        http_method: method, path: path.slice(0, 200), ip: firstForwardedFor(req.headers.get("x-forwarded-for")),
        ...(userAgent ? { client: userAgent.slice(0, 120) } : {}) });
    }

    // 1. public discovery
    if (CARD_PATHS.has(path) || path === OPENAPI_PATH) {
      const pub = { "Access-Control-Allow-Origin": "*" };
      if (method === "OPTIONS") return toResponse({ status: 204, headers: { ...pub, "Access-Control-Allow-Methods": "GET, OPTIONS", Allow: "GET, HEAD, OPTIONS" }, body: null });
      if (method !== "GET" && method !== "HEAD") return toResponse({ status: 405, headers: { Allow: "GET, HEAD, OPTIONS" }, body: { error: { code: "method_not_allowed", message: "Use GET." } } });
      const doc = path === OPENAPI_PATH ? openApiDocument(opts.publicUrl) : agentCard(opts.publicUrl);
      const res = toResponse({ status: 200, headers: { ...pub, "Cache-Control": "public, max-age=300" }, body: doc });
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

    // 3. a well-formed key, before anything else is read -- or (0607) no Authorization header at all, which only the
    //    passcode door accepts: the MCP endpoint (welcome, enter_passcode, tools with a `session` argument), GET
    //    /v1/welcome and POST /v1/passcode
    const authorization = req.headers.get("authorization");
    const anonymous = authorization === null || authorization.trim() === "";
    const token = anonymous ? null : bearerToken(authorization);
    const passcodeRoute = !isMcp && !isAsk && (() => { const r = routeRest(method, path); return "tool" in r && (r.tool === "welcome" || r.tool === "enter_passcode"); })();
    //: 0660: the signed-in MCP address takes only an access token; anything else is sent to sign in (RFC 9728 5.1)
    if (isAccountMcp && (anonymous || token === null || !ACCESS_TOKEN_PATTERN.test(token))) {
      return refuse(401, anonymous ? "sign_in_required" : "invalid_token",
        anonymous
          ? "Sign in to OTTOYARD: this address is for an agent signed in to an owner's account. Your MCP client finds the sign-in from this response's WWW-Authenticate header (OAuth 2.1, device code or browser)."
          : "That is not an OTTOYARD access token. Sign in again, or refresh the token.",
        { "WWW-Authenticate": accountChallenge(opts.publicUrl, !anonymous) });
    }
    if (anonymous ? !(isMcp || passcodeRoute) : token === null || !isWellFormedToken(token)) {
      return refuse(401, "unauthenticated",
        "Send Authorization: Bearer <agent key or session key>. No key? GET /v1/welcome, then POST /v1/passcode with OTTOYARD's demo passcode for a session key (over MCP, call welcome and enter_passcode).",
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
    const tokenHash = token === null ? null : await sha256Hex(token);
    const userAgent = req.headers.get("user-agent");
    const baseMeta: Record<string, unknown> = {
      http_method: method,
      path: path.slice(0, 200),
      ip: firstForwardedFor(req.headers.get("x-forwarded-for")),
      client: userAgent ? userAgent.slice(0, 120) : undefined,
    };
    const callFor = (hash: string | null): EngineCall => (tool, args, meta) => {
      const merged: Record<string, unknown> = { ...baseMeta };
      for (const [k, v] of Object.entries(meta)) if (v !== undefined && v !== null && v !== "") merged[k] = v;
      for (const k of Object.keys(merged)) if (merged[k] === undefined) delete merged[k];
      return engine(hash, tool, args, isMcp ? "mcp" : isAsk ? "ask" : "rest", merged);
    };
    const call = callFor(tokenHash);
    // a session key a tool call carries as its `session` argument is hashed here like a header key: it never leaves
    const bindSession = async (sessionKey: string) => callFor(await sha256Hex(sessionKey));
    const out = isMcp
      ? await handleMcp({ method, headers: req.headers, bodyText }, call, isAccountMcp ? {} : { anonymous, bindSession })
      : isAsk
        ? await handleAsk({ method, headers: req.headers, bodyText }, call, opts.ask)
        : await handleRest({ method, path, query: url.searchParams, headers: req.headers, bodyText }, call);
    //: 0660: an expired or disconnected access token on the signed-in address: tell the client to refresh or sign in again
    if (isAccountMcp && out.status === 401) out.headers = { ...out.headers, "WWW-Authenticate": accountChallenge(opts.publicUrl, true) };
    return toResponse(out, cors);
  } catch (e) {
    console.error(`${GATEWAY_NAME}: unhandled`, (e as Error)?.name ?? "error", (e as Error)?.message?.slice(0, 200) ?? "");
    return refuse(500, "internal_error", "The gateway hit an internal error.");
  }
}
