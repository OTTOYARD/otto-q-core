// ottoq-depot-v2: the v2 operator door (contract/README.md), beside ottoq-ingest, which stays until nothing uses it.
//
//   POST /events      an operator's CloudEvents (application/cloudevents+json, or a batch of up to 500 in
//                     application/cloudevents-batch+json, at most 1 MiB), each checked against contract/schemas here,
//                     then taken by public.ottoq_v2_take_events: scoped to the key's fleets and depot, once, in order.
//                     ?dry_run=true does everything and keeps nothing.
//   GET  /directives  the key's own directives after ?after= (the cursor a previous read returned in the
//                     OTTOQ-Next-After header), at most ?limit= (1-500), each signed. ?peek=true leaves them unmarked.
//   GET  /jwks        the public keys the signatures verify under.
//
// THIS FILE IS THE I/O SHELL ONLY. Routing, the credential's form, the size and type rules and the signature live in
// ../_shared/depot_v2.ts, which tests/depot_v2.test.mjs imports directly. Who a key speaks for, once-only, order and
// what each event does live in the database (db/migrations/0650-0652), so nothing here can widen what a key may do.
//
// The schema check runs @cfworker/json-schema 4.1.1 (MIT; drafts 4, 7, 2019-09 and 2020-12, no eval: npm registry,
// https://www.npmjs.com/package/@cfworker/json-schema, read 2026-10-10). On the contract's 28 examples it agrees with
// contract/ottoq_contract.py on every verdict (10 accepted, 18 refused; run 2026-10-10 against the committed files).
//
// DEPLOY WITH JWT VERIFICATION OFF. The source key is the authentication, and the functions gateway refuses the legacy
// JWT keys every app still ships (UNAUTHORIZED_LEGACY_JWT, measured 2026-10-09 on ottoq-ingest):
//   supabase functions deploy ottoq-depot-v2 --project-ref gxdrcyphqjzjsuhxuqtg --no-verify-jwt
// Environment: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY, injected by the platform. The depot's Ed25519 key is made
// here on first use and its private half is kept in Supabase Vault (0651); no key is ever configured by hand.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { Validator } from "npm:@cfworker/json-schema@4.1.1";
import { depotSigner, handleDepotV2Request, postgrestV2Engine } from "../_shared/depot_v2.ts";
import { CONTRACT_SCHEMAS } from "./contract_schemas.ts";

const SUPABASE_URL = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/+$/, "");
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

// deno-lint-ignore no-explicit-any
const validator = new Validator(CONTRACT_SCHEMAS["envelope.json"] as any, "2020-12", false);
for (const [name, schema] of Object.entries(CONTRACT_SCHEMAS)) {
  // deno-lint-ignore no-explicit-any
  if (name !== "envelope.json") validator.addSchema(schema as any);
}
const validate = (event: unknown): string[] => {
  const r = validator.validate(event);
  return r.valid ? [] : r.errors.map((e) => `${e.instanceLocation || "#"}: ${e.error} [${e.keyword}]`);
};

const engine = SUPABASE_URL && SERVICE_KEY ? postgrestV2Engine({ supabaseUrl: SUPABASE_URL, serviceKey: SERVICE_KEY }) : null;
const signer = engine ? depotSigner(engine) : null;

Deno.serve((req: Request) => {
  if (!engine || !signer) {
    return new Response(JSON.stringify({ ok: false, error: { code: "not_configured", message: "The door has no engine." } }),
      { status: 500, headers: { "Content-Type": "application/json" } });
  }
  return handleDepotV2Request(req, { engine, validate, signer });
});
