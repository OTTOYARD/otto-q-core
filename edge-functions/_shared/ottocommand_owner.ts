/**
 * OTTO-Command's owner door: POST /v1/ask on the ottoq-agent-gateway (db/migrations/0605, PERSONAL_AGENT.md).
 *
 * An owner's agent (Chase's Hermes, first) sends its person's words. OTTO-Command reads them, calls the owner tools,
 * and answers in plain English with OTTO-Q's own receipts and the OrchestrAV link, ready to forward.
 *
 * WHY THIS LIVES IN THE GATEWAY AND NOT IN ottoq-ottocommand. That function runs with the service-role key and calls
 * the engine's doors directly. This one is handed exactly one way into OTTO-Q, `call`, which the gateway has already
 * bound to THIS caller's token hash: every tool OTTO-Command uses goes through public.ottoq_agent_call, which resolves
 * the principal, rate-limits it, checks capability and fleet scope, runs the tool, and ledgers the call with transport
 * 'ask'. So a model that misreads the owner -- or is talked into something -- can do nothing the owner's token could
 * not do over MCP or REST. The safety envelope is the database's (0605 §3), not this prompt's.
 *
 * WHAT CODE ENFORCES HERE, NOT THE PROMPT:
 *   * dry_run: every command goes out with mode 'preview', whatever the model asked for;
 *   * the tool set: the owner reads and commands this token may use (toolsFor), nothing else;
 *   * arguments: validated against the same schemas MCP and REST use before the engine is asked;
 *   * the owner's own words travel as each command's note, so its receipt and OrchestrAV show what was asked;
 *   * idempotency: resent with the same idempotency_key, an ask replays each command it makes (one key per command,
 *     derived from the ask's key and the command's content, so a different command can never collide with it);
 *   * a bounded loop: at most ASK_MAX_ROUNDS model turns inside a wall-clock budget;
 *   * the answer never claims a change that did not happen: "Done" with nothing applied is replaced by the receipts,
 *     and an applied change always carries its OrchestrAV link;
 *   * confirm: a previewed plan is applied from its confirm objects with NO model involved.
 *
 * Pure apart from the injected model call: no Deno, no database. tests/owner_agent.test.mjs drives it with a scripted
 * model and, when a scratch PostgreSQL is reachable, against the real 0605 SQL.
 *
 * Anthropic Messages API, read 2026-10-03: tool use (tool_use blocks in, tool_result blocks back in a user turn) and
 * prompt caching -- the prefix is built "tools -> system -> messages", a system text block takes
 * "cache_control": {"type": "ephemeral"}, and the default lifetime is 5 minutes
 * (https://platform.claude.com/docs/en/build-with-claude/prompt-caching). The tools and the system prompt here are the
 * same for every round of an ask and every ask by an owner, so they are what is cached; the owner's context and words
 * ride in the messages.
 */

import {
  ASK_MAX_TEXT,
  askInputSchema,
  isTransportFailure,
  OWNER_COMMANDS,
  OWNER_READS,
  principalScope,
  sha256Hex,
  toolsFor,
  validateAgainst,
  validateToolArgs,
} from "./agent_gateway.ts";
import type { AskHandler, EngineCall, EngineOutcome, HttpOut, JsonSchema, ToolDef, ValidationError } from "./agent_gateway.ts";

export const ANSWERED_BY = "OTTO-Command";
export const ASK_MAX_ROUNDS = 6;
export const ASK_BUDGET_MS = 100_000;
export const ASK_MAX_TOKENS = 1200;
/** A tool result longer than this is cut before the model reads it (a 36-car fleet is about 18 KB). */
export const TOOL_RESULT_MAX_CHARS = 30_000;
export const ANTHROPIC_MESSAGES_URL = "https://api.anthropic.com/v1/messages";
export const ANTHROPIC_VERSION = "2023-06-01";

const OWNER_TOOL_NAMES: ReadonlySet<string> = new Set<string>([...OWNER_READS, ...OWNER_COMMANDS]);
const COMMAND_NAMES: ReadonlySet<string> = new Set<string>(OWNER_COMMANDS);
/** Arguments the door, not the model, decides: the owner's words go in as the note, the key is derived, and a plan hash
 *  only ever comes from a preview's confirm. */
