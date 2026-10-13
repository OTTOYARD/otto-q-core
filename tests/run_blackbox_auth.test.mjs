// ottoq-run-blackbox's door and cap (edge-functions/_shared/blackbox_auth.ts and run_blackbox.ts), over a fake
// Supabase client. The measurement that asked for it is db/checks/0446; the probes after deploy are in that file too.
//
// WHAT EACH PART PROVES
//   1. credential  no headers, the public key, a wrong token: 401. The service-role key (Bearer or apikey) and the
//                  operator export token: allowed. The two channels do not cross, and an export token shorter than 32
//                  characters is treated as not set.
//   2. timing      every credential comparison goes through the comparator, every applicable one runs whatever matched
//                  first, the default comparator is the constant-time one, and the module compares no credential with
//                  ===. A wall-clock timing test is not attempted: on a shared runner its noise is larger than the
//                  effect, and a test that passes on noise proves nothing.
//   3. no database a refused request makes no client and reads no body. The discriminating case is v7's own: an
//                  invalid run id, which v7 answered with Postgres's uuid error (HTTP 500), is now answered 401.
//   4. cap         at most 50,000 rows per table per request, a cursor that walks a table with no gap and no repeat,
//                  and everything v7 did besides (default run, meta, _export_error rows, file name) unchanged.
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
  fetchCapped, handleRunBlackbox, MAX_PAGE, NEXT_PAGE_HEADER, PAGE_SIZE, parsePage, ROW_CAP_PER_TABLE,
} from "../edge-functions/_shared/run_blackbox.ts";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const BASE = "https://x.supabase.co/functions/v1/ottoq-run-blackbox";
// Fakes in the shapes the platform uses. None is a real key.
const SERVICE = "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.c2VydmljZS1zaWduYXR1cmUtZmFrZQ";
const ANON = "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYW5vbiJ9.YW5vbi1zaWduYXR1cmUtZmFrZQ";
const PUBLISHABLE = "sb_publishable_" + "p".repeat(32);
const TOKEN = "f".repeat(64);
const RUN = "176b2912-7f91-4700-82e9-bbc42bbad0ff";
const DEPOT = "11111111-1111-1111-1111-111111111111";

const secrets = { serviceRoleKey: SERVICE, exportToken: TOKEN };
const hdrs = (h) => new Headers(h);
const decide = (h, s = secrets, cmp) => authorizeBlackbox(hdrs(h), s, cmp);
const bodyOf = async (res) => { const t = await res.text(); return t ? JSON.parse(t) : null; };

// ───────────────────────────────────────────────────────────────────────────── a fake client and world

function world(over = {}) {
  const rows = (n, tag) => Array.from({ length: n }, (_, i) => ({ id: `${tag}-${i}`, i }));
  return {
    latestRun: RUN,
    meta: { black_box_version: "1.0", sim_run_id: RUN, depot_id: DEPOT, run: { started_at: "2026-10-13T00:00:00Z" },
            executed_code: { ottoq_decide_tick: "CREATE FUNCTION ..." }, data_tables: ["ottoq_big", "ottoq_small"] },
    metaError: null,
    tables: { ottoq_big: rows(120_001, "big"), ottoq_small: rows(10, "small"),
              vehicles: rows(5, "veh"), stalls: rows(3, "stall"), ocpp_sessions: rows(2, "sess") },
    errors: {},
    ...over,
  };
}

function fakeDeps(w = world(), env = { SUPABASE_URL: "https://x.supabase.co", SUPABASE_SERVICE_ROLE_KEY: SERVICE, OTTOQ_BLACKBOX_TOKEN: TOKEN }) {
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
          calls.push(["range", table, from, to]);
          if (w.errors[table]) return { data: null, error: { message: w.errors[table] } };
          return { data: (w.tables[table] ?? []).slice(from, to + 1), error: null };
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
    },
  };
}

