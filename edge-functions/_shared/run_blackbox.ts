// ottoq-run-blackbox's request handler, importable by Deno (ottoq-run-blackbox/index.ts, the I/O shell) and by Node
// (tests/run_blackbox_auth.test.mjs, over a fake client). db/checks/0446 is the measurement behind it.
//
// What it does is what v7 did, with two changes and nothing else:
//   1. A CREDENTIAL FIRST. Before the URL, the body or the database are touched, the request must carry the
//      service-role key or the operator export token (./blackbox_auth.ts). Otherwise 401, and no client is made.
//   2. AT MOST ROW_CAP_PER_TABLE ROWS PER TABLE PER REQUEST, with a cursor. v7 paged each table up to 500,000 rows in
//      one response; run 816bd28c (twin depot, 2026-10-01) holds 327,222 shield evaluations, measured 2026-10-13, and
//      the same again in the view over them. A request now returns rows
//      [page * 50,000, page * 50,000 + 50,000) of every table, and `export_paging` names the tables that have more and
//      the next page to ask for (`?run=<id>&page=<n>`, or {"run": ..., "page": n} in a POST body). Page 0 is what a
//      caller that never sends `page` gets, so a run under the cap downloads exactly as before.
//
// THE CURSOR IS AN OFFSET, AND ITS ORDER IS THE ONE v7 ALREADY RELIED ON. Every table is read with `sim_run_id = run`
// and no ORDER BY, exactly as v7 read its 1,000-row pages: the 90 relations ottoq_run_blackbox_meta lists have no
// common key to order by (70 tables carry 53 different primary-key column lists, one table has none, and 19 are views;
// measured 2026-10-13). On a stopped run, whose rows no longer change, successive reads return them in the same order;
// on a run still being written, a later page can repeat or miss rows. So page a run that has stopped (export_paging
// says so). A keyset cursor needs each table's key, which ottoq_run_blackbox_meta does not return: that is a
// migration, and a separate change.
//
// Everything else behaves as v7: the default run (the latest operator_demo run), the meta RPC, the table list, the
// depot-keyed vehicles, stalls and ocpp_sessions, the `_export_error` rows, the 404 and 500 answers and page 0's file
// name. The only additions: the bundle's `export_paging` key, an X-OTTOQ-Next-Page header, a later page's file name
// ending "-p<n>", x-ottoq-export-token in the CORS allow list, a 400 for a page that is not a whole number 0..1000,
// and a POST body that is not an object read as {} instead of throwing.
import { authorizeBlackbox, EXPORT_TOKEN_HEADER, unauthorizedResponse } from "./blackbox_auth.ts";
import type { Compare } from "./blackbox_auth.ts";

export const ROW_CAP_PER_TABLE = 50_000;
export const PAGE_SIZE = 1000;          // PostgREST's own row limit per read; v7 used the same
export const MAX_PAGE = 1000;           // 50 million rows of one table; far past any run measured
export const NEXT_PAGE_HEADER = "X-OTTOQ-Next-Page";

export const cors: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": `authorization, x-client-info, apikey, content-type, ${EXPORT_TOKEN_HEADER}`,
};

// deno-lint-ignore no-explicit-any
export type Client = any;
// deno-lint-ignore no-explicit-any
type Query = any;
export type BlackboxDeps = {
  env: (name: string) => string | undefined;
  createClient: (url: string, key: string) => Client;
  /** The comparison authorizeBlackbox uses; tests pass a spy. Defaults to the constant-time one. */
  compare?: Compare;
  log?: (line: string) => void;
};
export type CappedRead = { rows: unknown[]; more: boolean };

