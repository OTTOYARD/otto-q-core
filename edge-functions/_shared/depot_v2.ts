// The v2 operator door: its logic, importable by Deno (ottoq-depot-v2/index.ts) and by Node (tests/depot_v2.test.mjs).
// The contract is contract/README.md; the door's database half is db/migrations/0650 to 0652.
//
//   operator --X-OTTO-Q-API-Key--> POST /events     --sha256(key), events that pass contract/schemas-->
//                                                     public.ottoq_v2_take_events (scope, once, order, apply)
//   operator --X-OTTO-Q-API-Key--> GET  /directives --> public.ottoq_v2_read_directives --> signed here, then sent
//   anyone                       --> GET  /jwks       --> public.ottoq_v2_jwks (the public halves)
//
// What this file decides is only what HTTP needs: the credential's form, content type, size, the schema check, and the
// signature. Who a key speaks for, which car is whose, once-only and order are the database's, so nothing here can
// widen what a key may do. The raw key never leaves this process: only its SHA-256 is sent.
//
// The signature (contract/README.md, Signatures): a detached JWS, compact form (RFC 7515 Appendix F), protected
// header exactly {"alg":"Ed25519","kid":...} (RFC 9864), over the RFC 8785 canonical form of the whole event without
// ottoqsig. Byte for byte what contract/ottoq_contract.py signs; tests/depot_v2.test.mjs proves it on the examples.

export const DOOR_NAME = "ottoq-depot-v2";
export const MAX_BODY_BYTES = 1024 * 1024;   // contract/README.md: at most 1 MiB per request
export const MAX_BATCH = 500;                // and at most 500 events
export const KEY_HEADER = "x-otto-q-api-key";
const KEY_FORM = /^ottow_[0-9a-f]{64}$/;
const CE_SINGLE = "application/cloudevents+json";
const CE_BATCH = "application/cloudevents-batch+json";

// ─────────────────────────────────────────────────────────────────────────────────────────── canonical JSON

/** RFC 8785: ECMAScript's own number and string forms, object keys sorted by UTF-16 code units (JavaScript's sort). */
export function jcs(v: unknown): string {
  if (v === null || typeof v === "boolean" || typeof v === "string") return JSON.stringify(v);
  if (typeof v === "number") {
    if (!Number.isFinite(v)) throw new Error("NaN and Infinity have no JSON form (RFC 8785 section 3.2.2.3)");
    return JSON.stringify(v);
  }
  if (Array.isArray(v)) return "[" + v.map(jcs).join(",") + "]";
  if (typeof v === "object") {
    const o = v as Record<string, unknown>;
    return "{" + Object.keys(o).filter((k) => o[k] !== undefined).sort()
      .map((k) => JSON.stringify(k) + ":" + jcs(o[k])).join(",") + "}";
  }
  throw new Error(`${typeof v} has no JSON form`);
}

const enc = new TextEncoder();

export function b64u(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function b64uToBytes(s: string): Uint8Array {
  if (!/^[A-Za-z0-9_-]*$/.test(s)) throw new Error("not base64url");
  const bin = atob(s.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (s.length % 4)) % 4));
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

export async function sha256Hex(s: string): Promise<string> {
  const d = new Uint8Array(await crypto.subtle.digest("SHA-256", enc.encode(s)));
  return Array.from(d, (b) => b.toString(16).padStart(2, "0")).join("");
}

// ─────────────────────────────────────────────────────────────────────────────────────────────── signatures

export type Signer = { kid: string; sign: (data: Uint8Array) => Promise<Uint8Array> };
export type Jwk = { kty: string; crv: string; x: string; d?: string; kid?: string; [k: string]: unknown };

/** What the signature covers: the whole event without ottoqsig, canonical. */
export function signingPayload(event: Record<string, unknown>): string {
  const { ottoqsig: _drop, ...body } = event;
  return jcs(body);
}