const RUNNER_ARGS = ["note", "idempotency_key", "expect_plan_hash"] as const;

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);

// ───────────────────────────────────────────────────────────────────────────────────────── the model ──

export type ModelBlock =
  | { type: "text"; text: string }
  | { type: "tool_use"; id: string; name: string; input: unknown };
export type ToolResultBlock = { type: "tool_result"; tool_use_id: string; content: string; is_error?: boolean };
export type ModelMessage =
  | { role: "user"; content: string | ToolResultBlock[] }
  | { role: "assistant"; content: string | ModelBlock[] };
export type ModelTool = { name: string; description: string; input_schema: JsonSchema };
export type ModelRequest = { system: string; tools: ModelTool[]; messages: ModelMessage[]; max_tokens: number };
export type ModelReply =
  | { ok: true; content: ModelBlock[]; stop_reason: string }
  | { ok: false; status: number; message: string };
export type ModelCall = (req: ModelRequest) => Promise<ModelReply>;

/** The Anthropic Messages API as a ModelCall. The model name comes from the deployment's environment. */
export function anthropicModel(o: { apiKey: string; model: string; fetchImpl?: typeof fetch; timeoutMs?: number }): ModelCall {
  const doFetch = o.fetchImpl ?? fetch;
  return async (req) => {
    let res: Response;
    try {
      res = await doFetch(ANTHROPIC_MESSAGES_URL, {
        method: "POST",
        headers: { "content-type": "application/json", "x-api-key": o.apiKey, "anthropic-version": ANTHROPIC_VERSION },
        body: JSON.stringify({
          model: o.model,
          max_tokens: req.max_tokens,
          system: [{ type: "text", text: req.system, cache_control: { type: "ephemeral" } }],
          tools: req.tools,
          messages: req.messages,
        }),
        signal: AbortSignal.timeout(o.timeoutMs ?? 45_000),
      });
    } catch (e) {
      const name = (e as { name?: string } | null)?.name;
      return { ok: false, status: name === "TimeoutError" || name === "AbortError" ? 504 : 503, message: "The language model could not be reached." };
    }
    let body: unknown = null;
    try { body = await res.json(); } catch { body = null; }
    if (!res.ok || !isObject(body) || !Array.isArray(body.content)) {
      const err = isObject(body) && isObject(body.error) && typeof body.error.message === "string" ? body.error.message : `HTTP ${res.status}`;
      return { ok: false, status: res.status, message: `The language model refused the request: ${err.slice(0, 200)}` };
    }
    const content: ModelBlock[] = [];
    for (const b of body.content) {
      if (isObject(b) && b.type === "text" && typeof b.text === "string") content.push({ type: "text", text: b.text });
      else if (isObject(b) && b.type === "tool_use" && typeof b.id === "string" && typeof b.name === "string") {
        content.push({ type: "tool_use", id: b.id, name: b.name, input: b.input });
      }
    }
    return { ok: true, content, stop_reason: typeof body.stop_reason === "string" ? body.stop_reason : "" };
  };
}

// ──────────────────────────────────────────────────────────────────────────────────────── the prompt ──

