// ottoq-benchmark-run — U5d controller (CRN A/B on the ISOLATED benchmark depot 22222222; never
// touches production). For each policy: reset benchmark -> run -> advance ONE TICK PER CALL (separate
// txns, dodges bulk-sync timeout) capturing a replay frame each tick -> score -> abort.
// v4 (hardening): (1) reset self-heals zombie runs (also enforced in SQL);
// (2) NEW fault_chargers param — fault the first N chargers (deterministic order,
// identical in BOTH arms) right after reset: one-call STRESS CERTS (outage story).
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const BENCH = "22222222-2222-2222-2222-222222222222";
const SCENARIO_ID = "ef24648f-eaf6-4686-bd07-1e018a8224ab";
const ALLOWED = ["manual", "fifo", "greedy", "otto_q"];
function json(o: any, s = 200) { return new Response(JSON.stringify(o), { status: s, headers: { ...cors, "Content-Type": "application/json" } }); }

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  try {
    const body = req.method === "POST" ? await req.json().catch(() => ({})) : {};
    const policies: string[] = (Array.isArray(body.policies) && body.policies.length ? body.policies : ["manual", "fifo", "otto_q"]).filter((p: string) => ALLOWED.includes(p));
    const ticks = Math.max(1, Math.min(Number(body.ticks) || 22, 40));
    const arrival_soc = Number(body.arrival_soc ?? 30);
    const target_soc = Number(body.target_soc ?? 80);
    const seed = Number(body.seed ?? 777);
    const fault_chargers = Math.max(0, Math.min(Number(body.fault_chargers ?? 0), 40));
    const isAsync = body.async !== false;
    const comparison_id: string = body.comparison_id || crypto.randomUUID();
    if (!policies.length) return json({ error: "no valid policies" }, 422);

    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    const runAll = async () => {
      await sb.from("ottoq_benchmark_frames").delete().eq("comparison_id", comparison_id);
      await sb.from("ottoq_ab_runs").delete().eq("ab_group_id", comparison_id);
      const timeline: Record<string, any[]> = {};
      for (const pol of policies) {
        const now = new Date().toISOString();
        const end = new Date(Date.now() + 86400000).toISOString();
        await sb.rpc("ottoq_benchmark_reset", { p_depot: BENCH, p_arrival_soc: arrival_soc, p_target_soc: target_soc });
        // STRESS: fault the first N chargers in deterministic stall_code order —
        // identical set in every arm, so the comparison stays CRN-fair.
        if (fault_chargers > 0) {
          const { data: stalls } = await sb.from("stalls")
            .select("ocpp_charger_id, stall_code, stall_type").eq("depot_id", BENCH)
            .in("stall_type", ["dcfc", "l2"]).order("stall_type").order("stall_code").limit(fault_chargers);
          const ids = (stalls ?? []).map((s: any) => s.ocpp_charger_id).filter(Boolean);
          if (ids.length) {
            await sb.from("ottoq_ocpp_chargers")
              .update({ station_state: "Faulted", last_fault_code: "STRESS_OUTAGE_CERT" })
              .in("charger_id", ids);
          }
        }
        const { data: run, error: rErr } = await sb.from("ottoq_sim_runs").insert({
          scenario_id: SCENARIO_ID, scenario_code: "normal_day", sim_clock_start: now, sim_clock_current: now, sim_clock_end: end,
          depot_id: BENCH, time_scale: 60, tick_interval_seconds: 30, status: "running", policy: pol, run_by: "benchmark",
          tick_count: 0, random_seed: seed, ab_group_id: comparison_id, started_at: now, last_tick_at: now, next_tick_due_at: now,
        }).select("sim_run_id").single();
        if (rErr || !run) continue;
        const frames: any[] = [];
        for (let t = 1; t <= ticks; t++) {
          const { data: frame, error: aErr } = await sb.rpc("ottoq_sim_advance_and_snapshot", { p_run: run.sim_run_id });
          if (aErr) break;
          frames.push({ comparison_id, policy: pol, tick: t, frame });
          if (t % 4 === 0) await sb.from("ottoq_benchmark_frames").insert(frames.slice(-4)); // stream frames for live polling
        }
        const remainder = frames.length % 4;
        if (remainder) await sb.from("ottoq_benchmark_frames").insert(frames.slice(-remainder));
        await sb.rpc("ottoq_score_run", { p_sim_run_id: run.sim_run_id });
        await sb.from("ottoq_sim_runs").update({ status: "aborted" }).eq("sim_run_id", run.sim_run_id);
        timeline[pol] = frames.map((f) => ({ tick: f.tick, ...f.frame }));
      }
      // leave the depot healthy for the next cert
      if (fault_chargers > 0) {
        await sb.from("ottoq_ocpp_chargers")
          .update({ station_state: "Available", last_fault_code: null })
          .eq("depot_id", BENCH).eq("last_fault_code", "STRESS_OUTAGE_CERT");
      }
      return timeline;
    };

    if (isAsync) {
      // @ts-ignore EdgeRuntime is provided by the Supabase edge runtime
      EdgeRuntime.waitUntil(runAll());
      return json({ comparison_id, status: "started", depot: BENCH, ticks, policies, fault_chargers, total_ticks: ticks * policies.length });
    }
    const timeline = await runAll();
    const { data: scoreboard } = await sb.from("ottoq_ab_runs")
      .select("policy,vehicles_turned_around,throughput_per_hr,gate_backlog,unsafe_deploys,safety_critical_violations,fleet_ready_pct,peak_demand_pct_of_cap,charge_sessions")
      .eq("ab_group_id", comparison_id);
    return json({ comparison_id, depot: BENCH, ticks, policies, scoreboard: scoreboard ?? [], timeline });
  } catch (e) { return json({ error: e instanceof Error ? e.message : "unknown" }, 500); }
});
