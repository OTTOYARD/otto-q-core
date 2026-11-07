// ottoq-battery-planner: the seam between the depot battery's plan and the solver that makes it (otto-q-core 0804, B1).
//
// The database asks: public.ottoq_bess_planner_fire writes the planner's request into a 'pending' row of
// ottoq_energy_plan and calls this function with net.http_post, the anon key from the vault (as the orchestrator agent's
// fire does), body {plan_id}. This function reads the request FROM THE ROW, never from the caller, posts it to
// ottoq-intelligence's POST /optimize/battery-plan (app/optimizers/battery_planner.py: the planner the research lab
// measured, $226 a day on the depot's day plan over six 36-hour lab days), and hands the answer to
// public.ottoq_bess_planner_land with the service role, which checks it before the battery may follow it and writes the
// ledger row (ottoq_model_call_ledger, provider intelligence_battery_planner). So a caller holding the anon key can do
// one thing: make a plan the depot already asked for, once (a landed plan is not pending).
//
// 0805 (B2): the same function grades a day in hindsight. Body {hindsight_id}: the request is read from the pending row of
// ottoq_bess_hindsight (the day's realized load: for the planner, perfect foresight) and the answer handed to
// public.ottoq_bess_hindsight_land. The battery never follows a hindsight row: it is not a plan and not in ottoq_energy_plan.
//
// Deploy with verify_jwt ON (the default): the anon key is a JWT the gateway verifies. The service URL is data
// (public.ottoq_service_endpoints, 0398), with OTTOQ_INTEL_URL as the fallback; the token is a secret
// (OTTOQ_INTEL_TOKEN), as for ottoq-cpsat-propose. NO FALLBACK CREDENTIAL: an unset token is a failed plan with its
// reason, landed, never an open door. Advisory, like every plan: the orchestrator follows it only while it is fresh and
// never during a demand-response call (0799), inside the battery's own limits. It moves only the battery.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SERVICE_TIMEOUT_MS = 25_000;   // the plan is a 36-hour LP of ~2,000 variables: 20-90 ms solved in the lab

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ ok: false, error: "POST only" }, 405);
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const envIntelligenceUrl = Deno.env.get("OTTOQ_INTEL_URL");
  const intelligenceToken = Deno.env.get("OTTOQ_INTEL_TOKEN");
  if (!supabaseUrl || !serviceKey) return json({ ok: false, error: "Supabase service configuration is unavailable" }, 500);

  const body = await req.json().catch(() => ({}));
  const planId = typeof body?.plan_id === "string" ? body.plan_id : "";
  const hindsightId = Number.isSafeInteger(body?.hindsight_id) && body.hindsight_id > 0 ? body.hindsight_id as number : 0;
  if (!UUID.test(planId) && !hindsightId) {
    return json({ ok: false, error: "plan_id (a uuid) or hindsight_id (a positive integer) is required" }, 400);
  }

  const sb = createClient(supabaseUrl, serviceKey);
  let request: unknown;
  let land: (answer: unknown, httpStatus: number, latencyMs: number) => Promise<Response>;
  if (hindsightId) {
    const { data: row, error: rowError } = await sb.from("ottoq_bess_hindsight")
      .select("hindsight_id,state,request").eq("hindsight_id", hindsightId).maybeSingle();
    if (rowError) return json({ ok: false, error: rowError.message }, 500);
    if (!row) return json({ ok: false, error: "no such grade" }, 404);
    if (row.state !== "pending") return json({ ok: false, error: `the grade is ${row.state}, not pending` }, 409);
    request = row.request;
    land = async (answer, httpStatus, latencyMs) => {
      const { data, error } = await sb.rpc("ottoq_bess_hindsight_land", {
        p_hindsight_id: hindsightId, p_response: answer, p_http_status: httpStatus, p_latency_ms: latencyMs,
      });
      return json({ ok: !error && data?.ok === true, landed: data ?? null, latency_ms: latencyMs, error: error?.message ?? null },
                  error ? 500 : 200);
    };
  } else {
    const { data: plan, error: planError } = await sb.from("ottoq_energy_plan")
      .select("id,source,plan_state,detail").eq("id", planId).maybeSingle();
    if (planError) return json({ ok: false, error: planError.message }, 500);
    if (!plan) return json({ ok: false, error: "no such plan" }, 404);
    if (plan.source !== "bess_planner" || plan.plan_state !== "pending") {
      return json({ ok: false, error: `the plan is ${plan.source}/${plan.plan_state}, not a pending battery plan` }, 409);
    }
    request = plan.detail?.request;
    land = async (answer, httpStatus, latencyMs) => {
      const { data, error } = await sb.rpc("ottoq_bess_planner_land", {
        p_plan_id: planId, p_response: answer, p_http_status: httpStatus, p_latency_ms: latencyMs,
      });
      return json({ ok: !error && data?.ok === true, landed: data ?? null, latency_ms: latencyMs, error: error?.message ?? null },
                  error ? 500 : 200);
    };
  }

  if (!request || typeof request !== "object") return await land({ error: "the row carries no request" }, 422, 0);

  // 0398: THE ADDRESS OF A SERVICE THAT MOVES IS DATA, NOT A DEPLOY-TIME SECRET; the env var is the fallback.
  let intelligenceUrl = envIntelligenceUrl;
  let endpointSource = "env:OTTOQ_INTEL_URL";
  try {
    const { data: dbUrl } = await sb.rpc("ottoq_service_endpoint", { p_service_key: "intelligence" });
    if (typeof dbUrl === "string" && /^https?:\/\/\S+$/.test(dbUrl)) {
      intelligenceUrl = dbUrl;
      endpointSource = "db:ottoq_service_endpoints";
    }
  } catch (_) { /* never fatal: the env var stands */ }
  if (!intelligenceUrl || !intelligenceToken) {
    return await land({
      error: `the battery planner is not configured (url from ${endpointSource}: ${intelligenceUrl ? "present" : "ABSENT"}, ` +
             `token ${intelligenceToken ? "present" : "ABSENT"})`,
    }, 503, 0);
  }

  const t0 = Date.now();
  let httpStatus = 0;
  let answer: unknown;
  try {
    const r = await fetch(`${intelligenceUrl.replace(/\/$/, "")}/optimize/battery-plan`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${intelligenceToken}` },
      body: JSON.stringify(request),
      signal: AbortSignal.timeout(SERVICE_TIMEOUT_MS),
    });
    httpStatus = r.status;
    answer = await r.json().catch(() => ({ error: "the service's answer was not JSON" }));
  } catch (e) {
    httpStatus = 599;
    answer = { error: e instanceof Error ? e.message : "the service could not be reached" };
  }
  return await land(answer, httpStatus, Date.now() - t0);
});
