import assert from "node:assert/strict";
import test from "node:test";

import {
  BASE_WAIT_MS,
  MAX_WAIT_MS,
  attemptsSummary,
  backoffMs,
  callModelWithRetry,
  retryAfterMs,
} from "../edge-functions/_shared/agent_model_call.ts";

// edge function v23: the orchestrator's model call, retries and fallback model. Driven with a fake fetch, a fake
// clock and a recording sleep, so every pause and every attempt is asserted rather than waited for.

const PRIMARY = "nvidia/nemotron-3-ultra-550b-a55b";
const FALLBACK = "nvidia/nemotron-3-super-120b-a12b";
const KEYS = [{ name: "NVIDIA_API_KEY_NEMOTRON", value: "secret-one" }, { name: "NVIDIA_API_KEY", value: "secret-two" }];

function answer(obj) {
  return { status: 200, body: JSON.stringify({ choices: [{ message: { content: JSON.stringify(obj) } }] }) };
}

/** A scripted endpoint: each call takes the next reply; a reply may advance the clock (`ms`) or time out. */
function rig(replies, { budgetMs = 90_000, attemptTimeoutMs = 75_000, minAttemptMs = 12_000, keys = KEYS,
                        models = [PRIMARY, FALLBACK], maxAttempts = undefined } = {}) {
  let clock = 1_000_000;
  const calls = [];
  const sleeps = [];
  const fetchImpl = async (url, init) => {
    const body = JSON.parse(init.body);
    calls.push({ url, model: body.model, auth: init.headers.Authorization, temperature: body.temperature, top_p: body.top_p });
    const r = replies.shift();
    if (!r) throw new Error("no scripted reply left");
    clock += r.ms ?? 100;
    if (r.timeout) throw new DOMException("The operation timed out.", "TimeoutError");
    if (r.network) throw new TypeError("fetch failed");
    return {
      ok: r.status >= 200 && r.status < 300,
      status: r.status,
      headers: { get: (h) => (h.toLowerCase() === "retry-after" ? (r.retryAfter ?? null) : null) },
      text: async () => r.body ?? "",
    };
  };
  const run = () => callModelWithRetry({
    url: "https://example.invalid/v1/chat/completions",
    keys,
    models, maxAttempts,
    body: (model) => ({ model, ...(model === PRIMARY ? { temperature: 0.1 } : { temperature: 1.0, top_p: 0.95 }) }),
    parse: (content) => { try { const o = JSON.parse(content); return Array.isArray(o.actions) ? o : null; } catch { return null; } },
    budgetMs, attemptTimeoutMs, minAttemptMs,
    fetchImpl,
    sleep: async (ms) => { sleeps.push(ms); clock += ms; },
    now: () => clock,
    random: () => 0.5,   // jitter factor exactly 1.0
  });
  return { run, calls, sleeps };
}

test("an answer on the first try is one attempt and no pause", async () => {
  const r = rig([answer({ actions: [] })]);
  const out = await r.run();
  assert.equal(out.model, PRIMARY);
  assert.deepEqual(out.parsed, { actions: [] });
  assert.equal(out.attempts.length, 1);
  assert.equal(out.attempts[0].status, "ok");
  assert.deepEqual(r.sleeps, []);
});

test("a 429 waits, moves to the next key and tries the primary again", async () => {
  const r = rig([{ status: 429, body: '{"status":429,"title":"Too Many Requests"}' }, answer({ actions: [] })]);
  const out = await r.run();
  assert.equal(out.model, PRIMARY);
  assert.deepEqual(r.sleeps, [BASE_WAIT_MS]);
  assert.equal(r.calls[0].auth, "Bearer secret-one");
  assert.equal(r.calls[1].auth, "Bearer secret-two");
  assert.deepEqual(out.attempts.map((a) => a.status), [429, "ok"]);
  assert.equal(out.attempts[1].wait_ms, BASE_WAIT_MS);
});

test("Retry-After is honoured, and capped", async () => {
  const r = rig([{ status: 429, retryAfter: "3" }, answer({ actions: [] })]);
  await r.run();
  assert.deepEqual(r.sleeps, [3_000]);
  const capped = rig([{ status: 503, retryAfter: "120" }, answer({ actions: [] })]);
  await capped.run();
  assert.deepEqual(capped.sleeps, [MAX_WAIT_MS]);
});

