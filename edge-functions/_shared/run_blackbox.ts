// ottoq-run-blackbox's request handler, importable by Deno (ottoq-run-blackbox/index.ts, the I/O shell) and by Node
// (tests/run_blackbox_auth.test.mjs, over a fake client). db/checks/0446 is the measurement behind it.
//
// What it does is what v7 did, with two changes and nothing else:
//   1. A CREDENTIAL FIRST. Before the URL, the body or the database are touched, the request must carry the
//      service-role key or the operator export token (./blackbox_auth.ts). Otherwise 401, and no client is made.
//   2. ONE RESPONSE CARRIES AT MOST RESPONSE_BYTE_BUDGET BYTES (20 MB) OF JSON, and a cursor names where the next one
//      starts. The limit is on the response, not on each table, because the platform's limits are per request:
//      256 MB of memory and 2 s of CPU (https://supabase.com/docs/guides/functions/limits, read 2026-10-13). v7 put a
//      whole run in one response, and measured 2026-10-13 a twin-depot run is far past that: 816bd28c is about
//      1,295 MB of JSON (327,222 shield evaluations at 1,132 bytes, 1,282 decision snapshots at 178,627 bytes each,
//      71,429 decisions at 2,903 bytes, ...), and 176b2912 about 448 MB. A first draft of this change capped each
//      table at 50,000 rows, which still put about 448 MB in 816bd28c's first response; a review measured that.
//
// HOW A RESPONSE IS FILLED. The relations are v7's, in v7's order: ottoq_run_blackbox_meta's data_tables (sorted by
// name), then vehicles, stalls and ocpp_sessions. Each row is serialised once, as it is read, and counted in UTF-8
// bytes; the response is those bytes joined, so what is counted is exactly what is sent. When the next row would take
// the body past the budget (less RESPONSE_RESERVE_BYTES for export_paging and punctuation), the response ends and its
// cursor names that row: `v1.<page>.<offset>.<relation>.<run>`. Every response carries at least one row, so a walk
// always ends. Reads are sized too, because one 1,000-row read of the decision snapshots is about 178 MB before any
// budget is consulted: a relation's first read in a request asks for FIRST_READ_ROWS rows, and each later read for as
// many as fit READ_BYTE_TARGET at the widest row seen so far in it (and no more than the budget has room for), never
// more than PAGE_SIZE.
//
// A RUN UNDER THE BUDGET DOWNLOADS EXACTLY AS BEFORE: one response, every relation a key of `data`, v7's file name,
// plus `export_paging` with complete: true. A larger run comes as several responses. Each repeats the header (run
// row, executed_code, data_tables) so every file stands alone, and `data` holds only the relations, or the part of
// one, that this response carries; concatenating data[<relation>] across pages in page order gives the whole run.
//
// THE CURSOR IS AN OFFSET, IN THE ORDER v7 ALREADY RELIED ON. Each relation is read with `sim_run_id = run` (or v7's
// depot filters) and no ORDER BY, exactly as v7 read its 1,000-row pages: the 90 relations share no key to order by
// (70 tables carry 53 different primary-key column lists, one table has none, 19 are views; measured 2026-10-13).
// On a run that has ended the order is usually stable between requests, but Postgres does not promise it: a plan
// can change as the offset grows, and a synchronized sequential scan can start mid-table. On a run still writing, a
// later page can repeat or miss rows. export_paging says which the run is. A keyset cursor needs each relation's key
// from ottoq_run_blackbox_meta, which is a migration and a separate change.
//
// Everything else behaves as v7: the default run (the latest operator_demo run), the meta RPC, the relation list,
// the depot-keyed vehicles, stalls and ocpp_sessions, the `_export_error` rows, the 404 and 500 answers and the first
// response's file name. The additions: the bundle's `export_paging` key, an X-OTTOQ-Next-Cursor header (exposed to
// browsers with Content-Disposition), a later response's file name ending "-p<n>", x-ottoq-export-token in the CORS
// allow list, a 400 for a cursor this function did not issue or one naming another run, a 409 for a cursor naming a
// relation the export no longer lists, and a POST body that is not an object read as {} instead of throwing.
import { authorizeBlackbox, EXPORT_TOKEN_HEADER, unauthorizedResponse } from "./blackbox_auth.ts";
import type { Compare } from "./blackbox_auth.ts";

