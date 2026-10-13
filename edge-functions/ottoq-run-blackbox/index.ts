// ottoq-run-blackbox v2 — downloadable FLIGHT RECORDER. Assembles the bundle in MANY fast
// queries (not one giant 25MB RPC that trips the API gateway's ~22s ceiling): a light
// metadata+code header RPC, then each run-scoped data table paginated separately, then
// streamed as a .json attachment. Chase drops it into Claude Code for a code-vs-behavior audit.
//
// THIS FILE IS THE I/O SHELL ONLY (2026-10-13, db/checks/0446). Who may call it lives in ../_shared/blackbox_auth.ts
// and the handler in ../_shared/run_blackbox.ts, which tests/run_blackbox_auth.test.mjs imports directly. Since this
// change a request needs the service-role key (Authorization: Bearer or apikey) or the operator export token
// (x-ottoq-export-token, the edge secret OTTOQ_BLACKBOX_TOKEN); anything else is answered 401 before the database is
// touched. One response carries at most 20 MB of JSON; a larger run comes as several, and `export_paging.next_cursor`
// (also the X-OTTOQ-Next-Cursor header) names the next one.
//
// DEPLOY (a person does this; db/checks/0446 §6 has the probes that follow it):
//   1. Set the token: supabase secrets set OTTOQ_BLACKBOX_TOKEN=$(openssl rand -hex 32) --project-ref gxdrcyphqjzjsuhxuqtg
//      (or the dashboard's Edge Function Secrets page).
//   2. Deploy THREE files through the Supabase MCP deploy_edge_function, as edge-functions/_MANIFEST.md footnote 11
//      did for ottoq-depot-v2: entrypoint ottoq-run-blackbox/index.ts, plus _shared/blackbox_auth.ts and
//      _shared/run_blackbox.ts, with verify_jwt FALSE. This repo has no supabase/ directory or config.toml, so
//      `supabase functions deploy` does not work from it as it stands.
//   3. Read it back with get_edge_function and hash all three files against the repo.
// verify_jwt must stay false. The function checks the credential itself; gateway verification would refuse the
// export token (not a JWT) and the legacy JWT keys (UNAUTHORIZED_LEGACY_JWT). Environment: SUPABASE_URL and
// SUPABASE_SERVICE_ROLE_KEY (platform) and OTTOQ_BLACKBOX_TOKEN (optional; unset or shorter than 32 characters means
// only the service-role key opens it).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { handleRunBlackbox } from "../_shared/run_blackbox.ts";

Deno.serve((req) =>
  handleRunBlackbox(req, {
    env: (name) => Deno.env.get(name),
    createClient: (url, key) => createClient(url, key),
    log: (line) => console.log(line),
  })
);
