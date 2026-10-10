// ottoq-csms-relay: the door through which OTTO-Q's charger back end (csms/, on AWS) reads the twin's charger frames
// and reports what it did with them. Step 5 of the twin data contract review, the live bridge (csms/README.md).
//
//   GET  /frames  the twin depot's station frames after ?after= (a previous read's next_after, or -1 for the head), at
//                 most ?limit= (1-1000); ?chargers=true adds what each charger says in its BootNotification.
//   POST /report  what the back end did with a batch (application/json, at most 256 KiB): frames by outcome and action.
//
// THIS FILE IS THE I/O SHELL ONLY. The routes, the credential's form and the size rules live in
// ../_shared/csms_relay.ts, which tests/csms_relay.test.mjs imports directly. Which depot and data source a key reads,
// and whether it may read at all, are decided in the database (db/migrations/0697) from the key alone.
//
// DEPLOY WITH JWT VERIFICATION OFF, as ottoq-depot-v2: the source key is the authentication.
//   supabase functions deploy ottoq-csms-relay --project-ref gxdrcyphqjzjsuhxuqtg --no-verify-jwt
// Environment: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY, injected by the platform. Deploy only after 0697 is applied.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { handleCsmsRelayRequest, postgrestRelayEngine } from "../_shared/csms_relay.ts";

const SUPABASE_URL = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/+$/, "");
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const engine = SUPABASE_URL && SERVICE_KEY ? postgrestRelayEngine({ supabaseUrl: SUPABASE_URL, serviceKey: SERVICE_KEY }) : null;

Deno.serve((req: Request) => {
  if (!engine) {
    return new Response(JSON.stringify({ ok: false, error: { code: "not_configured", message: "The relay has no engine." } }),
      { status: 500, headers: { "Content-Type": "application/json" } });
  }
  return handleCsmsRelayRequest(req, engine);
});