const json = (body: unknown, status: number, extra: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json", ...extra } });

/** A page number from the query string or body: absent means 0; anything but a whole number 0..MAX_PAGE is null. */
export function parsePage(raw: unknown): number | null {
  if (raw === null || raw === undefined || raw === "") return 0;
  const s = typeof raw === "number" ? String(raw) : typeof raw === "string" ? raw.trim() : "";
  if (!/^\d{1,4}$/.test(s)) return null;
  const n = Number(s);
  return n <= MAX_PAGE ? n : null;
}

/** Rows [start, start + cap) of one query, read PAGE_SIZE at a time as v7 read them, then one row past the cap to
 *  learn whether more exist. A read error ends the table with v7's `_export_error` row. If the probe past the cap
 *  itself fails, `more` is true: asking for an empty next page costs a request, missing rows costs the audit. */
export async function fetchCapped(makeQuery: () => Query, start: number, cap: number): Promise<CappedRead> {
  const out: unknown[] = [];
  const end = start + cap; // exclusive
  let off = start;
  while (off < end) {
    const to = Math.min(off + PAGE_SIZE, end) - 1;
    const { data, error } = await makeQuery().range(off, to);
    if (error) { out.push({ _export_error: error.message }); return { rows: out, more: false }; }
    if (!data || data.length === 0) return { rows: out, more: false };
    out.push(...data);
    if (data.length < to - off + 1) return { rows: out, more: false };
    off = to + 1;
  }
  const probe = await makeQuery().range(end, end);
  return { rows: out, more: probe.error ? true : Array.isArray(probe.data) && probe.data.length > 0 };
}

export async function handleRunBlackbox(req: Request, deps: BlackboxDeps): Promise<Response> {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });

  // 1) the credential, before anything else is read or touched
  const decision = await authorizeBlackbox(
    req.headers,
    { serviceRoleKey: deps.env("SUPABASE_SERVICE_ROLE_KEY"), exportToken: deps.env("OTTOQ_BLACKBOX_TOKEN") },
    deps.compare,
  );
  if (!decision.ok) {
    deps.log?.(JSON.stringify({ fn: "ottoq-run-blackbox", auth: "refused", reason: decision.reason }));
    return unauthorizedResponse(cors);
  }

  try {
    const url = new URL(req.url);
    let run: string | null = url.searchParams.get("run");
    let pageRaw: unknown = url.searchParams.get("page");
    if (req.method === "POST" && (!run || pageRaw === null)) {
      const b = await req.json().catch(() => ({}));
      const o = b && typeof b === "object" ? b as Record<string, unknown> : {};
      if (!run) run = (o.run ?? o.sim_run_id ?? null) as string | null;
      if (pageRaw === null) pageRaw = o.page ?? null;
    }
    const page = parsePage(pageRaw);
    if (page === null) return json({ error: `page must be a whole number from 0 to ${MAX_PAGE}` }, 400);
    deps.log?.(JSON.stringify({ fn: "ottoq-run-blackbox", auth: "accepted", via: decision.via, page }));

    const sb = deps.createClient(deps.env("SUPABASE_URL")!, deps.env("SUPABASE_SERVICE_ROLE_KEY")!);

    if (!run) {
      const { data: latest } = await sb.from("ottoq_sim_runs").select("sim_run_id")
        .eq("run_by", "operator_demo").order("started_at", { ascending: false }).limit(1).maybeSingle();
      run = latest?.sim_run_id ?? null;
      if (!run) return json({ error: "no run found" }, 404);
    }

    // 2) fast header: run metadata + exact executed code + the list of data tables
    const { data: meta, error: mErr } = await sb.rpc("ottoq_run_blackbox_meta", { p_sim_run_id: run });
    if (mErr || !meta) return json({ error: mErr?.message ?? "meta failed" }, 500);
    const depot = meta.depot_id;
    const tables: string[] = Array.isArray(meta.data_tables) ? meta.data_tables : [];

    const start = page * ROW_CAP_PER_TABLE;
    const more: string[] = [];
    const grab = async (name: string, makeQuery: () => Query) => {
      const r = await fetchCapped(makeQuery, start, ROW_CAP_PER_TABLE);
      if (r.more) more.push(name);
      return r.rows;
    };

    // 3) each run-scoped data table, at most ROW_CAP_PER_TABLE rows from `start`
    const data: Record<string, unknown> = {};
    for (const t of tables) data[t] = await grab(t, () => sb.from(t).select("*").eq("sim_run_id", run));

    // 4) depot-keyed state tables
    data["vehicles"] = await grab("vehicles", () => sb.from("vehicles").select("*").or(`owning_sim_run_id.eq.${run},current_depot_id.eq.${depot}`));
    data["stalls"] = await grab("stalls", () => sb.from("stalls").select("*").eq("depot_id", depot));
    data["ocpp_sessions"] = await grab("ocpp_sessions", () => sb.from("ocpp_sessions").select("*").eq("depot_id", depot).gte("started_at", meta.run?.started_at ?? "1970-01-01"));

    const nextPage = more.length > 0 ? page + 1 : null;
    const export_paging = {
      row_cap_per_table: ROW_CAP_PER_TABLE,
      page,
      first_row: start,
      tables_with_more_rows: [...more].sort(),
      next_page: nextPage,
      next: nextPage === null ? null : `?run=${encodeURIComponent(String(run))}&page=${nextPage}`,
      order: "offset paging in the order the database returns each table for this run; page only a run that has stopped",
    };

    const bundle = { ...meta, data, export_paging };
    const stamp = new Date().toISOString().slice(0, 19).replace(/[:T]/g, "-");
    const fname = `ottoq-blackbox-${String(run).slice(0, 8)}-${stamp}${page > 0 ? `-p${page}` : ""}.json`;
    return new Response(JSON.stringify(bundle), {
      status: 200,
      headers: {
        ...cors,
        "Content-Type": "application/json",
        "Content-Disposition": `attachment; filename="${fname}"`,
        [NEXT_PAGE_HEADER]: nextPage === null ? "none" : String(nextPage),
      },
    });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : "unknown" }, 500);
  }
}
