/**
 * OTTOYARD sign-in for an owner's own agent (db/migrations/0660, PERSONAL_AGENT.md section 10): the gateway's OAuth 2.1
 * endpoints and the signed-in MCP address. Pure functions and one web-standard handler, so `node --test` imports this
 * file directly, as it imports agent_gateway.ts.
 *
 * HOW AN AGENT SIGNS IN
 *   1. It reaches the signed-in MCP address ({gateway}/account/mcp) with no token and is answered 401 with
 *      `WWW-Authenticate: Bearer resource_metadata="..."` (RFC 9728 5.1).
 *   2. The protected-resource metadata names OTTOYARD's authorization server, https://www.ottoyard.com. Its metadata
 *      (RFC 8414) is published THERE, at the origin's /.well-known/oauth-authorization-server, because every path-scoped
 *      well-known address on supabase.co answers 401 and an MCP client's discovery stops at anything but a 404
 *      (Hermes Agent, tools/mcp_oauth_device.py, read 2026-10-10). The endpoints it lists are this gateway's.
 *   3. It registers (RFC 7591), then either asks for a device code (RFC 8628: Hermes on a server, reached through
 *      Telegram) or sends its person's browser to the authorization endpoint (code + PKCE S256).
 *   4. Its person signs in at www.ottoyard.com/connect (Supabase Auth of this project), sees which agent is asking and
 *      what it could do, and approves. The agent's poll (or its code exchange) gets an access token and a refresh token.
 *   5. It calls the signed-in MCP address (or REST) with `Authorization: Bearer oqt_...`. The database maps the token to
 *      the connection's principal: exactly an owner key's scope, the same door, ledger and receipts as every agent.
 *
 * WHAT LIVES WHERE: every decision (who may connect, which code is valid, what a token reaches, rotation, reuse) is in
 * the database (public.ottoq_agent_oauth for these endpoints, public.ottoq_agent_call for every tool). This file hashes
 * each secret it is handed before it calls (a device code, an authorization code, a refresh token, a token to revoke),
 * computes the PKCE S256 of a code_verifier, and shapes the answers the RFCs require.
 *
 * Specs, read 2026-10-10:
 *   MCP authorization (2026-07-28): https://modelcontextprotocol.io/specification/latest/basic/authorization
 *   RFC 9728 protected resource metadata, RFC 8414 server metadata, RFC 7591 registration, RFC 8628 device grant,
 *   RFC 7009 revocation, RFC 9207 iss, RFC 7636 PKCE, RFC 6749 5.1-5.2 (no-store, error bodies).
 */

export const SIGNIN_ISSUER_DEFAULT = "https://www.ottoyard.com";
export const SIGNIN_PAGE_DEFAULT = "https://www.ottoyard.com/connect";
/** The one database function the sign-in endpoints call (service_role only). */
export const OAUTH_RPC = "ottoq_agent_oauth";
/** The MCP address an agent signed in to an owner's account uses. Requires a Bearer access token; never the passcode door. */
export const ACCOUNT_MCP_PATH = "/account/mcp";
export const PRM_PATH = "/.well-known/oauth-protected-resource";
export const DEVICE_GRANT = "urn:ietf:params:oauth:grant-type:device_code";
/** One scope: see and set what the account's own cars need (read + note + owner_settings, pinned by a CHECK). */
export const SIGNIN_SCOPE = "fleet";
/** An access token as public.ottoq_oauth_mint mints it. */
export const ACCESS_TOKEN_PATTERN = /^oqt_[0-9a-f]{64}$/;
const SECRET = { device_code: /^oqd_[0-9a-f]{64}$/, code: /^oqg_[0-9a-f]{64}$/, refresh_token: /^oqr_[0-9a-f]{64}$/ } as const;
const VERIFIER = /^[A-Za-z0-9._~-]{43,128}$/;
const MAX_FORM_BYTES = 16 * 1024;

export type SigninConfig = {
  /** The gateway's public base URL, no trailing slash. */
  publicUrl: string;
  /** OTTOYARD's authorization server (where its RFC 8414 metadata is published). */
  issuer: string;
  /** The sign-in page a person approves an agent on. */
  signinPage: string;
};

export type OAuthOutcome = { ok: boolean; http_status: number; body: Record<string, unknown> | null; redirect_uri?: string; state?: string | null };
export type OAuthRpc = (op: string, args: Record<string, unknown>, meta: Record<string, unknown>) => Promise<OAuthOutcome>;

export const accountResource = (publicUrl: string): string => `${publicUrl}${ACCOUNT_MCP_PATH}`;
export const resourceMetadataUrl = (publicUrl: string): string => `${publicUrl}${PRM_PATH}${ACCOUNT_MCP_PATH}`;