export function protectedHeader(kid: string): string {
  return b64u(enc.encode(jcs({ alg: "Ed25519", kid })));
}

/** The event with its ottoqsig: B64U(header) + ".." + B64U(Ed25519(B64U(header) + "." + B64U(JCS(event - ottoqsig)))). */
export async function signEvent(event: Record<string, unknown>, signer: Signer): Promise<Record<string, unknown>> {
  const header = protectedHeader(signer.kid);
  const input = enc.encode(header + "." + b64u(enc.encode(signingPayload(event))));
  const sig = await signer.sign(input);
  return { ...event, ottoqsig: header + ".." + b64u(sig) };
}

/** True when the event's ottoqsig verifies under one of the JWK Set's Ed25519 public keys. */
export async function verifyEvent(event: Record<string, unknown>, jwks: { keys: Jwk[] }): Promise<boolean> {
  const sig = event.ottoqsig;
  if (typeof sig !== "string") return false;
  const parts = sig.split(".");
  if (parts.length !== 3 || parts[1] !== "") return false;
  let header: Record<string, unknown>;
  try { header = JSON.parse(new TextDecoder().decode(b64uToBytes(parts[0]))); } catch { return false; }
  if (Object.keys(header).sort().join(",") !== "alg,kid" || header.alg !== "Ed25519") return false;
  const jwk = jwks.keys.find((k) => k.kid === header.kid && k.kty === "OKP" && k.crv === "Ed25519" && !("d" in k));
  if (!jwk) return false;
  const key = await crypto.subtle.importKey("jwk", { kty: "OKP", crv: "Ed25519", x: jwk.x }, { name: "Ed25519" }, false, ["verify"]);
  const input = enc.encode(parts[0] + "." + b64u(enc.encode(signingPayload(event))));
  return crypto.subtle.verify({ name: "Ed25519" }, key, b64uToBytes(parts[2]), input);
}

/** A signer from a private JWK (RFC 8037 OKP form). */
export async function signerFromJwk(kid: string, jwk: Jwk): Promise<Signer> {
  const key = await crypto.subtle.importKey("jwk", { kty: "OKP", crv: "Ed25519", x: jwk.x, d: jwk.d }, { name: "Ed25519" },
    false, ["sign"]);
  return { kid, sign: async (data) => new Uint8Array(await crypto.subtle.sign({ name: "Ed25519" }, key, data)) };
}

/** The depot's key: read from the platform's store, or made here and stored there on first use. The private half is
 *  generated in this process and handed only to the store (0651: Supabase Vault); one key is active at a time, and a
 *  concurrent first use that loses the race signs with the winner's key. */
export function depotSigner(engine: Pick<EngineV2, "signingKeyCurrent" | "signingKeyStore">): () => Promise<Signer> {
  let cached: Promise<Signer> | null = null;
  const load = async (): Promise<Signer> => {
    const cur = await engine.signingKeyCurrent();
    if (cur) return signerFromJwk(cur.kid, cur.private_jwk);
    const pair = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]) as CryptoKeyPair;
    const priv = await crypto.subtle.exportKey("jwk", pair.privateKey) as Jwk;
    const kid = "ottoq-depot-" + (await sha256Hex(priv.x)).slice(0, 16);
    const stored = await engine.signingKeyStore(kid, { kty: "OKP", crv: "Ed25519", x: priv.x },
      { kty: "OKP", crv: "Ed25519", x: priv.x, d: priv.d });
    if (stored.stored) return signerFromJwk(kid, priv);
    const winner = await engine.signingKeyCurrent();
    if (!winner) throw new Error("the signing key store answered that a key exists, and returned none");
    return signerFromJwk(winner.kid, winner.private_jwk);
  };
  return () => (cached ??= load().catch((e) => { cached = null; throw e; }));
}

// ───────────────────────────────────────────────────────────────────────────────────────────────────── engine