/** The most one response's body carries, in bytes of UTF-8 JSON, header included. */
export const RESPONSE_BYTE_BUDGET = 20_000_000;
/** Kept back from the budget for export_paging and the bundle's punctuation (export_paging measured under 12 KB). */
export const RESPONSE_RESERVE_BYTES = 64_000;
/** The most rows one read asks for: PostgREST's own limit, and what v7 asked for. */
export const PAGE_SIZE = 1000;
/** A relation's first read in a request: small, because its row width is not yet known. */
export const FIRST_READ_ROWS = 25;
/** Later reads carry about this many bytes, sized by the widest row seen so far in the relation. */
export const READ_BYTE_TARGET = 4_000_000;
export const NEXT_CURSOR_HEADER = "X-OTTOQ-Next-Cursor";

export const cors: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": `authorization, x-client-info, apikey, content-type, ${EXPORT_TOKEN_HEADER}`,
  "Access-Control-Expose-Headers": `Content-Disposition, ${NEXT_CURSOR_HEADER}`,
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
  /** Tests only: a smaller budget, so a walk of many pages stays quick. Production uses RESPONSE_BYTE_BUDGET. */
  responseByteBudget?: number;
  log?: (line: string) => void;
};
export type Cursor = { page: number; offset: number; relation: string; run: string };
export type PagedRelation = { name: string; first_row: number; rows: number; complete: boolean; error?: string };

const enc = new TextEncoder();
const COMMA = enc.encode(",");