const get = (qs = `?run=${RUN}`, headers = { Authorization: `Bearer ${SERVICE}` }) => new Request(BASE + qs, { headers });
const post = (body, headers = { Authorization: `Bearer ${SERVICE}` }) =>
  new Request(BASE, { method: "POST", headers: { "content-type": "application/json", ...headers }, body: JSON.stringify(body) });

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
  test("the handler's default comparator is the constant-time one, and the module never compares a credential with ==", () => {
    const src = readFileSync(join(ROOT, "edge-functions/_shared/blackbox_auth.ts"), "utf8")
      .replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/[^\n]*/g, "");
    assert.match(src, /compare:\s*Compare\s*=\s*timingSafeEqualText/);
    // the comparator hashes both sides and folds every byte with no early exit
    const fn = src.slice(src.indexOf("async function timingSafeEqualText"), src.indexOf("export function bearerToken"));
    assert.match(fn, /sha256\(presented\),\s*sha256\(secret\)/);
    assert.match(fn, /diff \|= a\[i\] \^ b\[i\]/);
    const loop = fn.slice(fn.indexOf("for ("), fn.indexOf(";", fn.indexOf("diff |=")));
    assert.doesNotMatch(loop, /return|break/);
    assert.match(src, /crypto\.subtle\.digest\("SHA-256"/);
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
  test("OPTIONS answers the preflight with no credential and no client, and allows the token header", async () => {
    const f = fakeDeps();
    const res = await handleRunBlackbox(new Request(BASE, { method: "OPTIONS" }), f.deps);
    assert.equal(res.status, 200);
    assert.equal(f.made.length, 0);
    assert.match(res.headers.get("access-control-allow-headers"), new RegExp(`\\b${EXPORT_TOKEN_HEADER}\\b`));
    assert.match(res.headers.get("access-control-allow-headers"), /\bapikey\b/);
  });
  test("an invalid page is a 400 before the database, once the credential passes", async () => {
    for (const p of ["-1", "1.5", "abc", String(MAX_PAGE + 1), "99999"]) {
      const f = fakeDeps();
      const res = await handleRunBlackbox(get(`?run=${RUN}&page=${encodeURIComponent(p)}`), f.deps);
      assert.equal(res.status, 400, p);
      assert.equal(f.made.length, 0, p);
    }
  });
});

// ───────────────────────────────────────────────────────────────────────────── 4. the cap and the cursor

