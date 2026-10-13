// ottoq-run-blackbox's door and its response budget (edge-functions/_shared/blackbox_auth.ts and run_blackbox.ts), over
// a fake Supabase client. The measurement that asked for it is db/checks/0446; the probes after deploy are there too.
//
// WHAT EACH PART PROVES
//   1. credential  no headers, the public key, a wrong token: 401. The service-role key (Bearer or apikey) and the
//                  operator export token: allowed. The two channels do not cross, and an export token shorter than 32
//                  characters is treated as not set.
//   2. timing      every credential comparison goes through the comparator, every applicable one runs whatever matched
//                  first, the default comparator is the constant-time one, it has one exit (after the fold) and no
//                  branch, and the module compares no credential with ===. The shape check is itself tested against the
//                  bypasses it exists to catch. A wall-clock timing test is not attempted: on a shared runner its noise
//                  is larger than the effect, and a test that passes on noise proves nothing.
//   3. no database a refused request makes no client and reads no body. The discriminating case is v7's own: an
//                  invalid run id, which v7 answered with Postgres's uuid error (HTTP 500), is now answered 401.
//   4. budget      one response carries at most 20 MB, counted in the bytes actually sent, with rows as wide as the
//                  live engine's (db/checks/0446 §1 f): the decision snapshots at 178,627 bytes a row are never read
//                  1,000 at a time; a walk of the cursor returns every row once, in order, and ends; a run under the
//                  budget is v7's bundle exactly, plus export_paging; a cursor is bound to its run.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test, { describe } from "node:test";

import {
  authorizeBlackbox, bearerToken, EXPORT_TOKEN_HEADER, MIN_EXPORT_TOKEN_LENGTH, timingSafeEqualText, UNAUTHORIZED_DETAIL,
  WWW_AUTHENTICATE,
} from "../edge-functions/_shared/blackbox_auth.ts";
import {
  FIRST_READ_ROWS, formatCursor, handleRunBlackbox, NEXT_CURSOR_HEADER, PAGE_SIZE, parseCursor, READ_BYTE_TARGET,
  RESPONSE_BYTE_BUDGET, RESPONSE_RESERVE_BYTES,
} from "../edge-functions/_shared/run_blackbox.ts";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const BASE = "https://x.supabase.co/functions/v1/ottoq-run-blackbox";
// Fakes in the shapes the platform uses. None is a real key.
const SERVICE = "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.c2VydmljZS1zaWduYXR1cmUtZmFrZQ";
const ANON = "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYW5vbiJ9.YW5vbi1zaWduYXR1cmUtZmFrZQ";
const PUBLISHABLE = "sb_publishable_" + "p".repeat(32);
const TOKEN = "f".repeat(64);
const RUN = "816bd28c-e103-40ce-8839-f473af1d6416";
const OTHER_RUN = "57188f55-4503-4c5c-82c8-b42000f73ba2";
const DEPOT = "11111111-1111-1111-1111-111111111111";

const secrets = { serviceRoleKey: SERVICE, exportToken: TOKEN };
const hdrs = (h) => new Headers(h);
const decide = (h, s = secrets, cmp) => authorizeBlackbox(hdrs(h), s, cmp);
const bodyOf = async (res) => { const t = await res.text(); return t ? JSON.parse(t) : null; };
const bytesOf = async (res) => { const b = new Uint8Array(await res.arrayBuffer()); return { n: b.byteLength, body: JSON.parse(new TextDecoder().decode(b)) }; };

// ───────────────────────────────────────────────────────────────────────────── a fake client and world

/** `count` rows whose JSON is exactly `width` bytes (ids are fixed-width so every row is the same size). */
function rowsOf(count, tag, width = 0) {
  const base = JSON.stringify({ id: `${tag}-0000000`, i: 0, pad: "" }).length;
  const pad = "x".repeat(Math.max(0, width - base));
  return Array.from({ length: count }, (_, i) => ({ id: `${tag}-${String(i).padStart(7, "0")}`, i, pad }));
}