export type TakeResult = { ok: boolean; reason?: string; results?: Record<string, unknown>[]; [k: string]: unknown };
export type ReadResult = { ok: boolean; reason?: string; events?: Record<string, unknown>[]; next_after?: number; [k: string]: unknown };
export type EngineV2 = {
  takeEvents: (keyHash: string, events: unknown[], dryRun: boolean) => Promise<TakeResult>;
  readDirectives: (keyHash: string, after: number, limit: number, markDelivered: boolean) => Promise<ReadResult>;
  signingKeyCurrent: () => Promise<{ kid: string; private_jwk: Jwk } | null>;
  signingKeyStore: (kid: string, publicJwk: Jwk, privateJwk: Jwk) => Promise<{ stored: boolean; kid: string }>;
  jwks: () => Promise<{ keys: Jwk[] }>;
};

export class EngineError extends Error {
  status: number;
  code: string;
  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

/** The door's database half through PostgREST, as the service role. A sb_secret_ key goes in apikey alone; a legacy
 *  service JWT goes in Authorization too (the same rule as _shared/agent_gateway.ts). */
export function postgrestV2Engine(o: { supabaseUrl: string; serviceKey: string; fetchImpl?: typeof fetch; timeoutMs?: number }): EngineV2 {
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
      if (name === "TimeoutError" || name === "AbortError") throw new EngineError(504, "engine_timeout", "OTTO-Q did not answer in time; the outcome is unknown. Resend: the same event ids are taken once.");
      throw new EngineError(503, "engine_unreachable", "OTTO-Q could not be reached. Nothing was taken; try again shortly.");
    }
    const text = await res.text();
    let body: unknown = null;
    try { body = text ? JSON.parse(text) : null; } catch { body = null; }
    if (res.ok) return body;
    const code = body && typeof body === "object" && typeof (body as { code?: unknown }).code === "string" ? (body as { code: string }).code : "";
    if (res.status === 404 || code === "PGRST202" || code === "42883") throw new EngineError(503, "door_not_enabled", "The v2 door's database half is not applied.");
    if (res.status === 401 || res.status === 403 || code === "42501") throw new EngineError(502, "engine_misconfigured", "The door could not authenticate to OTTO-Q.");
    throw new EngineError(502, "engine_error", "OTTO-Q answered outside the door's contract.");
  };
  return {
    takeEvents: async (h, events, dryRun) => rpc("ottoq_v2_take_events", { p_key_hash: h, p_events: events, p_dry_run: dryRun }) as Promise<TakeResult>,
    readDirectives: async (h, after, limit, mark) =>
      rpc("ottoq_v2_read_directives", { p_key_hash: h, p_after: after, p_limit: limit, p_mark_delivered: mark }) as Promise<ReadResult>,
    signingKeyCurrent: async () => (await rpc("ottoq_v2_signing_key_current", {})) as { kid: string; private_jwk: Jwk } | null,
    signingKeyStore: async (kid, pub, priv) =>
      rpc("ottoq_v2_signing_key_store", { p_kid: kid, p_public_jwk: pub, p_private_jwk: priv }) as Promise<{ stored: boolean; kid: string }>,
    jwks: async () => (await rpc("ottoq_v2_jwks", {})) as { keys: Jwk[] },
  };
}

// ──────────────────────────────────────────────────────────────────────────────────────────────────── the door

export type DoorDeps = {
  engine: EngineV2;
  /** Every way an event breaks contract/schemas (envelope.json with data); empty when it conforms. */
  validate: (event: unknown) => string[];
  signer: () => Promise<Signer>;
};

const JSON_HEADERS = { "Content-Type": "application/json", "Cache-Control": "no-store" };

function reply(status: number, body: unknown, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...JSON_HEADERS, ...extra } });
}

function refuse(status: number, code: string, message: string): Response {
  return reply(status, { ok: false, error: { code, message } });
}

