// ============================================================================
// ottoq-approval-copilot — NVIDIA Nemotron as the SUPERVISOR'S CO-PILOT for the
// in-depot reassignment safety gate. When OTTO-Q wants a discretionary in-depot
// reassignment it is DENIED and queued to ottoq_ops_approvals (founder doctrine:
// no in-depot re-route without technician/supervisor approval). This function
// reviews each PENDING approval, gathers depot context, and asks Nemotron for a
// recommendation (approve | hold | reject + rationale + risks), writing it into
// payload->'copilot'. It NEVER sets status/decided_by — the human still decides.
// Input: { depot_id?, sim_run_id?, approval_type?='indepot_reassign', limit?=8 }.
// ============================================================================
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const NIM = "https://integrate.api.nvidia.com/v1/chat/completions";
const MODEL = "nvidia/nemotron-3-ultra-550b-a55b";
const DEFAULT_DEPOT = "11111111-1111-1111-1111-111111111111";

function json(obj: unknown, status = 200) {
  return new Response(JSON.stringify(obj), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

const SYS = `You are the supervisor's co-pilot at an autonomous AV/EV robotaxi depot. A safety rule requires a human technician/supervisor to approve any DISCRETIONARY reassignment of a vehicle that is already INSIDE the depot walls (re-routes forced by a broken charger/bay are auto-approved elsewhere and never reach you). For each pending approval you are given the vehicle's state and the depot context. Recommend one of: "approve" (the reassignment is clearly beneficial and low-risk), "hold" (wait / need more info / marginal), or "reject" (not worth the disruption or unsafe). You do NOT decide — a human acts on your recommendation. Be conservative: an in-motion or mid-service vehicle should rarely be re-routed. Reason ONLY from the data given; never invent numbers. Respond with STRICT JSON only: {"recommendation":"approve|hold|reject","confidence":0.0-1.0,"rationale":"one or two sentences","risks":["..."]}`;

async function callNemotron(prompt: string): Promise<{ ok: boolean; content?: string; err?: string; key?: string }> {
  const keyCandidates: [string, string | undefined][] = [
    ["NEMOTRON", Deno.env.get("NVIDIA_API_KEY_NEMOTRON")],
    ["CUOPT", Deno.env.get("NVIDIA_API_KEY_CUOPT")],
    ["GENERIC", Deno.env.get("NVIDIA_API_KEY")],
  ];
  const keys = keyCandidates.filter(([, v]) => v) as [string, string][];
  if (keys.length === 0) return { ok: false, err: "no NVIDIA key set" };
  const body = JSON.stringify({
    model: MODEL,
    messages: [{ role: "system", content: SYS }, { role: "user", content: prompt }],
    temperature: 0.2, top_p: 0.9, max_tokens: 500, stream: false,
  });
  let res: Response | null = null, raw = "", usedKey: string | null = null;
  for (const [name, key] of keys) {
    res = await fetch(NIM, { method: "POST",
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json", Accept: "application/json" }, body });
    raw = await res.text();
    if (res.status !== 401 && res.status !== 403) { usedKey = name; break; }
  }
  if (!res || !res.ok) return { ok: false, err: "nemotron HTTP " + (res?.status ?? "?") + ": " + raw.slice(0, 200) };
  try {
    const parsed = JSON.parse(raw);
    return { ok: true, content: parsed?.choices?.[0]?.message?.content ?? "", key: usedKey ?? undefined };
  } catch { return { ok: false, err: "non-JSON: " + raw.slice(0, 160) }; }
}

function extractJson(s: string): any | null {
  if (!s) return null;
  const a = s.indexOf("{"), b = s.lastIndexOf("}");
  if (a < 0 || b <= a) return null;
  try { return JSON.parse(s.slice(a, b + 1)); } catch { return null; }
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  try {
    const body = req.method === "POST" ? await req.json().catch(() => ({})) : {};
    const depot_id = body.depot_id || DEFAULT_DEPOT;
    const approval_type = body.approval_type || "indepot_reassign";
    const limit = Math.min(Number(body.limit) || 8, 20);
    const dryRun = body.dry_run === true;

    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    // pending approvals that don't already carry a co-pilot recommendation
    const { data: approvals } = await sb.from("ottoq_ops_approvals")
      .select("approval_id, vehicle_id, sim_run_id, depot_id, priority, payload, requested_at, approval_type")
      .eq("depot_id", depot_id).eq("approval_type", approval_type).eq("status", "pending")
      .order("requested_at", { ascending: true }).limit(limit);
    if (!approvals || approvals.length === 0) return json({ reviewed: 0, note: "no pending approvals" });

    // depot context (shared): free healthy DCFC count + inbound forecast if a run is live
    const { data: freeDcfc } = await sb.from("stalls")
      .select("id", { count: "exact", head: true })
      .eq("depot_id", depot_id).eq("stall_type", "dcfc").eq("status", "available").is("reserved_by", null);
    const dcfcFree = (freeDcfc as any)?.length ?? null; // head:true returns count via .count when supported

    const results: any[] = [];
    for (const ap of approvals) {
      const { data: veh } = await sb.from("vehicles")
        .select("display_name, current_state, current_soc, current_stall_id").eq("id", ap.vehicle_id).maybeSingle();
      let forecast: any = null;
      if (ap.sim_run_id) {
        const { data: run } = await sb.from("ottoq_sim_runs").select("payload").eq("sim_run_id", ap.sim_run_id).maybeSingle();
        forecast = (run?.payload as any)?.inbound_forecast?.pressure ?? null;
      }
      const ctx = {
        vehicle: veh ? { name: veh.display_name, state: veh.current_state, soc_pct: veh.current_soc, in_stall: !!veh.current_stall_id } : null,
        proposed: ap.payload?.proposed ?? ap.payload?.reason ?? "in_depot_reassignment",
        old_stall_type: ap.payload?.old_type ?? null,
        priority: ap.priority,
        depot: { free_dcfc_reported: dcfcFree, inbound_pressure: forecast },
      };
      const prompt = `Pending in-depot reassignment approval:\n${JSON.stringify(ctx, null, 2)}\n\nRecommend approve/hold/reject with rationale and risks. Remember: a vehicle actively in a service bay or charging should rarely be re-routed; only recommend approve when the benefit is clear and disruption is low.`;

      if (dryRun) { results.push({ approval_id: ap.approval_id, ctx, would_call: true }); continue; }
      const nem = await callNemotron(prompt);
      const rec = nem.ok ? extractJson(nem.content ?? "") : null;
      const copilot = {
        recommendation: rec?.recommendation ?? "hold",
        confidence: typeof rec?.confidence === "number" ? rec.confidence : null,
        rationale: rec?.rationale ?? (nem.ok ? "unparseable model output; defaulting to hold" : nem.err),
        risks: Array.isArray(rec?.risks) ? rec.risks : [],
        model: MODEL, ok: nem.ok, at: new Date().toISOString(),
      };
      // merge into payload->copilot; NEVER touch status/decided_by/decided_at
      const newPayload = { ...(ap.payload ?? {}), copilot };
      await sb.from("ottoq_ops_approvals").update({ payload: newPayload }).eq("approval_id", ap.approval_id);
      results.push({ approval_id: ap.approval_id, vehicle: veh?.display_name, recommendation: copilot.recommendation, confidence: copilot.confidence, ok: nem.ok });
    }
    return json({ reviewed: results.length, approval_type, results });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : "unknown" }, 500);
  }
});