/** RFC 9728: what the signed-in MCP address is and who signs agents in for it. */
export function protectedResourceMetadata(c: SigninConfig) {
  return {
    resource: accountResource(c.publicUrl),
    authorization_servers: [c.issuer],
    scopes_supported: [SIGNIN_SCOPE],
    bearer_methods_supported: ["header"],
    resource_name: "OTTOYARD",
    resource_documentation: c.signinPage,
  };
}

/** RFC 8414: OTTOYARD's authorization server. Published at {issuer}/.well-known/oauth-authorization-server (the
 *  OTTOYARD-SITE repository serves this exact document); GET {gateway}/oauth/metadata returns it too, so the two can be
 *  compared. */
export function authorizationServerMetadata(c: SigninConfig) {
  const e = (p: string) => `${c.publicUrl}/oauth/${p}`;
  return {
    issuer: c.issuer,
    authorization_endpoint: e("authorize"),
    token_endpoint: e("token"),
    device_authorization_endpoint: e("device"),
    registration_endpoint: e("register"),
    revocation_endpoint: e("revoke"),
    response_types_supported: ["code"],
    grant_types_supported: ["authorization_code", "refresh_token", DEVICE_GRANT],
    code_challenge_methods_supported: ["S256"],
    token_endpoint_auth_methods_supported: ["none"],
    revocation_endpoint_auth_methods_supported: ["none"],
    scopes_supported: [SIGNIN_SCOPE],
    authorization_response_iss_parameter_supported: true,
    service_documentation: c.signinPage,
  };
}

/** The 401 challenge on the signed-in MCP address: where the resource metadata is, and the scope (RFC 9728 5.1; MCP's
 *  scope selection). `invalid_token` when a token was presented (RFC 6750 3.1), so a client refreshes it. */
export function accountChallenge(publicUrl: string, presentedToken: boolean): string {
  return `Bearer resource_metadata="${resourceMetadataUrl(publicUrl)}", scope="${SIGNIN_SCOPE}"`
    + (presentedToken ? `, error="invalid_token"` : "");
}

/** An application/x-www-form-urlencoded body (RFC 6749 3.2), or a JSON object a lenient client sent instead. */
export function parseForm(bodyText: string, contentType: string | null): Record<string, string> | null {
  const ct = (contentType ?? "").toLowerCase();
  if (ct.includes("application/json")) {
    try {
      const o = JSON.parse(bodyText || "{}");
      if (!o || typeof o !== "object" || Array.isArray(o)) return null;
      const out: Record<string, string> = {};
      for (const [k, v] of Object.entries(o)) if (typeof v === "string") out[k] = v;
      return out;
    } catch { return null; }
  }
  const out: Record<string, string> = {};
  for (const [k, v] of new URLSearchParams(bodyText)) {
    if (k in out) return null; // RFC 6749 3.2: a parameter must not be repeated
    out[k] = v;
  }
  return out;
}

const b64url = (bytes: Uint8Array): string => {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

/** RFC 7636 4.6: BASE64URL(SHA256(ASCII(code_verifier))). */
export async function pkceS256(verifier: string): Promise<string> {
  return b64url(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier))));
}

async function sha256Hex(text: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(buf), (b) => b.toString(16).padStart(2, "0")).join("");
}

/** Is `resource` (RFC 8707) the signed-in MCP address, or absent? Compared without a trailing slash or case in the
 *  scheme and host (MCP: "SHOULD accept uppercase scheme and host"). */
export function resourceIsOurs(resource: string | undefined, publicUrl: string): boolean {
  if (resource === undefined || resource === "") return true;
  const norm = (u: string): string | null => {
    try {
      const x = new URL(u);
      if (x.hash) return null;
      return `${x.protocol}//${x.host}${x.pathname.replace(/\/+$/, "")}${x.search}`.toLowerCase();
    } catch { return null; }
  };
  const want = norm(accountResource(publicUrl));
  const got = norm(resource);
  return got !== null && (got === want || got === norm(publicUrl));
}

