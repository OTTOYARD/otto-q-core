// ottoq-csms-relay, its pure half: the door through which OTTO-Q's charger back end (csms/, on AWS) reads the twin's
// charger frames and reports what it did with them (db/migrations/0697, csms/README.md "Still to build").
//
//   back end --X-OTTO-Q-API-Key--> GET  /frames?after=N&limit=M[&chargers=true]  --sha256(key)--> ottoq_csms_pull
//   back end --X-OTTO-Q-API-Key--> POST /report (application/json, at most 256 KiB) --sha256(key)--> ottoq_csms_report
//
// The key is a charger_backend source key made on the back end's own machine (0697 registers its hash). Which depot,
// which data source and whether the key may read at all are decided in the database from the key alone; nothing here
// can widen them. The raw key never leaves this process: only its SHA-256 is sent. No browser origin is allowed.
import { EngineError, KEY_HEADER, sha256Hex } from "./depot_v2.ts";

export const RELAY_NAME = "ottoq-csms-relay";
export const MAX_REPORT_BYTES = 256 * 1024;
export const MAX_FRAMES = 1000;
const KEY_FORM = /^ottow_[0-9a-f]{64}$/;

export type PullResult = { ok: boolean; reason?: string; rows?: unknown[]; next_after?: number; more?: boolean; [k: string]: unknown };
export type ReportResult = { ok: boolean; reason?: string; report_id?: number };
export type RelayEngine = {
  pull: (keyHash: string, after: number, limit: number, withChargers: boolean) => Promise<PullResult>;
  report: (keyHash: string, report: unknown) => Promise<ReportResult>;
};

/** The relay's database half through PostgREST, as the service role (the same caller as the v2 door's). */
export function postgrestRelayEngine(o: { supabaseUrl: string; serviceKey: string; fetchImpl?: typeof fetch; timeoutMs?: number }): RelayEngine {
  const base = `${o.supabaseUrl.replace(/\/+$/, "")}/rest/v1/rpc/`;
  const headers: Record<string, string> = { "Content-Type": "application/json", Accept: "application/json", apikey: o.serviceKey };
  if (/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(o.serviceKey)) headers.Authorization = `Bearer ${o.serviceKey}`;
  const doFetch = o.fetchImpl ?? fetch;
  const timeoutMs = o.timeoutMs ?? 20_000;
  const rpc = async (fn: string, args: Record<string, unknown>): Promise<unknown> => {
    let res: Response;
    try {
      res = await doFetch(base + fn, { method: "POST", headers, body: JSON.stringify(args), signal: AbortSignal.timeout(timeoutMs) });
    } catch (e) {
      const name = (e as { name?: string } | null)?.name;
      if (name === "TimeoutError" || name === "AbortError") throw new EngineError(504, "engine_timeout", "OTTO-Q did not answer in time.");
      throw new EngineError(503, "engine_unreachable", "OTTO-Q could not be reached; try again shortly.");
    }
    const text = await res.text();
    let body: unknown = null;
    try { body = text ? JSON.parse(text) : null; } catch { body = null; }
    if (res.ok) return body;
    const code = body && typeof body === "object" && typeof (body as { code?: unknown }).code === "string" ? (body as { code: string }).code : "";
    if (res.status === 404 || code === "PGRST202" || code === "42883") throw new EngineError(503, "relay_not_enabled", "The relay's database half (0697) is not applied.");
    if (res.status === 401 || res.status === 403 || code === "42501") throw new EngineError(502, "engine_misconfigured", "The relay could not authenticate to OTTO-Q.");
    throw new EngineError(502, "engine_error", "OTTO-Q answered outside the relay's contract.");
  };
  return {
    pull: async (h, after, limit, withChargers) =>
      rpc("ottoq_csms_pull", { p_key_hash: h, p_after: after, p_limit: limit, p_with_chargers: withChargers }) as Promise<PullResult>,
    report: async (h, report) => rpc("ottoq_csms_report", { p_key_hash: h, p_report: report }) as Promise<ReportResult>,
  };
}

const JSON_HEADERS = { "Content-Type": "application/json", "Cache-Control": "no-store" };