function world(over = {}) {
  return {
    latestRun: RUN,
    meta: { black_box_version: "1.0", sim_run_id: RUN, depot_id: DEPOT,
            run: { sim_run_id: RUN, status: "completed", started_at: "2026-10-01T00:00:00Z", ended_at: "2026-10-01T19:06:00Z" },
            executed_code: { ottoq_decide_tick: "CREATE FUNCTION ..." }, data_tables: ["ottoq_big", "ottoq_empty", "ottoq_small"] },
    metaError: null,
    tables: { ottoq_big: rowsOf(3_000, "big", 300), ottoq_empty: [], ottoq_small: rowsOf(10, "small"),
              vehicles: rowsOf(5, "veh"), stalls: rowsOf(3, "stall"), ocpp_sessions: rowsOf(2, "sess") },
    errors: {},
    ...over,
  };
}

function fakeDeps(w = world(), extra = {}, env = { SUPABASE_URL: "https://x.supabase.co", SUPABASE_SERVICE_ROLE_KEY: SERVICE, OTTOQ_BLACKBOX_TOKEN: TOKEN }) {
  const calls = [];
  const logs = [];
  const client = {
    from(table) {
      calls.push(["from", table]);
      const q = {
        select() { return q; }, eq(c, v) { calls.push(["eq", table, c, v]); return q; }, or(f) { calls.push(["or", table, f]); return q; },
        gte() { return q; }, order() { return q; }, limit() { return q; },
        maybeSingle: async () => ({ data: w.latestRun ? { sim_run_id: w.latestRun } : null, error: null }),
        range: async (from, to) => {
          if (w.errors[table]) { calls.push(["range", table, from, to, 0]); return { data: null, error: { message: w.errors[table] } }; }
          const data = (w.tables[table] ?? []).slice(from, to + 1);
          calls.push(["range", table, from, to, data.length]);
          return { data, error: null };
        },
      };
      return q;
    },
    rpc: async (name, args) => {
      calls.push(["rpc", name, args]);
      return w.metaError ? { data: null, error: { message: w.metaError } } : { data: w.meta, error: null };
    },
  };
  const made = [];
  return {
    calls, logs, made,
    deps: {
      env: (k) => env[k],
      createClient: (url, key) => { made.push([url, key]); return client; },
      log: (line) => logs.push(line),
      ...extra,
    },
  };
}

const get = (qs = `?run=${RUN}`, headers = { Authorization: `Bearer ${SERVICE}` }) => new Request(BASE + qs, { headers });
const post = (body, headers = { Authorization: `Bearer ${SERVICE}` }) =>
  new Request(BASE, { method: "POST", headers: { "content-type": "application/json", ...headers }, body: JSON.stringify(body) });

/** Every page of one run, following next_cursor: [{ n: body bytes, body, res }]. */
async function walk(w, extra = {}, headers = { Authorization: `Bearer ${SERVICE}` }, limit = 100) {
  const pages = [];
  let qs = `?run=${RUN}`;
  for (;;) {
    const f = fakeDeps(w, extra);
    const res = await handleRunBlackbox(get(qs, headers), f.deps);
    assert.equal(res.status, 200);
    const { n, body } = await bytesOf(res);
    pages.push({ n, body, res, calls: f.calls });
    assert.equal(res.headers.get(NEXT_CURSOR_HEADER), body.export_paging.next_cursor ?? "none");
    if (body.export_paging.next_cursor === null) return pages;
    qs = body.export_paging.next;
    assert.ok(pages.length < limit, "the walk ends");
  }
}

/** The rows of each relation, pages concatenated in order, as a consumer would merge them. */
function merged(pages) {
  const out = {};
  for (const p of pages) for (const [k, v] of Object.entries(p.body.data)) (out[k] ??= []).push(...v);
  return out;
}

// ───────────────────────────────────────────────────────────────────────────── 1. credential