test("two refusals of the primary go to the fallback model, with its own sampling", async () => {
  const r = rig([{ status: 503 }, { status: 503 }, answer({ actions: [] })]);
  const out = await r.run();
  assert.equal(out.model, FALLBACK);
  assert.deepEqual(r.calls.map((c) => c.model), [PRIMARY, PRIMARY, FALLBACK]);
  assert.deepEqual(r.sleeps, [BASE_WAIT_MS, 2 * BASE_WAIT_MS]);   // 1 s, then 2 s
  assert.equal(r.calls[0].temperature, 0.1);
  assert.equal(r.calls[2].temperature, 1.0);
  assert.equal(r.calls[2].top_p, 0.95);
  // a 503 is the service's, not the key's: the key does not change
  assert.equal(r.calls[0].auth, r.calls[1].auth);
});

test("four refusals end the call with no answer and the last error", async () => {
  const r = rig([{ status: 429 }, { status: 503 }, { status: 503 }, { status: 503, body: "Service temporarily unavailable" }]);
  const out = await r.run();
  assert.equal(out.parsed, null);
  assert.equal(out.model, null);
  assert.equal(out.attempts.length, 4);
  assert.match(out.raw, /^HTTP 503: Service temporarily unavailable/);
  assert.deepEqual(out.attempts.map((a) => a.model), [PRIMARY, PRIMARY, FALLBACK, FALLBACK]);
});

test("a key the endpoint refuses (401/403/404) goes to the next key at once", async () => {
  const r = rig([{ status: 404 }, answer({ actions: [] })]);
  const out = await r.run();
  assert.equal(out.model, PRIMARY);
  assert.deepEqual(r.sleeps, []);
  assert.equal(r.calls[1].auth, "Bearer secret-two");
  // every key refused: the next model, still at once
  const all = rig([{ status: 401 }, { status: 403 }, answer({ actions: [] })]);
  const out2 = await all.run();
  assert.equal(out2.model, FALLBACK);
  assert.deepEqual(all.sleeps, []);
});

test("a request shape the model rejects (400) goes to the next model at once", async () => {
  const r = rig([{ status: 400, body: "unsupported parameter" }, answer({ actions: [] })]);
  const out = await r.run();
  assert.equal(out.model, FALLBACK);
  assert.deepEqual(r.sleeps, []);
});

test("an answer that does not parse goes to the next model, not the same one again", async () => {
  const r = rig([{ status: 200, body: JSON.stringify({ choices: [{ message: { content: "I think the depot..." } }] }) },
                 answer({ actions: [{ type: "directive", text: "ok" }] })]);
  const out = await r.run();
  assert.equal(out.model, FALLBACK);
  assert.deepEqual(out.attempts.map((a) => a.status), ["unparseable", "ok"]);
});

test("a timeout tries the fallback only when the budget still holds a full attempt", async () => {
  // 75 s timeout leaves 15 s of a 90 s budget: one more attempt fits (minimum 12 s)
  const fits = rig([{ timeout: true, ms: 75_000 }, answer({ actions: [] })]);
  const out = await fits.run();
  assert.equal(out.model, FALLBACK);
  assert.deepEqual(out.attempts.map((a) => a.status), ["timeout", "ok"]);
  // 80 s gone leaves 10 s: no attempt starts, and the timeout is the answer
  const late = rig([{ timeout: true, ms: 80_000 }]);
  const out2 = await late.run();
  assert.equal(out2.parsed, null);
  assert.equal(out2.attempts.length, 1);
  assert.match(out2.raw, /^model timeout after/);
});

test("a pause that would leave too little budget is not taken", async () => {
  // a 429 at 79 s: a 1 s pause would leave 10 s, under the 12 s minimum, so the call ends without waiting
  const r = rig([{ status: 429, ms: 79_000 }]);
  const out = await r.run();
  assert.equal(out.attempts.length, 1);
  assert.deepEqual(r.sleeps, []);
});

test("a network error is retried like a 5xx", async () => {
  const r = rig([{ network: true }, answer({ actions: [] })]);
  const out = await r.run();
  assert.equal(out.model, PRIMARY);
  assert.deepEqual(out.attempts.map((a) => a.status), ["network", "ok"]);
  assert.deepEqual(r.sleeps, [BASE_WAIT_MS]);
});

test("no key means no attempt", async () => {
  const r = rig([], { keys: [] });
  const out = await r.run();
  assert.equal(out.attempts.length, 0);
  assert.equal(out.raw, "no key");
});

test("the attempts carry key names and never a key", async () => {
  const r = rig([{ status: 429 }, { status: 503 }, answer({ actions: [] })]);
  const out = await r.run();
  const text = JSON.stringify(out.attempts) + attemptsSummary(out.attempts);
  assert.doesNotMatch(text, /secret-/);
  assert.match(text, /NVIDIA_API_KEY/);
  assert.equal(attemptsSummary(out.attempts), "nemotron-3-ultra-550b-a55b:429 nemotron-3-ultra-550b-a55b:503+1000ms nemotron-3-super-120b-a12b:ok+2000ms");
});