function reply(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

function refuse(status: number, code: string, message: string): Response {
  return reply(status, { ok: false, error: { code, message } });
}

/** The route after the function's own name: /frames, /report. */
export function relayRouteOf(url: URL): string {
  const p = url.pathname.replace(/\/+$/, "");
  const i = p.indexOf("/" + RELAY_NAME);
  const rest = i >= 0 ? p.slice(i + RELAY_NAME.length + 1) : p;
  return rest === "" ? "/" : rest;
}

const ENGINE_REFUSAL: Record<string, [number, string]> = {
  unknown_or_revoked_key: [401, "The key is unknown or revoked."],
  stream_not_allowed: [403, "The key does not carry the ocpp stream."],
  not_a_charger_backend_key: [403, "Only a charger back end's key reads or reports charger frames."],
  pull_is_for_the_twin: [403, "Frames are read only for the twin; a real back end hears its own chargers."],
  report_shape: [400, "A report is a JSON object with from_seq, to_seq, frames and outcomes."],
  report_outcomes: [400, "outcomes counts accepted, not_2_0_1, csms_error and not_a_station_frame, each a whole number."],
  report_does_not_add_up: [422, "frames must equal the sum of the outcomes, and to_seq must not be below from_seq."],
};

function engineRefusal(r: { reason?: string }): Response {
  const reason = r.reason ?? "refused";
  const known = ENGINE_REFUSAL[reason];
  return known ? refuse(known[0], reason, known[1]) : refuse(422, reason, "OTTO-Q refused the request.");
}

async function keyHashOf(req: Request): Promise<string | Response> {
  const key = (req.headers.get(KEY_HEADER) ?? "").trim();
  if (!key) return refuse(401, "no_key", `Send the back end's key as the ${KEY_HEADER} header.`);
  if (!KEY_FORM.test(key)) return refuse(401, "malformed_key", "A source key is ottow_ followed by 64 lowercase hex characters.");
  return sha256Hex(key);
}

async function frames(req: Request, url: URL, engine: RelayEngine): Promise<Response> {
  const keyHash = await keyHashOf(req);
  if (keyHash instanceof Response) return keyHash;
  const afterRaw = url.searchParams.get("after") ?? "-1";
  const limitRaw = url.searchParams.get("limit") ?? "200";
  if (!/^-?[0-9]{1,18}$/.test(afterRaw)) return refuse(400, "after", "after is the cursor a previous read returned, or -1 to start at the head.");
  if (!/^[0-9]{1,4}$/.test(limitRaw) || Number(limitRaw) < 1 || Number(limitRaw) > MAX_FRAMES) {
    return refuse(400, "limit", `limit is 1 to ${MAX_FRAMES}.`);
  }
  const withChargers = ["1", "true"].includes((url.searchParams.get("chargers") ?? "").toLowerCase());
  let r: PullResult;
  try { r = await engine.pull(keyHash, Number(afterRaw), Number(limitRaw), withChargers); } catch (e) {
    if (e instanceof EngineError) return refuse(e.status, e.code, e.message);
    throw e;
  }
  if (!r.ok) return engineRefusal(r);
  return reply(200, r);
}

async function report(req: Request, engine: RelayEngine): Promise<Response> {
  const keyHash = await keyHashOf(req);
  if (keyHash instanceof Response) return keyHash;
  const ctype = (req.headers.get("content-type") ?? "").split(";")[0].trim().toLowerCase();
  if (ctype !== "application/json") return refuse(415, "content_type", "Send the report as application/json.");
  const declared = Number(req.headers.get("content-length") ?? "0");
  if (declared > MAX_REPORT_BYTES) return refuse(413, "too_large", "At most 256 KiB per report.");
  const raw = new Uint8Array(await req.arrayBuffer());
  if (raw.byteLength > MAX_REPORT_BYTES) return refuse(413, "too_large", "At most 256 KiB per report.");
  let body: unknown;
  try { body = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(raw)); } catch {
    return refuse(400, "bad_json", "The body is not UTF-8 JSON.");
  }
  if (body === null || typeof body !== "object" || Array.isArray(body)) return refuse(400, "report_shape", "A report is one JSON object.");
  let r: ReportResult;
  try { r = await engine.report(keyHash, body); } catch (e) {
    if (e instanceof EngineError) return refuse(e.status, e.code, e.message);
    throw e;
  }
  if (!r.ok) return engineRefusal(r);
  return reply(200, r);
}

/** The relay. Its callers are servers, so no browser origin is allowed (no CORS headers are ever sent). */
export async function handleCsmsRelayRequest(req: Request, engine: RelayEngine): Promise<Response> {
  const url = new URL(req.url);
  const route = relayRouteOf(url);
  try {
    if (route === "/frames" && req.method === "GET") return await frames(req, url, engine);
    if (route === "/report" && req.method === "POST") return await report(req, engine);
    if (["/frames", "/report"].includes(route)) return refuse(405, "method", "Wrong method for this route.");
    return refuse(404, "no_route", "Routes: GET /frames, POST /report (db/migrations/0697).");
  } catch (_e) {
    return refuse(500, "relay_error", "The relay failed before it could answer.");
  }
}