describe("1. credential", () => {
  test("no headers: refused, nothing compared", async () => {
    const d = await decide({});
    assert.deepEqual(d, { ok: false, via: null, reason: "no_credential", compared: 0, export_token_configured: true });
  });
  test("the public key, as the twin app sends it (apikey + Bearer): refused", async () => {
    const d = await decide({ apikey: ANON, Authorization: `Bearer ${ANON}` });
    assert.equal(d.ok, false);
    assert.equal(d.reason, "not_accepted");
    assert.equal(d.compared, 2);
    assert.equal((await decide({ apikey: PUBLISHABLE, Authorization: `Bearer ${PUBLISHABLE}` })).ok, false);
  });
  test("a wrong export token: refused, also one character off and a prefix", async () => {
    for (const t of ["0".repeat(64), TOKEN.slice(0, 63) + "e", TOKEN.slice(0, 32), TOKEN + "f"]) {
      const d = await decide({ [EXPORT_TOKEN_HEADER]: t });
      assert.equal(d.ok, false, t);
      assert.equal(d.compared, 1);
    }
  });
  test("the service-role key: allowed as a Bearer, as apikey, and either way round", async () => {
    assert.deepEqual(await decide({ Authorization: `Bearer ${SERVICE}` }),
      { ok: true, via: "service_role", reason: "accepted", compared: 1, export_token_configured: true });
    assert.equal((await decide({ apikey: SERVICE })).via, "service_role");
    assert.equal((await decide({ apikey: ANON, Authorization: `Bearer ${SERVICE}` })).ok, true);
    assert.equal((await decide({ apikey: SERVICE, Authorization: `Bearer ${ANON}` })).ok, true);
    assert.equal((await decide({ Authorization: `bearer  ${SERVICE} ` })).ok, true);
  });
  test("the export token: allowed", async () => {
    const d = await decide({ [EXPORT_TOKEN_HEADER]: TOKEN });
    assert.deepEqual(d, { ok: true, via: "export_token", reason: "accepted", compared: 1, export_token_configured: true });
  });
  test("the channels do not cross", async () => {
    assert.equal((await decide({ [EXPORT_TOKEN_HEADER]: SERVICE })).ok, false);   // service key in the token header
    assert.equal((await decide({ Authorization: `Bearer ${TOKEN}` })).ok, false); // token as a Bearer
    assert.equal((await decide({ apikey: TOKEN })).ok, false);                    // token as apikey
  });
  test("an export token shorter than 32 characters is not set", async () => {
    const short = "s".repeat(MIN_EXPORT_TOKEN_LENGTH - 1);
    const d = await decide({ [EXPORT_TOKEN_HEADER]: short }, { serviceRoleKey: SERVICE, exportToken: short });
    assert.equal(d.ok, false);
    assert.equal(d.export_token_configured, false);
    assert.equal(d.compared, 0);
    const ok = "s".repeat(MIN_EXPORT_TOKEN_LENGTH);
    assert.equal((await decide({ [EXPORT_TOKEN_HEADER]: ok }, { serviceRoleKey: SERVICE, exportToken: ok })).ok, true);
  });
  test("unset secrets open nothing, even to empty or blank credentials", async () => {
    for (const s of [{}, { serviceRoleKey: "", exportToken: "" }, { serviceRoleKey: "  ", exportToken: null }]) {
      for (const h of [{}, { Authorization: "Bearer " }, { apikey: "" }, { apikey: "  " }, { [EXPORT_TOKEN_HEADER]: "" }]) {
        assert.equal((await decide(h, s)).ok, false, JSON.stringify([s, h]));
      }
    }
    assert.equal((await decide({ Authorization: `Bearer ${SERVICE}` }, { serviceRoleKey: null, exportToken: TOKEN })).ok, false);
  });
  test("bearerToken reads one token and nothing else", () => {
    assert.equal(bearerToken(`Bearer ${SERVICE}`), SERVICE);
    assert.equal(bearerToken("Basic abc"), null);
    assert.equal(bearerToken("Bearer a b"), null);
    assert.equal(bearerToken(null), null);
  });
});

// ───────────────────────────────────────────────────────────────────────────── 2. timing

const stripComments = (s) => s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/[^\n]*/g, "");

/** What is wrong with the comparator's shape, given the comment-stripped module source; [] means nothing. It must
 *  hash both sides, fold every byte with no early exit, have exactly one exit and no branch, and call no string
 *  comparison. Each clause is here because a bypass passed the clauses before it (the first review added
 *  `if (presented.localeCompare(secret) !== 0) return false;` and 27 tests still passed). */
