// ottoq-energy-mpc — bridge: twin (pg_net) -> this edge fn -> AWS intelligence service.
// pg_net can't reach the EC2 box directly (DB egress is HTTPS/edge-fn only), so this
// Deno function (unrestricted fetch) forwards the /optimize/energy request. Custom
// x-bridge-token auth (verify_jwt disabled so the twin can call it simply).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// NO FALLBACKS, AND THE FUNCTION FAILS CLOSED WITHOUT THEM.
// Until 2026-09-07 these three lines carried literal defaults: a hardcoded
// http:// address and, for BOTH tokens, one shared 27-character secret. That
// value was the only thing in front of this function -- it is deployed with
// verify_jwt disabled, so x-bridge-token IS the authentication -- and it was
// simultaneously the bearer token presented to the intelligence service. It
// sat in two tracked files across four commits, so it is in history and must
// be treated as compromised regardless of what this file says now.
// The house rule is "no secrets in code, ever". A default that is a working
// credential is a secret in code that also removes the operator's ability to
// notice the configuration is missing: with a fallback, an unset variable is
// silent; without one, it is a 500 on the first call.
const AWS_URL = Deno.env.get("OTTOQ_INTEL_URL");
const AWS_TOKEN = Deno.env.get("OTTOQ_INTEL_TOKEN");
const BRIDGE_TOKEN = Deno.env.get("OTTOQ_BRIDGE_TOKEN");
const j = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  // Misconfiguration is a 500, never an open door. If BRIDGE_TOKEN were unset
  // and a caller sent no header, both sides would be null and the comparison
  // below would PASS -- an unauthenticated bridge to the intelligence service.
  if (!BRIDGE_TOKEN || !AWS_TOKEN || !AWS_URL) {
    return j({ error: "bridge not configured: set OTTOQ_INTEL_URL, OTTOQ_INTEL_TOKEN and OTTOQ_BRIDGE_TOKEN" }, 500);
  }
  if (req.headers.get("x-bridge-token") !== BRIDGE_TOKEN) return j({ error: "unauthorized" }, 401);
  const url = new URL(req.url);
  try {
    if (url.searchParams.get("probe") === "1" || req.method === "GET") {
      const h = await fetch(`${AWS_URL}/health`);
      return j({ bridge: "ok", aws_url: AWS_URL, aws_health: await h.json() });
    }
    const body = await req.json();
    const r = await fetch(`${AWS_URL}/optimize/energy`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${AWS_TOKEN}` },
      body: JSON.stringify(body),
    });
    return new Response(await r.text(), { status: r.status, headers: { "Content-Type": "application/json" } });
  } catch (e) {
    return j({ error: e instanceof Error ? e.message : "bridge_fetch_failed", aws_url: AWS_URL }, 502);
  }
});
