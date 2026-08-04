// ottoq-energy-mpc — bridge: twin (pg_net) -> this edge fn -> AWS intelligence service.
// pg_net can't reach the EC2 box directly (DB egress is HTTPS/edge-fn only), so this
// Deno function (unrestricted fetch) forwards the /optimize/energy request. Custom
// x-bridge-token auth (verify_jwt disabled so the twin can call it simply).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const AWS_URL = Deno.env.get("OTTOQ_INTEL_URL") ?? "http://100.53.130.57:8080";
const AWS_TOKEN = Deno.env.get("OTTOQ_INTEL_TOKEN") ?? "ottoq-frontier-a7f3c9d1e5b8";
const BRIDGE_TOKEN = Deno.env.get("OTTOQ_BRIDGE_TOKEN") ?? "ottoq-frontier-a7f3c9d1e5b8";
const j = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
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