function comparatorShapeProblems(src) {
  const start = src.indexOf("async function timingSafeEqualText");
  const end = src.indexOf("export function bearerToken");
  if (start < 0 || end < start) return ["timingSafeEqualText not found"];
  const fn = src.slice(start, end);
  const problems = [];
  if (!/sha256\(presented\),\s*sha256\(secret\)/.test(fn)) problems.push("does not hash both sides");
  if (!/diff \|= a\[i\] \^ b\[i\]/.test(fn)) problems.push("does not fold every byte's XOR");
  const returns = fn.match(/\breturn\b/g) ?? [];
  if (returns.length !== 1) problems.push(`has ${returns.length} returns, not one`);
  const fold = fn.indexOf("diff |=");
  if (fold < 0 || fn.indexOf("return") < fold) problems.push("returns before the fold");
  if (/\bif\s*\(|\bswitch\s*\(|\bbreak\b|\bthrow\b|&&|\|\|/.test(fn)) problems.push("branches or short-circuits");
  if (/\.(localeCompare|startsWith|endsWith|includes|indexOf|search|match)\s*\(/.test(fn)) problems.push("calls a string comparison");
  if (/\b(presented|secret)\b\s*(?:===|!==|==|!=)(?!\s*(?:null|undefined)\b)/.test(fn)) problems.push("compares a credential with ==");
  return problems;
}

describe("2. timing-safe comparison", () => {
  test("timingSafeEqualText: equal, one byte off, prefix, longer, empty secret", async () => {
    assert.equal(await timingSafeEqualText(TOKEN, TOKEN), true);
    assert.equal(await timingSafeEqualText(TOKEN.slice(0, 63) + "0", TOKEN), false);
    assert.equal(await timingSafeEqualText(TOKEN.slice(0, 10), TOKEN), false);
    assert.equal(await timingSafeEqualText(TOKEN + "f", TOKEN), false);
    assert.equal(await timingSafeEqualText("", ""), false);
    assert.equal(await timingSafeEqualText("x", ""), false);
  });
  test("every comparison goes through the comparator, and every one runs after the first match", async () => {
    const seen = [];
    const spy = async (p, s) => { seen.push([p, s]); return timingSafeEqualText(p, s); };
    const d = await decide({ Authorization: `Bearer ${SERVICE}`, apikey: SERVICE, [EXPORT_TOKEN_HEADER]: TOKEN }, secrets, spy);
    assert.equal(d.ok, true);
    assert.equal(d.via, "service_role");
    assert.equal(d.compared, 3);
    assert.deepEqual(seen, [[SERVICE, SERVICE], [SERVICE, SERVICE], [TOKEN, TOKEN]]);
    // and a comparator that says no is obeyed even when the strings are equal: nothing decides around it
    const never = async () => false;
    assert.equal((await decide({ Authorization: `Bearer ${SERVICE}` }, secrets, never)).ok, false);
  });
  test("the comparator has one exit, after the fold, and no branch", () => {
    const src = stripComments(readFileSync(join(ROOT, "edge-functions/_shared/blackbox_auth.ts"), "utf8"));
    assert.deepEqual(comparatorShapeProblems(src), []);
    assert.match(src, /crypto\.subtle\.digest\("SHA-256"/);
    // the shape check is live: each bypass below is one line added to the real comparator, and each is caught
    const at = src.indexOf("const [a, b] = await Promise.all");
    const inject = (line) => src.slice(0, at) + line + "\n  " + src.slice(at);
    for (const bypass of [
      "if (presented.localeCompare(secret) !== 0) return false;",          // the review's bypass
      "if (presented === secret) return true;",
      "if (presented.length !== secret.length) return false;",
      "const fast = presented.startsWith(secret);",
      "return presented == secret;",
    ]) {
      assert.notDeepEqual(comparatorShapeProblems(inject(bypass)), [], bypass);
    }
    const fold = src.indexOf("for (let i = 0; i < a.length; i++)");
    assert.notDeepEqual(comparatorShapeProblems(src.slice(0, fold) + "for (let i = 0; i < a.length; i++) { if (a[i] !== b[i]) return false; }\n  " + src.slice(fold)), []);
  });
  test("the handler's default comparator is the constant-time one, and the module never compares a credential with ==", () => {
    const src = stripComments(readFileSync(join(ROOT, "edge-functions/_shared/blackbox_auth.ts"), "utf8"));
    assert.match(src, /compare:\s*Compare\s*=\s*timingSafeEqualText/);
    // no credential meets a secret through ==/=== anywhere (comparisons with null/undefined/true are presence checks)
    const names = "secret|serviceKey|exportToken|bearer|apikey|token|presented|SERVICE|TOKEN";
    const op = "(?:===|!==|==|!=)(?!=)";
    assert.doesNotMatch(src, new RegExp(`\\b(${names})\\b\\s*${op}(?!\\s*(?:null|undefined|true)\\b)`));
    assert.doesNotMatch(src, new RegExp(`${op}\\s*\\b(${names})\\b(?!\\.)`));
    // the check above is live: it trips on the comparison it exists to forbid
    assert.match("if (token === secret) return true;", new RegExp(`\\b(${names})\\b\\s*${op}(?!\\s*(?:null|undefined|true)\\b)`));
    assert.match("if (a == serviceKey) return true;", new RegExp(`${op}\\s*\\b(${names})\\b(?!\\.)`));
    // and the handler passes the injected comparator through, never one of its own
    const h = readFileSync(join(ROOT, "edge-functions/_shared/run_blackbox.ts"), "utf8");
    assert.match(h, /authorizeBlackbox\(\s*req\.headers,[\s\S]*?deps\.compare,\s*\)/);
  });
});

// ───────────────────────────────────────────────────────────────────────────── 3. no database without a credential

describe("3. a refused request touches no database", () => {
  const refusals = [
    ["no headers", {}],
    ["the public key (twin app's download)", { apikey: ANON, Authorization: `Bearer ${ANON}` }],
    ["the publishable key", { apikey: PUBLISHABLE }],
    ["a wrong export token", { [EXPORT_TOKEN_HEADER]: "0".repeat(64) }],
  ];
  for (const [name, headers] of refusals) {
    test(`${name}: 401, no client, no query`, async () => {
      const f = fakeDeps();
      const res = await handleRunBlackbox(get("?run=not-a-uuid", headers), f.deps);
      assert.equal(res.status, 401);
      assert.equal(f.made.length, 0);
      assert.deepEqual(f.calls, []);
      assert.deepEqual(await bodyOf(res), { error: "unauthorized", detail: UNAUTHORIZED_DETAIL });
      assert.equal(res.headers.get("www-authenticate"), WWW_AUTHENTICATE);
      assert.equal(res.headers.get("access-control-allow-origin"), "*");
      assert.equal(f.logs.length, 1);
      assert.match(f.logs[0], /"auth":"refused"/);
      for (const secret of [SERVICE, TOKEN]) assert.ok(!f.logs[0].includes(secret));
    });
  }
  test("a POST without a credential: 401 and the body is never read", async () => {
    const f = fakeDeps();
    const req = post({ run: RUN }, {});
    const res = await handleRunBlackbox(req, f.deps);
    assert.equal(res.status, 401);
    assert.equal(req.bodyUsed, false);
    assert.equal(f.made.length, 0);
  });
  test("OPTIONS answers the preflight with no credential and no client; the token header is allowed, the cursor exposed", async () => {
    const f = fakeDeps();
    const res = await handleRunBlackbox(new Request(BASE, { method: "OPTIONS" }), f.deps);
    assert.equal(res.status, 200);
    assert.equal(f.made.length, 0);
    assert.match(res.headers.get("access-control-allow-headers"), new RegExp(`\\b${EXPORT_TOKEN_HEADER}\\b`));
    assert.match(res.headers.get("access-control-allow-headers"), /\bapikey\b/);
    const exposed = res.headers.get("access-control-expose-headers").toLowerCase().split(/,\s*/);
    assert.ok(exposed.includes(NEXT_CURSOR_HEADER.toLowerCase()));
    assert.ok(exposed.includes("content-disposition"));
  });
  test("a malformed cursor, or one bound to another run, is a 400 before the database, once the credential passes", async () => {
    const bad = ["garbage", `v1.0.0.ottoq_big.${RUN}`, "v1.1.0.ottoq_big.not-a-uuid", `v2.1.0.ottoq_big.${RUN}`,
                 `v1.1.-5.ottoq_big.${RUN}`, `v1.1.0.Robert'); DROP TABLE x;--.${RUN}`];
    for (const c of bad) {
      const f = fakeDeps();
      const res = await handleRunBlackbox(get(`?run=${RUN}&cursor=${encodeURIComponent(c)}`), f.deps);
      assert.equal(res.status, 400, c);
      assert.equal(f.made.length, 0, c);
    }
    const f = fakeDeps();
    const res = await handleRunBlackbox(get(`?run=${OTHER_RUN}&cursor=v1.1.0.ottoq_big.${RUN}`), f.deps);
    assert.equal(res.status, 400);
    assert.match((await bodyOf(res)).error, /another run/);
    assert.equal(f.made.length, 0);
  });
});

// ───────────────────────────────────────────────────────────────────────────── 4. the response budget and the cursor

describe("4. at most 20 MB a response, counted in bytes sent, with a cursor", () => {
  test("parseCursor and formatCursor", () => {
    const c = { page: 3, offset: 50_000, relation: "ottoq_rule_evaluations", run: RUN };
    assert.deepEqual(parseCursor(formatCursor(c)), c);
    const dollar = { page: 1, offset: 0, relation: "ottoq_a$b", run: RUN }; // a Postgres identifier may carry $
    assert.deepEqual(parseCursor(formatCursor(dollar)), dollar);
    assert.equal(parseCursor(null), undefined);
    assert.equal(parseCursor(""), undefined);
    for (const bad of [3, {}, "v1", `v1.0.0.x.${RUN}`, `v1.1.0.x.${RUN}.extra`, `v1.1.0.Upper.${RUN}x`]) assert.equal(parseCursor(bad), null, String(bad));
  });

  test("a run under the budget is v7's bundle exactly, in one response, plus export_paging", async () => {
    const w = world();
    const f = fakeDeps(w);
    const res = await handleRunBlackbox(get(), f.deps);
    assert.equal(res.status, 200);
    const { n, body } = await bytesOf(res);
    const { export_paging, ...rest } = body;
    // what v7 built: {...meta, data} with every relation a key, empty ones included
    const v7 = { ...w.meta, data: { ottoq_big: w.tables.ottoq_big, ottoq_empty: [], ottoq_small: w.tables.ottoq_small,
                                     vehicles: w.tables.vehicles, stalls: w.tables.stalls, ocpp_sessions: w.tables.ocpp_sessions } };
    assert.deepEqual(rest, v7);
    assert.deepEqual(Object.keys(body), [...Object.keys(w.meta), "data", "export_paging"]);
    assert.deepEqual(Object.keys(body.data), ["ottoq_big", "ottoq_empty", "ottoq_small", "vehicles", "stalls", "ocpp_sessions"]);
    assert.equal(export_paging.complete, true);
    assert.equal(export_paging.next_cursor, null);
    assert.equal(export_paging.page, 0);
    assert.equal(export_paging.response_byte_budget, RESPONSE_BYTE_BUDGET);
    assert.ok(export_paging.relations.every((r) => r.complete && r.first_row === 0));
    assert.equal(export_paging.warning, null);
    assert.equal(res.headers.get(NEXT_CURSOR_HEADER), "none");
    assert.match(res.headers.get("content-disposition"), /^attachment; filename="ottoq-blackbox-816bd28c-\d{4}-\d\d-\d\d-\d\d-\d\d-\d\d\.json"$/);
    assert.ok(n < 2_000_000);
    // the client was made with the service key, and no read asked for more than PAGE_SIZE rows
    assert.deepEqual(f.made, [["https://x.supabase.co", SERVICE]]);
    for (const c of f.calls.filter((c) => c[0] === "range")) assert.ok(c[3] - c[2] + 1 <= PAGE_SIZE, JSON.stringify(c));
  });

  test("rows as wide as the live engine's, at the production budget: every response within 20 MB, every row once", async () => {
    // widths measured on run 816bd28c, 2026-10-13 (db/checks/0446 §1 f); counts scaled down so the test stays quick
    const widths = { ottoq_comms_messages: 1_198, ottoq_decision_snapshots: 178_627, ottoq_decisions: 2_903,
                     ottoq_rule_evaluation_effect: 544, ottoq_rule_evaluations: 1_132, ottoq_tick_clock_log: 359 };
    const counts = { ottoq_comms_messages: 5_000, ottoq_decision_snapshots: 300, ottoq_decisions: 8_000,
                     ottoq_rule_evaluation_effect: 20_000, ottoq_rule_evaluations: 20_000, ottoq_tick_clock_log: 2_564 };
    const w = world();
    w.meta = { ...w.meta, executed_code: { ottoq_decide_tick: "x".repeat(316_000) }, data_tables: Object.keys(widths).sort() };
    w.tables = { vehicles: rowsOf(116, "veh", 900), stalls: rowsOf(158, "stall", 600), ocpp_sessions: rowsOf(491, "sess", 800) };
    for (const t of Object.keys(widths)) w.tables[t] = rowsOf(counts[t], t, widths[t]);
    const totalBytes = Object.keys(widths).reduce((s, t) => s + widths[t] * counts[t], 0);
    assert.ok(totalBytes > 5 * RESPONSE_BYTE_BUDGET, "the fixture is several responses' worth");

    const pages = await walk(w);
    for (const p of pages) assert.ok(p.n <= RESPONSE_BYTE_BUDGET, `page ${p.body.export_paging.page}: ${p.n} bytes`);
    assert.ok(pages.length >= Math.ceil(totalBytes / RESPONSE_BYTE_BUDGET), `${pages.length} pages`);
    assert.ok(pages.length <= Math.ceil(totalBytes / (RESPONSE_BYTE_BUDGET - RESPONSE_RESERVE_BYTES - 400_000)) + 1, `${pages.length} pages`);
    // pages are numbered, file names say which, every page repeats the header, and only the last is complete
    pages.forEach((p, k) => {
      assert.equal(p.body.export_paging.page, k);
      assert.equal(p.body.sim_run_id, RUN);
      assert.equal(p.body.executed_code.ottoq_decide_tick.length, 316_000);
      assert.equal(p.body.export_paging.complete, k === pages.length - 1);
      if (k > 0) assert.match(p.res.headers.get("content-disposition"), new RegExp(`-p${k}\\.json"$`));
    });
    // merged, every relation is whole: every row once, in order
    const all = merged(pages);
    for (const t of [...Object.keys(widths), "vehicles", "stalls", "ocpp_sessions"]) {
      assert.equal(all[t].length, w.tables[t].length, t);
      assert.deepEqual(all[t].map((r) => r.i), w.tables[t].map((r) => r.i), t);
    }
    // reads are sized by width: no read over PAGE_SIZE rows, a relation's first read in a request is FIRST_READ_ROWS,
    // and the wide snapshots are never read more than READ_BYTE_TARGET at a time
    let snapshotReads = 0;
    for (const p of pages) {
      const firstSeen = new Set();
      for (const c of p.calls.filter((c) => c[0] === "range")) {
        const [, table, from, to, got] = c;
        assert.ok(to - from + 1 <= PAGE_SIZE, JSON.stringify(c));
        if (!firstSeen.has(table)) { firstSeen.add(table); assert.equal(to - from + 1, FIRST_READ_ROWS, JSON.stringify(c)); }
        else if (widths[table]) assert.ok(got * widths[table] <= READ_BYTE_TARGET, JSON.stringify(c));
        if (table === "ottoq_decision_snapshots") { snapshotReads++; assert.ok(to - from + 1 <= FIRST_READ_ROWS, JSON.stringify(c)); }
      }
    }
    assert.ok(snapshotReads >= Math.ceil(300 / FIRST_READ_ROWS));
  });

  test("a walk at a small budget, over mixed widths and an empty relation: no gap, no repeat, and it ends", async () => {
    const w = world({ tables: { ottoq_big: rowsOf(3_000, "big", 300), ottoq_empty: [], ottoq_small: rowsOf(40, "small", 9_000),
                                vehicles: rowsOf(5, "veh"), stalls: rowsOf(3, "stall"), ocpp_sessions: rowsOf(2, "sess") } });
    const budget = 150_000;
    const pages = await walk(w, { responseByteBudget: budget });
    assert.ok(pages.length > 5);
    for (const p of pages) assert.ok(p.n <= budget, String(p.n));
    const all = merged(pages);
    for (const t of Object.keys(w.tables)) assert.deepEqual((all[t] ?? []).map((r) => r.id), w.tables[t].map((r) => r.id), t);
    // a relation split across pages starts each continuation where the last page stopped
    const big = pages.flatMap((p) => p.body.export_paging.relations.filter((r) => r.name === "ottoq_big"));
    for (let k = 1; k < big.length; k++) assert.equal(big[k].first_row, big[k - 1].first_row + big[k - 1].rows);
  });

  test("a single row wider than the budget still goes, alone, and the walk ends", async () => {
    const w = world({ tables: { ottoq_big: rowsOf(3, "big", 250_000), ottoq_empty: [], ottoq_small: rowsOf(2, "small"),
                                vehicles: [], stalls: [], ocpp_sessions: [] } });
    const pages = await walk(w, { responseByteBudget: 100_000 });
    assert.equal(merged(pages).ottoq_big.length, 3);
    assert.ok(pages.every((p) => p.body.export_paging.relations.reduce((s, r) => s + r.rows, 0) >= 1));
  });

  test("a later page is bound to its run: a cursor alone reads that run, never the latest", async () => {
    const w = world({ latestRun: OTHER_RUN });
    const f = fakeDeps(w);
    const res = await handleRunBlackbox(get(`?cursor=v1.1.0.ottoq_small.${RUN}`), f.deps);
    assert.equal(res.status, 200);
    assert.deepEqual(f.calls.find((c) => c[0] === "rpc"), ["rpc", "ottoq_run_blackbox_meta", { p_sim_run_id: RUN }]);
    assert.ok(!f.calls.some((c) => c[1] === "ottoq_sim_runs"));
    const b = await bodyOf(res);
    assert.deepEqual(Object.keys(b.data), ["ottoq_small", "vehicles", "stalls", "ocpp_sessions"]);
    assert.equal(b.export_paging.cursor, `v1.1.0.ottoq_small.${RUN}`);
    // the same through a POST body
    const g = fakeDeps(w);
    const r2 = await handleRunBlackbox(post({ cursor: `v1.2.5.ottoq_small.${RUN}` }), g.deps);
    assert.equal(r2.status, 200);
    const b2 = await bodyOf(r2);
    assert.equal(b2.export_paging.page, 2);
    assert.equal(b2.data.ottoq_small.length, 5);
    assert.match(r2.headers.get("content-disposition"), /-p2\.json"$/);
  });

  test("a cursor naming a relation the export no longer lists: 409", async () => {
    const res = await handleRunBlackbox(get(`?run=${RUN}&cursor=v1.1.0.ottoq_gone.${RUN}`), fakeDeps().deps);
    assert.equal(res.status, 409);
  });

  test("a run that has not ended says so on every page", async () => {
    const w = world();
    w.meta = { ...w.meta, run: { ...w.meta.run, status: "running", ended_at: null } };
    const b = await bodyOf(await handleRunBlackbox(get(), fakeDeps(w).deps));
    assert.equal(b.export_paging.run_status, "running");
    assert.match(b.export_paging.warning, /has not ended/);
  });

  test("the export token gets the same bundle", async () => {
    const res = await handleRunBlackbox(get(`?run=${RUN}`, { [EXPORT_TOKEN_HEADER]: TOKEN }), fakeDeps().deps);
    assert.equal(res.status, 200);
    assert.equal((await bodyOf(res)).data.ottoq_big.length, 3_000);
  });

  test("unchanged from v7: the default run, the meta failure, the no-run 404, and _export_error rows", async () => {
    let f = fakeDeps();
    let b = await bodyOf(await handleRunBlackbox(get(""), f.deps));
    assert.ok(f.calls.some((c) => c[0] === "eq" && c[1] === "ottoq_sim_runs" && c[2] === "run_by" && c[3] === "operator_demo"));
    assert.deepEqual(f.calls.find((c) => c[0] === "rpc"), ["rpc", "ottoq_run_blackbox_meta", { p_sim_run_id: RUN }]);
    assert.equal(b.sim_run_id, RUN);

    f = fakeDeps(world({ latestRun: null }));
    let res = await handleRunBlackbox(get(""), f.deps);
    assert.equal(res.status, 404);
    assert.deepEqual(await bodyOf(res), { error: "no run found" });

    f = fakeDeps(world({ metaError: 'invalid input syntax for type uuid: "x"' }));
    res = await handleRunBlackbox(get("?run=x"), f.deps);
    assert.equal(res.status, 500);
    assert.deepEqual(await bodyOf(res), { error: 'invalid input syntax for type uuid: "x"' });

    f = fakeDeps(world({ errors: { ottoq_small: "permission denied" } }));
    b = await bodyOf(await handleRunBlackbox(get(), f.deps));
    assert.deepEqual(b.data.ottoq_small, [{ _export_error: "permission denied" }]);
    const small = b.export_paging.relations.find((r) => r.name === "ottoq_small");
    assert.equal(small.complete, true);
    assert.equal(small.error, "permission denied");
    assert.equal(b.export_paging.complete, true);

    // vehicles keep v7's filter: the run's own cars or the depot's
    f = fakeDeps();
    await handleRunBlackbox(get(), f.deps);
    assert.ok(f.calls.some((c) => c[0] === "or" && c[1] === "vehicles" && c[2] === `owning_sim_run_id.eq.${RUN},current_depot_id.eq.${DEPOT}`));
  });

  test("the log lines carry the page and its size, and no key", async () => {
    const f = fakeDeps();
    await handleRunBlackbox(get(), f.deps);
    assert.equal(f.logs.length, 2);
    assert.match(f.logs[0], /"auth":"accepted","via":"service_role"/);
    assert.match(f.logs[1], /"page":0,"bytes":\d+/);
    for (const l of f.logs) for (const secret of [SERVICE, TOKEN]) assert.ok(!l.includes(secret));
  });
});