/** public.ottoq_agent_oauth over PostgREST with the service key (as postgrestEngine reaches ottoq_agent_call). */
export function postgrestOAuth(o: { supabaseUrl: string; serviceKey: string; fetchImpl?: typeof fetch; timeoutMs?: number }): OAuthRpc {
  const endpoint = `${o.supabaseUrl.replace(/\/+$/, "")}/rest/v1/rpc/${OAUTH_RPC}`;
  const headers: Record<string, string> = { "Content-Type": "application/json", Accept: "application/json", apikey: o.serviceKey };
  if (/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(o.serviceKey)) headers.Authorization = `Bearer ${o.serviceKey}`;
  const doFetch = o.fetchImpl ?? fetch;
  const timeoutMs = o.timeoutMs ?? 15_000;
  const unavailable = (status: number, description: string): OAuthOutcome =>
    ({ ok: false, http_status: status, body: { error: "temporarily_unavailable", error_description: description } });
  return async (op, args, meta) => {
    let res: Response;
    try {
      res = await doFetch(endpoint, { method: "POST", headers, body: JSON.stringify({ p_op: op, p_args: args, p_meta: meta }),
                                      signal: AbortSignal.timeout(timeoutMs) });
    } catch {
      return unavailable(503, "OTTOYARD's sign-in could not be reached. Try again shortly.");
    }
    const text = await res.text();
    let body: unknown = null;
    try { body = text ? JSON.parse(text) : null; } catch { body = null; }
    if (res.ok && body && typeof body === "object" && typeof (body as { http_status?: unknown }).http_status === "number") {
      return body as OAuthOutcome;
    }
    if (res.status === 404) return unavailable(503, "OTTOYARD sign-in is built but not enabled yet (migration 0660).");
    return unavailable(502, "OTTOYARD's sign-in answered outside the gateway's contract.");
  };
}

const JSON_HEADERS = { "Content-Type": "application/json; charset=utf-8", "X-Content-Type-Options": "nosniff" };
/** OAuth endpoints carry no cookies or ambient credentials, so any origin may call them (the secrets are the proof). */
const OPEN_CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Expose-Headers": "www-authenticate" };

function json(status: number, body: unknown, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...JSON_HEADERS, ...OPEN_CORS, ...extra } });
}
/** RFC 6749 5.1: a response carrying tokens or token errors is never cached. */
const NO_STORE = { "Cache-Control": "no-store", Pragma: "no-cache" };
const oauthError = (status: number, error: string, description: string, extra: Record<string, string> = {}): Response =>
  json(status, { error, error_description: description }, { ...NO_STORE, ...extra });

async function readBody(req: Request): Promise<string | null> {
  const declared = Number(req.headers.get("content-length") ?? "0");
  if (Number.isFinite(declared) && declared > MAX_FORM_BYTES) return null;
  const text = await req.text();
  return new TextEncoder().encode(text).byteLength > MAX_FORM_BYTES ? null : text;
}

function withQuery(base: string, params: Record<string, string | null | undefined>): string {
  const u = new URL(base);
  for (const [k, v] of Object.entries(params)) if (v !== undefined && v !== null) u.searchParams.set(k, v);
  return u.toString();
}

const SIGNIN_PATHS = new Set([PRM_PATH, `${PRM_PATH}${ACCOUNT_MCP_PATH}`, "/oauth/metadata", "/oauth/register", "/oauth/device",
  "/oauth/token", "/oauth/revoke", "/oauth/authorize"]);

/** Is this one of the sign-in paths (the gateway hands these to handleSignin before its Origin and key checks)? */
export const isSigninPath = (path: string): boolean => SIGNIN_PATHS.has(path);

/**
 * The sign-in endpoints. `path` is the gateway path ('/oauth/token'), `meta` what the ledger may record (the caller's
 * IP and user agent). Never logs or forwards a raw secret: each is hashed here first.
 */
