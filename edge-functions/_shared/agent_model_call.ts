/**
 * The orchestrator agent's model call, with retries and a fallback model (edge function v23).
 *
 * WHY. From 2026-10-06 the hosted endpoint refused a third to a half of the agent's calls at an unchanged call rate.
 * Measured on run 81787ef9 (17:00-18:00 UTC, 2026-10-07, public.ottoq_model_call_ledger): 74 answered, 26 HTTP 429
 * "Too Many Requests", 20 HTTP 503 "Service temporarily unavailable" and 1 timeout. The refusals come back fast (a
 * mean of 132 ms for a 429 and 478 ms for a 503), and v22 gave each one up after a single try per key with no pause:
 * the pass fell to the deterministic fallback and the depot lost that pass's advice.
 *
 * WHAT. One call goes through a short plan: the primary model twice, then the fallback model twice, each attempt
 * bounded by its own timeout and all of them by one budget, so the solver handoff and the decision insert after it
 * always fit inside the runtime's 150 s wall clock.
 *
 *   - 429, 500, 502, 503, 504 and a network error are worth another try: wait (Retry-After when the endpoint sends
 *     one, else 1 s, 2 s, 4 s... with jitter, never more than MAX_WAIT_MS), and move to the next key on a 429,
 *     because a rate limit can be the key's own.
 *   - 401, 403 and 404 are the key's problem: the next key, at once. (A legacy NVCF key can be valid yet point at
 *     a retired function and return 404 -- v14's reason for trying every key.)
 *   - 400 and 422 say the request shape does not suit this model: the next model, at once.
 *   - An answer that does not parse moves to the next model, at once: asking the same model again for the same
 *     board rarely parses differently.
 *   - A timeout moves to the next model, and only if the budget still holds a full attempt.
 *
 * Pure apart from the injected fetch, sleep and clock, so `node --test tests/*.test.mjs` drives it with fake
 * responses. It never sees the board or the depot; it returns what happened, attempt by attempt, with no key in it.
 */

export type ModelKey = { name: string; value: string };

export type AttemptStatus = number | "timeout" | "network" | "unparseable";

export type ModelAttempt = {
  model: string;
  key: string;          // the environment variable's NAME, never its value
  status: AttemptStatus | "ok";
  ms: number;           // the request itself
  wait_ms: number;      // the pause before it
};

export type ModelCallResult = {
  parsed: unknown | null;
  model: string | null;   // the model that answered, null when none did
  raw: string;            // the answer's text, or the last failure in a line
  attempts: ModelAttempt[];
  ms: number;             // the whole call, pauses included
};

export type ModelCallOptions = {
  url: string;
  keys: ModelKey[];
  models: string[];                                  // [primary, fallback, ...]; each is tried triesPerModel times
  body: (model: string) => Record<string, unknown>;  // the request body for a model
  parse: (content: string) => unknown | null;        // the answer, or null when it does not parse
  budgetMs: number;                                  // every attempt and every pause, together
  attemptTimeoutMs: number;                          // one attempt's ceiling
  minAttemptMs: number;                              // never start an attempt with less than this left
  triesPerModel?: number;                            // default 2
  maxAttempts?: number;                              // default models.length * triesPerModel
  fetchImpl?: typeof fetch;
  sleep?: (ms: number) => Promise<void>;
  now?: () => number;
  random?: () => number;
};

export const RETRY_STATUSES: ReadonlySet<number> = new Set([429, 500, 502, 503, 504]);
export const KEY_STATUSES: ReadonlySet<number> = new Set([401, 403, 404]);
export const SHAPE_STATUSES: ReadonlySet<number> = new Set([400, 422]);
export const BASE_WAIT_MS = 1_000;
export const MAX_WAIT_MS = 8_000;

const isTimeout = (error: unknown) =>
  typeof DOMException !== "undefined" && error instanceof DOMException
  && (error.name === "TimeoutError" || error.name === "AbortError");

/** Retry-After as milliseconds: seconds or an HTTP date. Null when absent or unreadable. */
export function retryAfterMs(header: string | null | undefined, nowMs: number): number | null {
  if (header == null) return null;
  const h = header.trim();
  if (h === "") return null;
  if (/^\d+(\.\d+)?$/.test(h)) return Math.round(Number(h) * 1000);
  const at = Date.parse(h);
  return Number.isFinite(at) ? Math.max(at - nowMs, 0) : null;
}