/** The same for every owner and every ask, so it caches. Nothing in it is a fact about a car: those come from tools. */
export const SYSTEM_PROMPT = [
  "You are OTTO-Command, the voice of OTTO-Q, the orchestration engine at the OTTOYARD Nashville Flagship depot, which runs as a digital twin. You are answering a vehicle owner's personal AI agent, which forwards your answer to the owner, usually on a phone.",
  "",
  "What you can do, only through your tools:",
  "- Read the owner's own cars: my_fleet (start here for anything about \"my cars\" or \"the fleet\"), my_vehicle (one car), my_settings (what is in force), my_commands (what was asked before, with command ids).",
  "- Change what the owner's cars NEED, inside the owner's contract: set_charge_limit and clear_charge_limit (how full they charge), request_service and cancel_service (work done at the depot), hold_vehicle and release_hold (not before a time), undo_command.",
  "",
  "What you cannot do, and must say plainly when asked: move or drive a car, pick its route, stall, charger or place in line (OTTO-Q decides when and where, and the car's own driving system moves it), lock or unlock it, touch another owner's cars, or change anything when no demo run is live. Offer the nearest thing you can do, such as a hold instead of \"keep it parked\".",
  "",
  "How to answer:",
  "1. Facts come only from tool results. Never invent a car, a number, a time or a setting. If the owner names a car that does not exist, the tool refuses and lists the real names: say so.",
  "2. A change is done only when its tool returns outcome \"applied\". Then begin with \"Done.\", give OTTO-Q's own summary from the receipt (shorten it, never contradict it), and end with the receipt's confirmation code and its OrchestrAV link. \"refused\": say it was not done, why, in one sentence, and what is allowed instead. \"no_change\": it was already so. \"previewed\": nothing has changed yet.",
  "3. When the owner's words clearly name a change, make it; do not ask for confirmation. If they ask to see it first (\"what would happen if\", \"preview\", \"before you do it\"), send mode \"preview\" and say nothing has changed.",
  "4. When a request is truly ambiguous (which service, which car, until when), ask one short question instead of guessing.",
  "5. Words to tools: \"service bay\", \"maintenance\", \"have a tech look at it\" -> mechanical_pm. \"wash\", \"external cleaning\", \"exterior cleaning\" -> exterior_wash. \"detail\", \"deep clean\" -> interior_deep_clean. \"quick clean\", \"tidy\" -> interior_tidy. \"lost item\", \"left my bag\" -> item_retrieval. \"update\" -> software_update. \"clean the sensors or cameras\" -> sensor_clean. \"calibrate\" -> sensor_calibration. \"after charging\": OTTO-Q always plans bay work after the charge, so request the service with when \"now\". \"every time it comes back\", \"always\", \"from now on\" -> when \"every_return\". \"next time\" -> \"next_return\". \"all my cars\", \"the fleet\", \"all Teslas\" -> vehicles \"all\". \"Tesla 45\" is fine as a name.",
  "6. Times: tools give times in Nashville local time, marked \"sim time\" (the simulation's clock) or \"CT\" (real time). Keep the mark. A hold time you send is on the sim clock.",
  "7. Keep it short and plain: two to five sentences, no tables, no headings, no JSON, no command ids unless asked. Numbers exactly as the tools give them.",
].join("\n");

/** The owner's context, from the handshake's whoami. It rides in the user turn so the system prompt stays cacheable. */
export function ownerContext(who: EngineOutcome, dryRun: boolean): string {
  const data = isObject(who.data) ? who.data : {};
  const scope = isObject(data.scope) ? data.scope : {};
  const depot = isObject(scope.depot) && typeof scope.depot.name === "string" ? scope.depot.name : "the depot";
  const fleet = isObject(scope.fleet_operator) && typeof scope.fleet_operator.name === "string" ? scope.fleet_operator.name : "the owner";
  const owner = isObject(data.owner) ? data.owner : null;
  const lines = [`Owner: ${fleet}, at ${depot}.`];
  if (owner) {
    const range = isObject(owner.charge_limit_pct) ? owner.charge_limit_pct : {};
    lines.push(`Cars: ${String(owner.cars ?? "unknown")}. Demo run live: ${owner.live_demo_run ? "yes" : "no (no change can be made until one starts)"}.`);
    if (range.min !== undefined && range.max !== undefined) lines.push(`Charge limit range in the contract: ${String(range.min)}% to ${String(range.max)}%.`);
    if (Array.isArray(owner.requestable_services)) {
      const svc = owner.requestable_services.filter(isObject).map((s) => `${String(s.service)} (${String(s.name)}, about ${String(s.minutes)} min, ${String(s.where)})`);
      if (svc.length) lines.push(`Services the owner may order: ${svc.join("; ")}.`);
    }
    if (owner.hold_max_hours !== undefined) lines.push(`A hold lasts at most ${String(owner.hold_max_hours)} sim hours.`);
  } else {
    lines.push("This token cannot change anything: answer questions only.");
  }
  if (dryRun) lines.push("DRY RUN: every change you make runs as a preview and nothing is applied. Say what WOULD happen, and say clearly that nothing has changed.");
  return lines.join("\n");
}

