// Who may download a run's Black Box (ottoq-run-blackbox), importable by Deno (../_shared/run_blackbox.ts) and by Node
// (tests/run_blackbox_auth.test.mjs). db/checks/0446 is the measurement that asked for it.
//
// THE DOOR WAS OPEN. ottoq-run-blackbox v7 is deployed with verify_jwt off and checked no credential, and it reads with
// the service role: anyone with the URL got every run-scoped table of any run (paged to 500,000 rows each), the
// depot's vehicles, stalls and charge sessions, and the source of 49 engine functions. Of the 74 tables it reads, the
// public key may read 4 directly since 0658; this function served all 74 to everyone. An unauthenticated probe on
// 2026-10-13 at 1:07 PM CT reached Postgres (a uuid parse error, HTTP 500), not a 401.
//
// TWO CREDENTIALS, AND NOTHING ELSE:
//   - the service-role key, as `Authorization: Bearer <key>` or `apikey: <key>`, against SUPABASE_SERVICE_ROLE_KEY
//     (the platform injects it; it is the key the function already reads with);
//   - an operator export token, as `x-ottoq-export-token: <token>`, against the edge secret OTTOQ_BLACKBOX_TOKEN. A
//     token shorter than MIN_EXPORT_TOKEN_LENGTH characters is treated as not set, so a weak secret cannot open the
//     door; set one with `openssl rand -hex 32` (64 characters).
// The public key (legacy anon JWT or sb_publishable_) matches neither, so it gets a 401. The two channels do not
// cross: the service key in the token header, or the token as a Bearer, is refused.
//
// EVERY COMPARISON IS CONSTANT-TIME AND EVERY ONE RUNS. Both sides are hashed with SHA-256 and the two 32-byte digests
// are compared with an XOR accumulator that has no early exit, so neither a secret's content nor its length shows in
// the time a refusal takes. authorizeBlackbox runs every applicable comparison before it reads any result
// (Promise.all), so the time does not say which credential matched either.
//
// Deploy note: the function must stay deployed WITHOUT gateway JWT verification (--no-verify-jwt). The export token is
// not a JWT, and the functions gateway refuses the legacy JWT keys (UNAUTHORIZED_LEGACY_JWT, measured 2026-10-09 on
// ottoq-ingest), so turning verification on would lock out both credentials. This file is the check instead.

export const EXPORT_TOKEN_HEADER = "x-ottoq-export-token";
export const MIN_EXPORT_TOKEN_LENGTH = 32;
export const REALM = "ottoq-run-blackbox";
export const WWW_AUTHENTICATE = `Bearer realm="${REALM}"`;
export const UNAUTHORIZED_DETAIL =
  "Send the operator export token in x-ottoq-export-token, or the service-role key as a Bearer or apikey.";

export type HeaderGetter = { get(name: string): string | null };
export type Compare = (presented: string, secret: string) => Promise<boolean>;
export type BlackboxSecrets = { serviceRoleKey?: string | null; exportToken?: string | null };
export type BlackboxVia = "service_role" | "export_token";
export type BlackboxAuthDecision = {
  ok: boolean;
  via: BlackboxVia | null;
  /** 'accepted', 'no_credential' (nothing usable was presented) or 'not_accepted' (something was, and nothing matched). */
  reason: "accepted" | "no_credential" | "not_accepted";
  /** How many constant-time comparisons ran: every applicable one, whatever matched first. */
  compared: number;
  export_token_configured: boolean;
};

const enc = new TextEncoder();

async function sha256(text: string): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", enc.encode(text)));
}

/** Constant-time equality of a presented credential and a secret: SHA-256 both (fixed 32 bytes, so the secret's length
 *  is hidden too), then fold every byte's XOR into one accumulator with no early exit. An empty secret never matches. */
export async function timingSafeEqualText(presented: string, secret: string): Promise<boolean> {
  const [a, b] = await Promise.all([sha256(presented), sha256(secret)]);
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return (diff | (secret.length === 0 ? 1 : 0)) === 0;
}

export function bearerToken(authorization: string | null | undefined): string | null {
  const m = /^Bearer[ ]+(\S+)[ ]*$/i.exec(authorization ?? "");
  return m ? m[1] : null;
}

function presented(value: string | null | undefined): string | null {
  const v = (value ?? "").trim();
  return v === "" ? null : v;
}

function usableSecret(value: string | null | undefined, minLength: number): string | null {
  const v = (value ?? "").trim();
  return v.length >= Math.max(1, minLength) ? v : null;
}

/** Decide one request. Reads only the three headers; touches no database and no network. */
export async function authorizeBlackbox(
  headers: HeaderGetter,
  secrets: BlackboxSecrets,
  compare: Compare = timingSafeEqualText,
): Promise<BlackboxAuthDecision> {
  const bearer = presented(bearerToken(headers.get("authorization")));
  const apikey = presented(headers.get("apikey"));
  const token = presented(headers.get(EXPORT_TOKEN_HEADER));
  const serviceKey = usableSecret(secrets.serviceRoleKey, 1);
  const exportToken = usableSecret(secrets.exportToken, MIN_EXPORT_TOKEN_LENGTH);

  const checks: Array<{ via: BlackboxVia; presented: string; secret: string }> = [];
  if (serviceKey && bearer) checks.push({ via: "service_role", presented: bearer, secret: serviceKey });
  if (serviceKey && apikey) checks.push({ via: "service_role", presented: apikey, secret: serviceKey });
  if (exportToken && token) checks.push({ via: "export_token", presented: token, secret: exportToken });

  // Every comparison runs before any result is read.
  const results = await Promise.all(checks.map((c) => compare(c.presented, c.secret)));
  const hit = checks.find((_, i) => results[i] === true);
  const anyPresented = bearer !== null || apikey !== null || token !== null;
  return {
    ok: hit !== undefined,
    via: hit ? hit.via : null,
    reason: hit ? "accepted" : anyPresented ? "not_accepted" : "no_credential",
    compared: checks.length,
    export_token_configured: exportToken !== null,
  };
}

/** The refusal: 401, the CORS headers the caller passes (so a browser can read why), and no hint of which secret is
 *  set or how close a guess came. */
export function unauthorizedResponse(corsHeaders: Record<string, string>): Response {
  return new Response(JSON.stringify({ error: "unauthorized", detail: UNAUTHORIZED_DETAIL }), {
    status: 401,
    headers: { ...corsHeaders, "Content-Type": "application/json", "WWW-Authenticate": WWW_AUTHENTICATE },
  });
}