/** The pause before retry number `n` (1 = the first retry): Retry-After when sent, else exponential with jitter. */
export function backoffMs(n: number, retryAfter: number | null, random: () => number = Math.random): number {
  if (retryAfter != null) return Math.min(Math.max(retryAfter, 0), MAX_WAIT_MS);
  const base = BASE_WAIT_MS * 2 ** Math.max(n - 1, 0);
  const jitter = 0.75 + 0.5 * random();   // 0.75x - 1.25x, so passes refused together do not retry together
  return Math.min(Math.round(base * jitter), MAX_WAIT_MS);
}

/** The model call. Never throws: a fetch failure, a timeout or a bad answer is an attempt with a status. */
export async function callModelWithRetry(o: ModelCallOptions): Promise<ModelCallResult> {
  const fetchImpl = o.fetchImpl ?? fetch;
  const sleep = o.sleep ?? ((ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms)));
  const now = o.now ?? Date.now;
  const random = o.random ?? Math.random;
  const tries = Math.max(o.triesPerModel ?? 2, 1);
  const maxAttempts = Math.max(o.maxAttempts ?? o.models.length * tries, 1);
  const t0 = now();
  const attempts: ModelAttempt[] = [];
  let raw = o.keys.length === 0 ? "no key" : o.models.length === 0 ? "no model" : "";
  if (o.keys.length === 0 || o.models.length === 0) return { parsed: null, model: null, raw, attempts, ms: 0 };

  let modelIdx = 0;
  let triesOnModel = 0;
  let keyIdx = 0;
  let retries = 0;
  let wait = 0;
  while (attempts.length < maxAttempts && modelIdx < o.models.length) {
    const left = o.budgetMs - (now() - t0);
    if (left - wait < o.minAttemptMs) break;
    if (wait > 0) await sleep(wait);
    const waited = wait;
    wait = 0;
    const model = o.models[modelIdx];
    const key = o.keys[keyIdx % o.keys.length];
    const timeout = Math.min(o.attemptTimeoutMs, o.budgetMs - (now() - t0));
    const tA = now();
    let status: AttemptStatus | "ok";
    let retryAfter: number | null = null;
    let content = "";
    try {
      const r = await fetchImpl(o.url, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${key.value}` },
        body: JSON.stringify(o.body(model)),
        signal: AbortSignal.timeout(Math.max(timeout, 1)),
      });
      const text = await r.text();
      if (!r.ok) {
        status = r.status;
        retryAfter = retryAfterMs(r.headers?.get?.("retry-after") ?? null, now());
        raw = `HTTP ${r.status}: ${text.slice(0, 240)}`;
      } else {
        let j: any = null;
        try { j = JSON.parse(text); } catch { /* an unreadable body is an unparseable answer */ }
        content = String(j?.choices?.[0]?.message?.content ?? "");
        const parsed = content ? o.parse(content) : null;
        if (parsed != null) {
          attempts.push({ model, key: key.name, status: "ok", ms: now() - tA, wait_ms: waited });
          return { parsed, model, raw: content, attempts, ms: now() - t0 };
        }
        status = "unparseable";
        raw = `unparseable answer from ${model}: ${content.slice(0, 160)}`;
      }
    } catch (error) {
      if (isTimeout(error)) {
        status = "timeout";
        raw = `model timeout after ${Math.round(timeout)} ms`;
      } else {
        status = "network";
        raw = `request error: ${error instanceof Error ? error.message.slice(0, 200) : "unknown"}`;
      }
    }
    attempts.push({ model, key: key.name, status, ms: now() - tA, wait_ms: waited });
    triesOnModel++;

    if (typeof status === "number" && KEY_STATUSES.has(status)) {
      // the key's problem: the next key on the same model, at once. When every key has said so, the next model.
      keyIdx++;
      if (keyIdx % o.keys.length === 0) { modelIdx++; triesOnModel = 0; }
      continue;
    }
    if ((typeof status === "number" && SHAPE_STATUSES.has(status)) || status === "unparseable" || status === "timeout") {
      modelIdx++; triesOnModel = 0;
      continue;
    }
    if ((typeof status === "number" && RETRY_STATUSES.has(status)) || status === "network") {
      retries++;
      wait = backoffMs(retries, retryAfter, random);
      if (status === 429) keyIdx++;
      if (triesOnModel >= tries) { modelIdx++; triesOnModel = 0; }
      continue;
    }
    // anything else (a 3xx, a 418): nothing about another try would differ
    break;
  }
  return { parsed: null, model: null, raw, attempts, ms: now() - t0 };
}

/** One line for the decision row: how the call went, attempt by attempt, with no key in it. */
export function attemptsSummary(attempts: ModelAttempt[]): string {
  return attempts.map((a) => `${a.model.split("/").pop()}:${a.status}${a.wait_ms ? `+${a.wait_ms}ms` : ""}`).join(" ");
}