/** Owner tools as the model sees them: the arguments the door decides are not offered, and in a dry run neither is mode. */
export function modelTools(tools: readonly ToolDef[], dryRun: boolean): ModelTool[] {
  return tools.map((t) => {
    const props = { ...(t.inputSchema.properties ?? {}) };
    for (const k of RUNNER_ARGS) delete props[k];
    if (dryRun) delete props.mode;
    return { name: t.name, description: t.description, input_schema: { ...t.inputSchema, properties: props } };
  });
}

// ───────────────────────────────────────────────────────────────────────────────────────── the input ──

export type AskTurn = { role: "user" | "assistant"; text: string };
export type AskConfirm = { tool: string; args: Record<string, unknown> };
export type AskInput = { text?: string; dry_run: boolean; history: AskTurn[]; confirm?: AskConfirm[]; idempotency_key?: string };

export function parseAskBody(bodyText: string): { ok: true; value: AskInput } | { ok: false; errors: ValidationError[] } {
  let raw: unknown = {};
  if (bodyText.trim() !== "") {
    try { raw = JSON.parse(bodyText); } catch { return { ok: false, errors: [{ path: "$", message: "the body is not valid JSON" }] }; }
  }
  if (!isObject(raw)) return { ok: false, errors: [{ path: "$", message: "the body must be a JSON object" }] };
  const errors = validateAgainst(askInputSchema(), raw);
  if (errors.length === 0) {
    const hasText = typeof raw.text === "string" && raw.text.trim() !== "";
    if (hasText === (raw.confirm !== undefined)) errors.push({ path: "$.text", message: "send text, or confirm, but not both" });
    if (raw.confirm !== undefined && raw.dry_run === true) errors.push({ path: "$.dry_run", message: "a confirm applies a previewed plan; it cannot be a dry run" });
  }
  if (errors.length) return { ok: false, errors };
  return {
    ok: true,
    value: {
      text: typeof raw.text === "string" ? raw.text.trim() : undefined,
      dry_run: raw.dry_run === true,
      history: Array.isArray(raw.history) ? (raw.history as AskTurn[]) : [],
      confirm: Array.isArray(raw.confirm) ? (raw.confirm as AskConfirm[]) : undefined,
      idempotency_key: typeof raw.idempotency_key === "string" ? raw.idempotency_key : undefined,
    },
  };
}

/** Earlier turns plus this one, as the Messages API wants them: starting with the user, roles alternating. */
export function conversation(history: readonly AskTurn[], userText: string): ModelMessage[] {
  const turns: AskTurn[] = [];
  for (const t of [...history, { role: "user" as const, text: userText }]) {
    if (turns.length === 0 && t.role !== "user") continue;
    const last = turns[turns.length - 1];
    if (last && last.role === t.role) last.text = `${last.text}\n\n${t.text}`;
    else turns.push({ role: t.role, text: t.text });
  }
  return turns.map((t) => ({ role: t.role, content: t.text }) as ModelMessage);
}

// ──────────────────────────────────────────────────────────────────────────────────────── the result ──

export type AskAction = {
  tool: string;
  args: Record<string, unknown>;
  ok: boolean;
  http_status: number;
  outcome: string | null;
  summary: string | null;
  link: string | null;
  command_id: string | null;
  /** 0607: an applied command's "OQ-XXXX-XXXX", the same code OrchestrAV, OTTO-PULSE and the twin show. */
  confirmation_code: string | null;
  cars: number | null;
  confirm?: unknown;
  undo?: unknown;
  error?: { code: string; message: string };
};
export type AskResult = {
  answer: string;
  answered_by: string;
  dry_run: boolean;
  actions: AskAction[];
  reads: string[];
  link: string | null;
  incomplete: boolean;
  rounds: number;
};
export type AskFailure = { status: number; error: { code: string; message: string; details?: ValidationError[] }; partial?: AskResult };

function sortedJson(v: unknown): string {
  if (Array.isArray(v)) return `[${v.map(sortedJson).join(",")}]`;
  if (isObject(v)) return `{${Object.keys(v).sort().map((k) => `${JSON.stringify(k)}:${sortedJson(v[k])}`).join(",")}}`;
  return JSON.stringify(v);
}