test("backoff doubles with jitter inside 0.75-1.25x, and Retry-After reads seconds or a date", () => {
  assert.equal(backoffMs(1, null, () => 0.5), 1_000);
  assert.equal(backoffMs(2, null, () => 0.5), 2_000);
  assert.equal(backoffMs(3, null, () => 0), 3_000);       // 4 s x 0.75
  assert.equal(backoffMs(3, null, () => 1), 5_000);       // 4 s x 1.25
  assert.equal(backoffMs(9, null, () => 1), MAX_WAIT_MS);
  assert.equal(retryAfterMs("2", 0), 2_000);
  assert.equal(retryAfterMs("1.5", 0), 1_500);
  assert.equal(retryAfterMs(null, 0), null);
  assert.equal(retryAfterMs("soon", 0), null);
  const now = Date.parse("2026-10-07T18:00:00Z");
  assert.equal(retryAfterMs("Wed, 07 Oct 2026 18:00:04 GMT", now), 4_000);
});

// v33 (G543). Run a95e51a3, 2026-11-13: the primary timed out at 75 s and the one fallback answered 404 on both keys,
// so the pass had no answer. The chain walks past a model no key may call.
const LIGHT = "nvidia/nemotron-3.5-lightning-30b-a3b";
const CHAIN = [PRIMARY, LIGHT, FALLBACK];

test("G543: a fallback that every key answers 404 for is walked past, and the next model answers", async () => {
  const r = rig([{ timeout: true, ms: 75_000 }, { status: 404, ms: 40 }, { status: 404, ms: 55 }, answer({ actions: [] })],
    { models: [PRIMARY, FALLBACK, LIGHT], maxAttempts: 3 * 2 });
  const out = await r.run();
  assert.equal(out.model, LIGHT);
  assert.deepEqual(out.attempts.map((a) => [a.model, a.status]),
    [[PRIMARY, "timeout"], [FALLBACK, 404], [FALLBACK, 404], [LIGHT, "ok"]]);
  assert.deepEqual(r.sleeps, []);                       // a 404 is the next key at once, never a pause
});

test("G543: with the default cap of two attempts a model, the same walk ran out before the model that answers", async () => {
  const r = rig([{ status: 503, ms: 100 }, { status: 503, ms: 100 }, { status: 404, ms: 40 }, { status: 404, ms: 55 },
                 { status: 404, ms: 40 }, { status: 404, ms: 40 }, answer({ actions: [] })],
    { models: [PRIMARY, FALLBACK, "nvidia/also-gone", LIGHT] });        // default cap: 4 models x 2 = 8, enough here
  assert.equal((await r.run()).model, LIGHT);
  const capped = rig([{ status: 404, ms: 40 }, { status: 404, ms: 55 }, { status: 404, ms: 40 }, answer({ actions: [] })],
    { models: [FALLBACK, LIGHT], keys: [...KEYS, { name: "NVIDIA_API_KEY_CUOPT", value: "secret-three" }] });
  const out = await capped.run();                       // three keys, two models: the default cap of 4 ends on the first answer
  assert.equal(out.model, LIGHT);
  assert.equal(out.attempts.length, 4);
});

test("G543: a model's key refusals are counted for that model, wherever the key index stands", async () => {
  // a 429 moves the key index to the second key; the fallback must still be tried on BOTH keys before it is given up
  const r = rig([{ status: 429, ms: 100 }, { status: 503, ms: 100 }, { status: 404, ms: 40 }, answer({ actions: [] })],
    { models: [PRIMARY, FALLBACK] });
  const out = await r.run();
  assert.equal(out.model, FALLBACK);
  assert.deepEqual(out.attempts.map((a) => [a.model, a.key, a.status]),
    [[PRIMARY, "NVIDIA_API_KEY_NEMOTRON", 429], [PRIMARY, "NVIDIA_API_KEY", 503],
     [FALLBACK, "NVIDIA_API_KEY", 404], [FALLBACK, "NVIDIA_API_KEY_NEMOTRON", "ok"]]);
});

test("G543: the chain keeps the dead model last, so it costs nothing while it is dead and answers if it returns", async () => {
  const r = rig([{ timeout: true, ms: 75_000 }, answer({ actions: [] })], { models: CHAIN, maxAttempts: 6 });
  const out = await r.run();
  assert.equal(out.model, LIGHT);
  assert.equal(out.attempts.length, 2);
});