export async function handleSignin(req: Request, path: string, cfg: SigninConfig, rpc: OAuthRpc | null,
                                   meta: Record<string, unknown>): Promise<Response> {
  const method = req.method.toUpperCase();
  if (method === "OPTIONS") {
    return new Response(null, { status: 204, headers: { ...OPEN_CORS, "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      "Access-Control-Allow-Headers": "authorization, content-type, mcp-protocol-version", "Access-Control-Max-Age": "600" } });
  }

  // documents: public, cacheable
  if (path === PRM_PATH || path === `${PRM_PATH}${ACCOUNT_MCP_PATH}` || path === "/oauth/metadata") {
    if (method !== "GET" && method !== "HEAD") return json(405, { error: "method_not_allowed" }, { Allow: "GET, HEAD, OPTIONS" });
    const doc = path === "/oauth/metadata" ? authorizationServerMetadata(cfg) : protectedResourceMetadata(cfg);
    const res = json(200, doc, { "Cache-Control": "public, max-age=300" });
    return method === "HEAD" ? new Response(null, { status: 200, headers: res.headers }) : res;
  }

  if (!rpc) return oauthError(500, "server_error", "The gateway is deployed without its database connection.");

  // the browser authorization (code + PKCE): validated, recorded, then the person goes to the sign-in page
  if (path === "/oauth/authorize") {
    if (method !== "GET") return json(405, { error: "method_not_allowed" }, { Allow: "GET" });
    const q = new URL(req.url).searchParams;
    const args: Record<string, unknown> = { issuer: cfg.issuer };
    for (const k of ["client_id", "redirect_uri", "response_type", "code_challenge", "code_challenge_method", "state", "scope", "resource"]) {
      const v = q.get(k);
      if (v !== null) args[k] = v.slice(0, 600);
    }
    if (!resourceIsOurs(q.get("resource") ?? undefined, cfg.publicUrl)) {
      return new Response("This sign-in names a resource OTTOYARD does not serve (RFC 8707 resource).",
        { status: 400, headers: { "Content-Type": "text/plain; charset=utf-8" } });
    }
    args.resource = accountResource(cfg.publicUrl);
    const out = await rpc("authorize", args, meta);
    if (out.ok && out.body && typeof out.body.request_id === "string") {
      return new Response(null, { status: 302, headers: { Location: withQuery(cfg.signinPage, { request: out.body.request_id }), "Cache-Control": "no-store" } });
    }
    const err = out.body ?? { error: "server_error", error_description: "The sign-in could not start." };
    if (out.redirect_uri) {
      return new Response(null, { status: 302, headers: { "Cache-Control": "no-store", Location: withQuery(out.redirect_uri, {
        error: String(err.error), error_description: String(err.error_description ?? ""), state: out.state ?? undefined, iss: cfg.issuer }) } });
    }
    // RFC 6749 4.1.2.1: an unverifiable client or redirect URI is shown to the person, never redirected to
    return new Response(`OTTOYARD could not start this sign-in: ${String(err.error_description ?? err.error)}`,
      { status: out.http_status >= 400 ? out.http_status : 400, headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" } });
  }

  if (method !== "POST") return json(405, { error: "method_not_allowed" }, { Allow: "POST, OPTIONS" });
  const text = await readBody(req);
  if (text === null) return oauthError(413, "invalid_request", `The body is limited to ${MAX_FORM_BYTES} bytes.`);

  if (path === "/oauth/register") {
    let reg: unknown;
    try { reg = JSON.parse(text || "{}"); } catch { return oauthError(400, "invalid_client_metadata", "The registration must be JSON."); }
    if (!reg || typeof reg !== "object" || Array.isArray(reg)) return oauthError(400, "invalid_client_metadata", "The registration must be a JSON object.");
    const out = await rpc("register", reg as Record<string, unknown>, meta);
    return json(out.http_status, out.body ?? {}, NO_STORE);
  }

  const form = parseForm(text, req.headers.get("content-type"));
  if (form === null) return oauthError(400, "invalid_request", "Send the parameters form-encoded, once each.");

  if (path === "/oauth/device") {
    if (!resourceIsOurs(form.resource, cfg.publicUrl)) return oauthError(400, "invalid_target", "resource must be OTTOYARD's signed-in MCP address.");
    const out = await rpc("device_authorize", { client_id: form.client_id, scope: form.scope, resource: accountResource(cfg.publicUrl) }, meta);
    if (!out.ok || !out.body) return json(out.http_status, out.body ?? { error: "server_error" }, NO_STORE);
    const code = String(out.body.user_code);
    return json(200, { ...out.body, verification_uri: cfg.signinPage, verification_uri_complete: withQuery(cfg.signinPage, { code }) }, NO_STORE);
  }

  if (path === "/oauth/token") {
    const grant = form.grant_type ?? "";
    const args: Record<string, unknown> = { grant_type: grant, client_id: form.client_id };
    if (form.resource !== undefined && !resourceIsOurs(form.resource, cfg.publicUrl)) {
      return oauthError(400, "invalid_target", "resource must be OTTOYARD's signed-in MCP address.");
    }
    if (grant === DEVICE_GRANT) {
      if (!SECRET.device_code.test(form.device_code ?? "")) return oauthError(400, "invalid_grant", "Unknown device_code.");
      args.device_code_hash = await sha256Hex(form.device_code);
    } else if (grant === "authorization_code") {
      if (!SECRET.code.test(form.code ?? "")) return oauthError(400, "invalid_grant", "Unknown authorization code.");
      if (!VERIFIER.test(form.code_verifier ?? "")) return oauthError(400, "invalid_grant", "PKCE: code_verifier is required (43-128 characters).");
      args.code_hash = await sha256Hex(form.code);
      args.code_challenge_s256 = await pkceS256(form.code_verifier);
      if (form.redirect_uri !== undefined) args.redirect_uri = form.redirect_uri;
    } else if (grant === "refresh_token") {
      if (!SECRET.refresh_token.test(form.refresh_token ?? "")) return oauthError(400, "invalid_grant", "Unknown refresh token.");
      args.refresh_token_hash = await sha256Hex(form.refresh_token);
    }
    const out = await rpc("token", args, meta);
    return json(out.http_status, out.body ?? { error: "server_error" }, NO_STORE);
  }

  // path === "/oauth/revoke" (RFC 7009): 200 whether or not the token was known
  if (form.token) {
    await rpc("revoke", { token_hash: await sha256Hex(form.token), token_type_hint: form.token_type_hint }, meta);
  }
  return json(200, {}, NO_STORE);
}