/** The route after the function's own name: /events, /directives, /jwks. */
export function routeOf(url: URL): string {
  const p = url.pathname.replace(/\/+$/, "");
  const i = p.indexOf("/" + DOOR_NAME);
  const rest = i >= 0 ? p.slice(i + DOOR_NAME.length + 1) : p;
  return rest === "" ? "/" : rest;
}

const ENGINE_REFUSAL: Record<string, [number, string]> = {
  unknown_or_revoked_key: [401, "The key is unknown or revoked."],
  key_speaks_for_no_fleet: [403, "The key speaks for no fleet's cars yet; the platform scopes it (ottoq_scope_source_key)."],
  no_running_run: [409, "A twin or replay key is judged on its run's clock, and no run is running at its depot."],
  batch_size: [413, `A request carries 1 to ${MAX_BATCH} events.`],
  events_must_be_an_array: [400, "The events must be a JSON array."],
};

function engineRefusal(r: { reason?: string }): Response {
  const reason = r.reason ?? "refused";
  const known = ENGINE_REFUSAL[reason] ?? (reason.startsWith("no_directives_for_") ? [403, "This key's data source has no directives."] : null);
  return known ? refuse(known[0], reason, known[1]) : refuse(422, reason, "OTTO-Q refused the request.");
}

async function keyHashOf(req: Request): Promise<string | Response> {
  const key = (req.headers.get(KEY_HEADER) ?? "").trim();
  if (!key) return refuse(401, "no_key", `Send your source key as the ${KEY_HEADER} header.`);
  if (!KEY_FORM.test(key)) return refuse(401, "malformed_key", "A source key is ottow_ followed by 64 lowercase hex characters.");
  return sha256Hex(key);
}

async function takeEvents(req: Request, url: URL, deps: DoorDeps): Promise<Response> {
  const keyHash = await keyHashOf(req);
  if (keyHash instanceof Response) return keyHash;
  const ctype = (req.headers.get("content-type") ?? "").split(";")[0].trim().toLowerCase();
  if (ctype !== CE_SINGLE && ctype !== CE_BATCH) {
    return refuse(415, "content_type", `Send ${CE_SINGLE} (one event) or ${CE_BATCH} (a JSON array of events). Binary mode is not taken.`);
  }
  const declared = Number(req.headers.get("content-length") ?? "0");
  if (declared > MAX_BODY_BYTES) return refuse(413, "too_large", "At most 1 MiB per request.");
  const raw = new Uint8Array(await req.arrayBuffer());
  if (raw.byteLength > MAX_BODY_BYTES) return refuse(413, "too_large", "At most 1 MiB per request.");
  let body: unknown;
  try { body = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(raw)); } catch {
    return refuse(400, "bad_json", "The body is not UTF-8 JSON.");
  }
  let events: unknown[];
  if (ctype === CE_BATCH) {
    if (!Array.isArray(body)) return refuse(400, "batch_not_array", "A batch is a JSON array of events.");
    events = body;
  } else {
    if (body === null || typeof body !== "object" || Array.isArray(body)) return refuse(400, "not_an_event", "One event is one JSON object.");
    events = [body];
  }
  if (events.length === 0 || events.length > MAX_BATCH) return refuse(413, "batch_size", `A request carries 1 to ${MAX_BATCH} events.`);
  const dryRun = ["1", "true"].includes((url.searchParams.get("dry_run") ?? "").toLowerCase());

  // The schema first. An event that breaks it never reaches the engine, and is answered in its place.
  const checked = events.map((e) => ({ e, problems: deps.validate(e) }));
  const passing = checked.filter((c) => c.problems.length === 0).map((c) => c.e);
  let engineResults: Record<string, unknown>[] = [];
  let head: TakeResult | null = null;
  if (passing.length > 0) {
    try { head = await deps.engine.takeEvents(keyHash, passing, dryRun); } catch (e) {
      if (e instanceof EngineError) return refuse(e.status, e.code, e.message);
      throw e;
    }
    if (!head.ok) return engineRefusal(head);
    engineResults = head.results ?? [];
  }
  let k = 0;
  const results = checked.map((c) => {
    if (c.problems.length > 0) {
      const o = c.e as Record<string, unknown> | null;
      return { id: typeof o?.id === "string" ? o.id : null, source: typeof o?.source === "string" ? o.source : null,
               disposition: "refused", reason: "schema", problems: c.problems.slice(0, 10) };
    }
    return engineResults[k++] ?? { disposition: "refused", reason: "engine_returned_no_result" };
  });
  const count = (d: string) => results.filter((r) => (r as { disposition?: unknown }).disposition === d).length;
  return reply(200, {
    ok: true, dry_run: dryRun, operator: head?.operator ?? null, data_source: head?.data_source ?? null,
    sim_run_id: head?.sim_run_id ?? null, clock: head?.clock ?? null, received: events.length,
    applied: count("applied"), late: count("late"), duplicate: count("duplicate"), refused: count("refused"), results,
  });
}