/** One command's idempotency key, from the ask's key and the command's own content. */
export async function commandKey(askKey: string, tool: string, args: Record<string, unknown>): Promise<string> {
  const content = { ...args };
  for (const k of [...RUNNER_ARGS, "mode"]) delete content[k];
  return `${askKey}:${(await sha256Hex(`${tool}|${sortedJson(content)}`)).slice(0, 24)}`;
}

function actionOf(tool: string, args: Record<string, unknown>, outcome: EngineOutcome): AskAction {
  const d = isObject(outcome.data) ? outcome.data : {};
  const cmd = isObject(d.command) ? d.command : {};
  const shown = { ...args };
  delete shown.note;
  return {
    tool,
    args: shown,
    ok: outcome.ok,
    http_status: outcome.http_status,
    outcome: typeof d.outcome === "string" ? d.outcome : null,
    summary: typeof d.summary === "string" ? d.summary : null,
    link: typeof d.link === "string" ? d.link : null,
    command_id: typeof cmd.command_id === "string" ? cmd.command_id : null,
    confirmation_code: typeof d.confirmation_code === "string" ? d.confirmation_code : null,
    cars: typeof cmd.cars === "number" ? cmd.cars : null,
    ...(d.confirm !== undefined ? { confirm: d.confirm } : {}),
    ...(d.undo !== undefined ? { undo: d.undo } : {}),
    ...(!outcome.ok && outcome.error ? { error: { code: outcome.error.code, message: outcome.error.message } } : {}),
  };
}

/** What happened, in OTTO-Q's own words: every receipt's summary, or the error a command met. */
export function receiptsText(actions: readonly AskAction[]): string {
  return actions.map((a) => a.summary ?? `Not done (${a.tool.replace(/_/g, " ")}): ${a.error?.message ?? "OTTO-Q did not answer."}`).join("\n\n");
}