const json = (body: unknown, status: number, extra: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json", ...extra } });

// The relation part is a Postgres identifier's alphabet (letters, digits, _ and $; no dot, so the parse is unambiguous).
// db/checks/0446 query (3) asserts every relation the export lists fits it.
const CURSOR_RE =
  /^v1\.(\d{1,6})\.(\d{1,10})\.([a-z_][a-z0-9_$]{0,62})\.([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/i;

export function formatCursor(c: Cursor): string {
  return `v1.${c.page}.${c.offset}.${c.relation}.${c.run}`;
}

/** undefined: no cursor was sent (the first response). null: something was sent and it is not a cursor. */
export function parseCursor(raw: unknown): Cursor | null | undefined {
  if (raw === null || raw === undefined || raw === "") return undefined;
  if (typeof raw !== "string") return null;
  const m = CURSOR_RE.exec(raw.trim());
  if (!m) return null;
  const page = Number(m[1]);
  if (page < 1) return null; // the first response has no cursor
  return { page, offset: Number(m[2]), relation: m[3], run: m[4] };
}

// No return annotation: inferred, it is Uint8Array<ArrayBuffer> where the compiler knows that form (a Response body
// needs it) and plain Uint8Array where it does not.
function concat(parts: Uint8Array[], total: number) {
  const out = new Uint8Array(total);
  let at = 0;
  for (const p of parts) { out.set(p, at); at += p.byteLength; }
  return out;
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
    let cursorRaw: unknown = url.searchParams.get("cursor");
    if (req.method === "POST" && (!run || cursorRaw === null)) {
      const b = await req.json().catch(() => ({}));
      const o = b && typeof b === "object" ? b as Record<string, unknown> : {};
      if (!run) run = (o.run ?? o.sim_run_id ?? null) as string | null;
      if (cursorRaw === null) cursorRaw = o.cursor ?? null;
    }
    const cursor = parseCursor(cursorRaw);
    if (cursor === null) return json({ error: "cursor is not one this function issued; send export_paging.next_cursor as it came" }, 400);
    if (cursor) {
      if (run && run.toLowerCase() !== cursor.run.toLowerCase()) {
        return json({ error: "cursor belongs to another run; send it with that run, or with no run" }, 400);
      }
      run = cursor.run; // a later page never falls back to "the latest run", which can change between pages
    }
    deps.log?.(JSON.stringify({ fn: "ottoq-run-blackbox", auth: "accepted", via: decision.via, page: cursor?.page ?? 0 }));

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

    // 3) the relations, in v7's order: each run-scoped data table, then the depot-keyed state tables
    const relations: Array<{ name: string; query: () => Query }> = [
      ...tables.map((t) => ({ name: t, query: () => sb.from(t).select("*").eq("sim_run_id", run) })),
      { name: "vehicles", query: () => sb.from("vehicles").select("*").or(`owning_sim_run_id.eq.${run},current_depot_id.eq.${depot}`) },
      { name: "stalls", query: () => sb.from("stalls").select("*").eq("depot_id", depot) },
      { name: "ocpp_sessions", query: () => sb.from("ocpp_sessions").select("*").eq("depot_id", depot).gte("started_at", meta.run?.started_at ?? "1970-01-01") },
    ];
    let startAt = 0;
    let startOffset = 0;
    const page = cursor ? cursor.page : 0;
    if (cursor) {
      startAt = relations.findIndex((r) => r.name === cursor.relation);
      if (startAt < 0) return json({ error: `cursor names ${cursor.relation}, which this run's export no longer lists` }, 409);
      startOffset = cursor.offset;
    }

    // 4) the body, built as UTF-8 bytes and counted as it is built
    const budget = deps.responseByteBudget ?? RESPONSE_BYTE_BUDGET;
    const rowRoom = budget - RESPONSE_RESERVE_BYTES;
    const parts: Uint8Array[] = [];
    let used = 0;
    const put = (bytes: Uint8Array) => { parts.push(bytes); used += bytes.byteLength; };
    const head = { ...meta } as Record<string, unknown>;
    delete head.data;
    delete head.export_paging;
    const headJson = JSON.stringify(head);
    put(enc.encode(headJson.slice(0, -1) + (headJson === "{}" ? "" : ",") + '"data":{'));

    const onPage: PagedRelation[] = [];
    let rowsOnPage = 0;
    let next: { relation: string; offset: number } | null = null;
    fill: for (let i = startAt; i < relations.length; i++) {
      const rel = relations[i];
      const entry: PagedRelation = { name: rel.name, first_row: i === startAt ? startOffset : 0, rows: 0, complete: false };
      put(enc.encode(`${onPage.length > 0 ? "," : ""}${JSON.stringify(rel.name)}:[`));
      onPage.push(entry);
      let off = entry.first_row;
      let widest = 0;
      let want = FIRST_READ_ROWS;
      for (;;) {
        const { data, error } = await rel.query().range(off, off + want - 1);
        if (error) {
          // v7's answer to a failed read: an _export_error row, and the relation ends there
          if (entry.rows > 0) put(COMMA);
          put(enc.encode(JSON.stringify({ _export_error: error.message })));
          entry.rows++;
          entry.error = String(error.message).slice(0, 300);
          entry.complete = true;
          break;
        }
        if (!data || data.length === 0) { entry.complete = true; break; }
        for (let k = 0; k < data.length; k++) {
          const row = enc.encode(JSON.stringify(data[k]));
          if (rowsOnPage > 0 && used + row.byteLength + 1 > rowRoom) {
            next = { relation: rel.name, offset: off + k };
            put(enc.encode("]"));
            break fill;
          }
          if (entry.rows > 0) put(COMMA);
          put(row);
          entry.rows++;
          rowsOnPage++;
          if (row.byteLength > widest) widest = row.byteLength;
        }
        if (data.length < want) { entry.complete = true; break; }
        off += data.length;
        const w = Math.max(1, widest);
        want = Math.max(1, Math.min(PAGE_SIZE, Math.floor(READ_BYTE_TARGET / w), Math.floor(Math.max(0, rowRoom - used) / w) + 1));
      }
      put(enc.encode("]"));
    }

    const nextCursor = next ? formatCursor({ page: page + 1, offset: next.offset, relation: next.relation, run: String(run) }) : null;
    const runRow = (meta.run ?? null) as Record<string, unknown> | null;
    const ended = runRow !== null && runRow.ended_at !== null && runRow.ended_at !== undefined;
    const export_paging = {
      response_byte_budget: budget,
      page,
      cursor: cursor ? formatCursor(cursor) : null,
      next_cursor: nextCursor,
      next: nextCursor === null ? null : `?run=${encodeURIComponent(String(run))}&cursor=${nextCursor}`,
      complete: nextCursor === null,
      relations: onPage,
      run_status: runRow?.status ?? null,
      run_ended_at: runRow?.ended_at ?? null,
      warning: ended ? null : "this run has not ended: rows are still being written, so a later page can repeat or miss rows",
      order: "offset paging over each relation in the order the database returns it (no ORDER BY, as v7); usually stable on a run that has ended, not guaranteed",
      merge: "concatenate data[<relation>] across pages in page order; every page repeats the header keys",
    };
    put(enc.encode(`},"export_paging":${JSON.stringify(export_paging)}}`));

    const body = concat(parts, used);
    deps.log?.(JSON.stringify({ fn: "ottoq-run-blackbox", page, bytes: used, rows: rowsOnPage, relations: onPage.length, complete: nextCursor === null }));
    const stamp = new Date().toISOString().slice(0, 19).replace(/[:T]/g, "-");
    const fname = `ottoq-blackbox-${String(run).slice(0, 8)}-${stamp}${page > 0 ? `-p${page}` : ""}.json`;
    return new Response(body, {
      status: 200,
      headers: {
        ...cors,
        "Content-Type": "application/json",
        "Content-Disposition": `attachment; filename="${fname}"`,
        [NEXT_CURSOR_HEADER]: nextCursor ?? "none",
      },
    });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : "unknown" }, 500);
  }
}