async function readDirectives(req: Request, url: URL, deps: DoorDeps): Promise<Response> {
  const keyHash = await keyHashOf(req);
  if (keyHash instanceof Response) return keyHash;
  const afterRaw = url.searchParams.get("after") ?? "0";
  const limitRaw = url.searchParams.get("limit") ?? "100";
  if (!/^[0-9]{1,18}$/.test(afterRaw)) return refuse(400, "after", "after is the cursor a previous read returned: a whole number.");
  if (!/^[0-9]{1,3}$/.test(limitRaw) || Number(limitRaw) < 1 || Number(limitRaw) > MAX_BATCH) {
    return refuse(400, "limit", `limit is 1 to ${MAX_BATCH}.`);
  }
  const peek = ["1", "true"].includes((url.searchParams.get("peek") ?? "").toLowerCase());
  let r: ReadResult;
  try { r = await deps.engine.readDirectives(keyHash, Number(afterRaw), Number(limitRaw), !peek); } catch (e) {
    if (e instanceof EngineError) return refuse(e.status, e.code, e.message);
    throw e;
  }
  if (!r.ok) return engineRefusal(r);
  const signer = await deps.signer();
  const signed = [];
  for (const ev of r.events ?? []) signed.push(await signEvent(ev, signer));
  return new Response(JSON.stringify(signed), { status: 200, headers: {
    "Content-Type": `${CE_BATCH}; charset=utf-8`, "Cache-Control": "no-store",
    "OTTOQ-Next-After": String(r.next_after ?? afterRaw), "OTTOQ-Signing-Kid": signer.kid,
  } });
}

async function jwks(deps: DoorDeps): Promise<Response> {
  try {
    await deps.signer();   // a depot publishes a key before it signs anything with it
    return reply(200, await deps.engine.jwks(), { "Cache-Control": "public, max-age=300" });
  } catch (e) {
    if (e instanceof EngineError) return refuse(e.status, e.code, e.message);
    throw e;
  }
}

/** The door. Operators are servers, so no browser origin is allowed (no CORS headers are ever sent). */
export async function handleDepotV2Request(req: Request, deps: DoorDeps): Promise<Response> {
  const url = new URL(req.url);
  const route = routeOf(url);
  try {
    if (route === "/events" && req.method === "POST") return await takeEvents(req, url, deps);
    if (route === "/directives" && req.method === "GET") return await readDirectives(req, url, deps);
    if (route === "/jwks" && req.method === "GET") return await jwks(deps);
    if (["/events", "/directives", "/jwks"].includes(route)) return refuse(405, "method", "Wrong method for this route.");
    return refuse(404, "no_route", "Routes: POST /events, GET /directives, GET /jwks (contract/README.md).");
  } catch (_e) {
    return refuse(500, "door_error", "The door failed before it could answer. Nothing it could not finish was kept.");
  }
}