const CLAIMS_DONE = /^\s*(done\b|all set\b|it'?s done\b|completed\b|finished\b)/i;

/** The model's answer, held to the receipts: it may not claim a change nothing applied, and an applied change always
 *  carries its confirmation code (0607) and its OrchestrAV link. */
export function settleAnswer(answer: string, actions: readonly AskAction[], dryRun: boolean): string {
  const applied = actions.filter((a) => a.outcome === "applied");
  let out = answer.trim();
  if (out === "") out = actions.length ? receiptsText(actions) : "OTTO-Command has no answer to give.";
  if (CLAIMS_DONE.test(out) && (applied.length === 0 || dryRun)) out = receiptsText(actions) || out.replace(CLAIMS_DONE, "Not done.");
  if (!dryRun) {
    const missing = applied.map((a) => a.confirmation_code).filter((c): c is string => !!c && !out.includes(c));
    if (missing.length) out = `${out}\nConfirmation code${missing.length === 1 ? "" : "s"}: ${missing.join(", ")}.`;
  }
  const link = [...applied].reverse().find((a) => a.link)?.link;
  if (link && !out.includes(link)) out = `${out}\nSee it in OrchestrAV: ${link}`;
  return out;
}

function primaryLink(actions: readonly AskAction[], readLink: string | null): string | null {
  const withLink = [...actions].reverse().find((a) => a.link && (a.outcome === "applied" || a.outcome === "previewed"));
  return withLink?.link ?? readLink;
}

function capped(text: string): string {
  return text.length <= TOOL_RESULT_MAX_CHARS ? text : `${text.slice(0, TOOL_RESULT_MAX_CHARS)}\n[cut: the result was longer]`;
}

// ────────────────────────────────────────────────────────────────────────────────────────── the door ──

export type AskDeps = {
  who: EngineOutcome;
  call: EngineCall;
  model: ModelCall | null;
  maxRounds?: number;
  budgetMs?: number;
  now?: () => number;
};

/** The owner tools this token may use. */
export function ownerTools(who: EngineOutcome): ToolDef[] {
  const { capabilities, fleetBound } = principalScope(who);
  return toolsFor(capabilities, { fleetBound }).filter((t) => OWNER_TOOL_NAMES.has(t.name));
}

/** Apply previewed plans exactly: each confirm goes out with mode apply and its plan hash, and no model is involved. */
async function applyConfirms(input: AskInput, deps: AskDeps, tools: readonly ToolDef[]): Promise<AskResult | AskFailure> {
  const actions: AskAction[] = [];
  for (const [i, c] of (input.confirm ?? []).entries()) {
    const tool = tools.find((t) => t.name === c.tool && COMMAND_NAMES.has(t.name));
    if (!tool) return { status: 403, error: { code: "tool_not_available", message: `confirm[${i}]: ${c.tool} is not a command this token may send.` } };
    const args: Record<string, unknown> = { ...c.args, mode: "apply" };
    if (typeof args.expect_plan_hash !== "string") {
      return { status: 400, error: { code: "invalid_arguments", message: `confirm[${i}] carries no expect_plan_hash: send the confirm object a preview returned, unchanged.` } };
    }
    if (input.idempotency_key && args.idempotency_key === undefined) args.idempotency_key = await commandKey(input.idempotency_key, tool.name, args);
    const v = validateToolArgs(tool, args);
    if (!v.ok) return { status: 400, error: { code: "invalid_arguments", message: `confirm[${i}] is not a valid ${tool.name}.`, details: v.errors } };
    const outcome = await deps.call(tool.name, v.value, {});
    if (isTransportFailure(outcome) && actions.length === 0) {
      return { status: outcome.http_status, error: { code: outcome.error?.code ?? "error", message: outcome.error?.message ?? "The request failed." } };
    }
    actions.push(actionOf(tool.name, v.value, outcome));
    if (isTransportFailure(outcome)) break;
  }
  const answer = settleAnswer(receiptsText(actions), actions, false);
  return { answer, answered_by: ANSWERED_BY, dry_run: false, actions, reads: [], link: primaryLink(actions, null), incomplete: false, rounds: 0 };
}

/** One ask: the model reads the owner's words and calls tools through the owner's token until it can answer. */
export async function runOwnerAsk(input: AskInput, deps: AskDeps): Promise<AskResult | AskFailure> {
  const tools = ownerTools(deps.who);
  if (!tools.some((t) => t.name === "my_fleet")) {
    return { status: 403, error: { code: "ask_needs_an_owner_token", message: "The plain-English door is for a vehicle owner's token: one bound to a fleet, with the read capability." } };
  }
  if (input.confirm) return applyConfirms(input, deps, tools);
  if (!deps.model) return { status: 503, error: { code: "ask_not_configured", message: "The plain-English door has no model configured. Every tool works directly over MCP and REST." } };

  const now = deps.now ?? Date.now;
  const started = now();
  const budget = deps.budgetMs ?? ASK_BUDGET_MS;
  const maxRounds = deps.maxRounds ?? ASK_MAX_ROUNDS;
  const words = (input.text ?? "").slice(0, ASK_MAX_TEXT);
  const offered = modelTools(tools, input.dry_run);
  const messages = conversation(input.history, `<context>\n${ownerContext(deps.who, input.dry_run)}\n</context>\n\n<owner_request>\n${words}\n</owner_request>`);
  const actions: AskAction[] = [];
  const reads: string[] = [];
  let readLink: string | null = null;
  let lastText = "";
  let finished = false;
  let stopped: { code: string; message: string } | null = null;
  let rounds = 0;

  while (rounds < maxRounds) {
    if (now() - started > budget) { stopped = { code: "ask_budget_spent", message: "OTTO-Command ran out of time." }; break; }
    const reply = await deps.model({ system: SYSTEM_PROMPT, tools: offered, messages, max_tokens: ASK_MAX_TOKENS });
    rounds += 1;
    if (!reply.ok) { stopped = { code: "ask_model_failed", message: reply.message }; break; }
    const text = reply.content.filter((b): b is { type: "text"; text: string } => b.type === "text").map((b) => b.text).join("\n").trim();
    if (text) lastText = text;
    const uses = reply.content.filter((b): b is { type: "tool_use"; id: string; name: string; input: unknown } => b.type === "tool_use");
    if (reply.stop_reason !== "tool_use" || uses.length === 0) { finished = true; break; }

    messages.push({ role: "assistant", content: reply.content });
    const results: ToolResultBlock[] = [];
    for (const use of uses) {
      const tool = tools.find((t) => t.name === use.name);
      if (!tool) {
        results.push({ type: "tool_result", tool_use_id: use.id, is_error: true, content: `No tool named ${use.name} is available here.` });
        continue;
      }
      const args: Record<string, unknown> = isObject(use.input) ? { ...use.input } : {};
      for (const k of RUNNER_ARGS) delete args[k];
      const isCommand = COMMAND_NAMES.has(tool.name);
      if (isCommand) {
        if (input.dry_run) args.mode = "preview";
        if (words) args.note = words.slice(0, 500);
        if (input.idempotency_key && args.mode !== "preview") args.idempotency_key = await commandKey(input.idempotency_key, tool.name, args);
      }
      const v = validateToolArgs(tool, args);
      if (!v.ok) {
        results.push({ type: "tool_result", tool_use_id: use.id, is_error: true, content: JSON.stringify({ error: "invalid_arguments", details: v.errors }) });
        continue;
      }
      const outcome = await deps.call(tool.name, v.value, {});
      if (isCommand) actions.push(actionOf(tool.name, v.value, outcome));
      else {
        reads.push(tool.name);
        const d = isObject(outcome.data) ? outcome.data : {};
        if (typeof d.link === "string") readLink = d.link;
      }
      if (isTransportFailure(outcome)) {
        stopped = { code: outcome.error?.code ?? "error", message: outcome.error?.message ?? "OTTO-Q did not answer." };
        break;
      }
      const shown = outcome.ok ? outcome.data : { error: outcome.error, ...(outcome.data !== undefined ? { data: outcome.data } : {}) };
      results.push({ type: "tool_result", tool_use_id: use.id, ...(outcome.ok ? {} : { is_error: true }), content: capped(JSON.stringify(shown ?? null)) });
    }
    if (stopped) break;
    messages.push({ role: "user", content: results });
  }
  if (!finished && !stopped) stopped = { code: "ask_round_limit", message: "OTTO-Command reached its step limit." };

  if (stopped && actions.length === 0 && !lastText) {
    // nothing was done and nothing can be said: an honest failure, not an invented answer
    const status = stopped.code === "ask_model_failed" ? 502 : stopped.code === "rate_limited" ? 429 : stopped.code === "unauthenticated" ? 401 : 504;
    return { status, error: stopped };
  }
  const incomplete = stopped !== null;
  const draft = incomplete
    ? (actions.length
      ? `OTTO-Command could not finish its answer, but here is what OTTO-Q did:\n\n${receiptsText(actions)}`
      : lastText)
    : lastText;
  return {
    answer: settleAnswer(draft, actions, input.dry_run),
    answered_by: ANSWERED_BY,
    dry_run: input.dry_run,
    actions,
    reads,
    link: primaryLink(actions, readLink),
    incomplete,
    rounds,
  };
}

/** The door as the gateway mounts it. Without a model it still applies confirms; a plain-English ask answers 503. */
export function ownerAskHandler(o: { model: ModelCall | null; modelName?: string; maxRounds?: number; budgetMs?: number }): AskHandler {
  return async ({ who, call, bodyText }): Promise<HttpOut> => {
    const meta: Record<string, unknown> = { tool: "ask", call_id: who.call_id ?? null };
    const parsed = parseAskBody(bodyText);
    if (!parsed.ok) {
      return { status: 400, headers: {}, body: { error: { code: "invalid_arguments", message: "The ask is not valid.", details: parsed.errors }, meta } };
    }
    const result = await runOwnerAsk(parsed.value, { who, call, model: o.model, maxRounds: o.maxRounds, budgetMs: o.budgetMs });
    if ("error" in result) return { status: result.status, headers: {}, body: { error: result.error, meta } };
    if (o.modelName && !parsed.value.confirm) meta.model = o.modelName;
    return { status: 200, headers: {}, body: { data: result, meta } };
  };
}
