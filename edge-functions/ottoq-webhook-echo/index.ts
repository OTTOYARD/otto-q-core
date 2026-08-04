// ottoq-webhook-echo — a REAL OEM-side webhook receiver, used to prove end-to-end
// that OTTO-Q delivers a genuine, signed HTTP POST (not a diced '200 OK').
//
// Auth is by HMAC SIGNATURE, not JWT — exactly how a real OEM secures a webhook —
// so verify_jwt is intentionally off. It recomputes HMAC-SHA256 over the raw body
// with the shared TEST secret and compares to the X-OTTOQ-Signature header. A
// tampered or unsigned body gets a real 401. A valid one gets a real 200 with
// signature_valid:true. Nothing here is simulated.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// Shared TEST secret — matches the vault secret 'ottoq_test_webhook_secret' that
// ottoq_oem_deliver_live signs with. Clearly a fixture for the conformance test,
// not a production credential.
const TEST_SECRET = "ottoq-wire1-conformance-secret-2026";

function toHex(buf: ArrayBuffer): string {
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "POST only" }), { status: 405, headers: { "Content-Type": "application/json" } });
  }
  const rawBody = await req.text();
  const sigHeader = req.headers.get("X-OTTOQ-Signature") ?? "";
  const received = sigHeader.replace(/^sha256=/, "");
  const webhookId = req.headers.get("X-OTTOQ-Webhook-Id") ?? null;
  const eventType = req.headers.get("X-OTTOQ-Event") ?? null;

  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(TEST_SECRET),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(rawBody));
  const expected = toHex(mac);

  // constant-time-ish compare
  let ok = received.length === expected.length;
  for (let i = 0; i < expected.length; i++) ok = ok && received[i] === expected[i];

  const body = JSON.stringify({
    received: true,
    signature_valid: ok,
    webhook_id: webhookId,
    event_type: eventType,
    body_bytes: rawBody.length,
  });
  return new Response(body, {
    status: ok ? 200 : 401,
    headers: { "Content-Type": "application/json" },
  });
});
