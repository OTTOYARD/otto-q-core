-- migration-version: 20260830053000
-- migration-name:    the_cert_run_quiesces_the_llm_proposer
-- 0105 -- closes determinism pair 8's LAST front. After 0104, the pair-8 arms (966dd746 /
-- 7814f235, seed 424242, 12 ticks) were byte-identical on the COMMAND stream (671/671, equal
-- hash) and on DECISION content for ticks 1-11. The only remaining divergence sits in the
-- final tick's task_start rows, and it is not a cursor: it is the ORCHESTRATOR AGENT.
--
-- public.ottoq_sim_decide_and_dispatch fires the ottoq-orchestrator-agent edge function
-- (net.http_post, every 3rd tick) and that agent calls a hosted LLM
-- (nvidia/nemotron-3-ultra-550b-a55b), then writes set_policy decisions back into the run.
-- Ledger proof from pair 8, tick 12: arm A received two model batches
-- (energy_demand_factor_peak -> 0.45 then 0.65); arm B got an HTTP 429/503 fallback and then
-- a DIFFERENT batch (deploy_peak_fraction 0.95, factor 0.6). A network round-trip to a
-- sampling LLM can never be replayed by seed; on longer runs its mid-run policy writes fork
-- everything downstream.
--
-- The gate already excludes benchmark runs. cert_harness -- the run_by the determinism
-- instrument and the metronome exemption both use -- was NOT excluded: the certification
-- run measuring the deterministic core had a live LLM adjusting its policies mid-flight.
-- Same class of gap 0056 closed for the cuOpt proposer (cert quiesce), same posture:
-- agents propose, solver disposes -- and a cert run is solver-only by definition.
--
-- ONE PATCH: the orchestrator-fire gate also requires run_by <> 'cert_harness'. Production
-- and demo runs keep the agent exactly as-is. The determinism claim this enables is scoped
-- honestly: "byte-identical under fixed seed with external proposers quiesced" -- which is
-- the only claim a seed can ever back.
--
-- (Also observed in pair 8, recorded for 0046: ottoq_decisions.enacted_action for
-- bay_reconcile rows embeds ottoq_itinerary_legs.leg_id -- a per-run random uuid -- so
-- full-payload comparisons of otherwise-identical decisions differ cosmetically. The 0046
-- projection already excludes it; any future comparison must, too.)
--
-- Pre-image pin, read live 2026-08-29 (anchor verified at exactly 1 occurrence):
--   public.ottoq_sim_decide_and_dispatch   72e5e6adfa4c4774d37bbaadea4822d0

DO $do$
DECLARE
  v_oid oid; v_src text; v_cnt int;
  v_a_old text := E'IF COALESCE(v_run.run_by,'''') <> ''benchmark''\n     AND NOT v_is_benchmark';
  v_a_new text := E'IF COALESCE(v_run.run_by,'''') NOT IN (''benchmark'', ''cert_harness'')  -- 0105: cert runs quiesce the LLM proposer\n     AND NOT v_is_benchmark';
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_sim_decide_and_dispatch';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '72e5e6adfa4c4774d37bbaadea4822d0' THEN
    RAISE EXCEPTION '0105 abort: decide_and_dispatch drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src)-length(replace(v_src, v_a_old,'')))/length(v_a_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0105 abort: gate anchor found % times', v_cnt; END IF;

  EXECUTE replace(v_src, v_a_old, v_a_new);

  IF position('NOT IN (''benchmark'', ''cert_harness'')' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0105 abort: patch did not survive';
  END IF;

  RAISE NOTICE '0105 applied: cert runs quiesce the LLM proposer.';
END
$do$;