describe("4. at most 50,000 rows per table per request, with a cursor", () => {
  test("parsePage", () => {
    assert.equal(parsePage(null), 0);
    assert.equal(parsePage(""), 0);
    assert.equal(parsePage("3"), 3);
    assert.equal(parsePage(3), 3);
    assert.equal(parsePage(MAX_PAGE), MAX_PAGE);
    for (const bad of ["-1", "1.5", "x", 1.5, -1, MAX_PAGE + 1, {}, "1e3"]) assert.equal(parsePage(bad), null, String(bad));
  });

  test("the service key gets page 0: big table capped at 50,000, small tables whole, a cursor to page 1", async () => {
    const f = fakeDeps();
    const res = await handleRunBlackbox(get(), f.deps);
    assert.equal(res.status, 200);
    const b = await bodyOf(res);
    assert.equal(b.data.ottoq_big.length, ROW_CAP_PER_TABLE);
    assert.equal(b.data.ottoq_big[0].id, "big-0");
    assert.equal(b.data.ottoq_big.at(-1).id, "big-49999");
    assert.equal(b.data.ottoq_small.length, 10);
    assert.equal(b.data.vehicles.length, 5);
    assert.equal(b.data.stalls.length, 3);
    assert.equal(b.data.ocpp_sessions.length, 2);
    assert.deepEqual(b.export_paging.tables_with_more_rows, ["ottoq_big"]);
    assert.equal(b.export_paging.row_cap_per_table, 50_000);
    assert.equal(b.export_paging.page, 0);
    assert.equal(b.export_paging.next_page, 1);
    assert.equal(b.export_paging.next, `?run=${RUN}&page=1`);
    assert.equal(res.headers.get(NEXT_PAGE_HEADER), "1");
    // v7's own keys are all still there
    for (const k of ["black_box_version", "sim_run_id", "depot_id", "run", "executed_code", "data_tables"]) assert.ok(k in b, k);
    assert.match(res.headers.get("content-disposition"), /^attachment; filename="ottoq-blackbox-176b2912-\d{4}-\d\d-\d\d-\d\d-\d\d-\d\d\.json"$/);
    // the client was made with the service key, and every read asked for at most PAGE_SIZE rows
    assert.deepEqual(f.made, [["https://x.supabase.co", SERVICE]]);
    for (const c of f.calls.filter((c) => c[0] === "range")) assert.ok(c[3] - c[2] + 1 <= PAGE_SIZE, JSON.stringify(c));
  });

  test("walking the cursor returns every row once: no gap, no repeat, and it ends", async () => {
    const all = [];
    let page = 0;
    let pages = 0;
    while (page !== null) {
      const f = fakeDeps();
      const b = await bodyOf(await handleRunBlackbox(get(`?run=${RUN}&page=${page}`), f.deps));
      all.push(...b.data.ottoq_big);
      if (page > 0) assert.deepEqual(b.data.ottoq_small, []);
      page = b.export_paging.next_page;
      pages++;
      assert.ok(pages <= 4);
    }
    assert.equal(pages, 3);
    assert.equal(all.length, 120_001);
    assert.equal(new Set(all.map((r) => r.id)).size, 120_001);
    assert.deepEqual(all.map((r) => r.i), Array.from({ length: 120_001 }, (_, i) => i));
  });

  test("a later page: the file name says which, and the last page has no next", async () => {
    const res = await handleRunBlackbox(post({ run: RUN, page: 2 }), fakeDeps().deps);
    const b = await bodyOf(res);
    assert.equal(b.export_paging.page, 2);
    assert.equal(b.export_paging.first_row, 100_000);
    assert.equal(b.data.ottoq_big.length, 20_001);
    assert.equal(b.export_paging.next_page, null);
    assert.equal(b.export_paging.next, null);
    assert.equal(res.headers.get(NEXT_PAGE_HEADER), "none");
    assert.match(res.headers.get("content-disposition"), /-p2\.json"$/);
  });

  test("a table of exactly 50,000 rows has no next page", async () => {
    const w = world();
    w.tables.ottoq_big = w.tables.ottoq_big.slice(0, ROW_CAP_PER_TABLE);
    const b = await bodyOf(await handleRunBlackbox(get(), fakeDeps(w).deps));
    assert.equal(b.data.ottoq_big.length, ROW_CAP_PER_TABLE);
    assert.equal(b.export_paging.next_page, null);
  });

  test("the export token gets the same bundle", async () => {
    const res = await handleRunBlackbox(get(`?run=${RUN}`, { [EXPORT_TOKEN_HEADER]: TOKEN }), fakeDeps().deps);
    assert.equal(res.status, 200);
    assert.equal((await bodyOf(res)).data.ottoq_big.length, ROW_CAP_PER_TABLE);
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
    assert.ok(!b.export_paging.tables_with_more_rows.includes("ottoq_small"));

    // vehicles keep v7's filter: the run's own cars or the depot's
    f = fakeDeps();
    await handleRunBlackbox(get(), f.deps);
    assert.ok(f.calls.some((c) => c[0] === "or" && c[1] === "vehicles" && c[2] === `owning_sim_run_id.eq.${RUN},current_depot_id.eq.${DEPOT}`));
  });

  test("fetchCapped: a failed probe past the cap says there may be more rather than dropping rows", async () => {
    let n = 0;
    const q = () => ({ range: async (from, to) => (++n > 1 ? { data: null, error: { message: "boom" } } : { data: [{ from }, { to }].slice(0, to - from + 1), error: null }) });
    const r = await fetchCapped(q, 0, 2);
    assert.equal(r.rows.length, 2);
    assert.equal(r.more, true);
  });
});
