// RETIRED DIAGNOSTIC. Re-armed 2026-08-01 to empirically establish the NVIDIA cuOpt hosted LP
// contract (12/12 synchronous 200s, solution at response.solver_response.solution.primal_solution),
// then re-retired the same day.
//
// WHY THIS IS INERT: while armed it made BILLABLE NVIDIA API calls and was reachable by anyone
// holding the project's PUBLIC anon key (verify_jwt=true is satisfied by the publishable key).
// It must stay a no-op unless deliberately re-armed for a bounded diagnostic window.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

Deno.serve(() =>
  new Response(
    JSON.stringify({
      error: "gone",
      message:
        "ottoq-cuopt-lp-probe is retired. It made billable NVIDIA calls and was anon-key reachable. Re-arm deliberately and re-retire immediately after.",
      findings_recorded: "project_nvidia_layer_truth_2026_07_30.md",
    }),
    { status: 410, headers: { "Content-Type": "application/json" } },
  )
);
