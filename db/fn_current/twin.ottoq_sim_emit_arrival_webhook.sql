-- CAPTURED LIVE from gxdrcyphqjzjsuhxuqtg via pg_get_functiondef, 2026-08-19 (run3/C7)
-- md5 at capture: 11af2d80d71ec33e690f789dda765042
CREATE OR REPLACE FUNCTION twin.ottoq_sim_emit_arrival_webhook(p_vehicle_id uuid, p_sim_run_id uuid, p_sim_clock_now timestamp with time zone, p_dispatch_id uuid, p_arrival_soc numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_vehicle           RECORD;
  v_oem               TEXT;
  v_pattern           ottoq_oem_webhook_patterns%ROWTYPE;
  v_seed              BIGINT;
  v_webhook_id        UUID := gen_random_uuid();
  v_payload           JSONB;
  v_payload_complete  BOOLEAN;
  v_missing_fields    TEXT[];
  v_attempt           INTEGER := 1;
  v_max_retries       INTEGER;
  v_latency_ms        INTEGER;
  v_total_latency_ms  INTEGER := 0;
  v_roll_auth         NUMERIC;
  v_roll_rate         NUMERIC;
  v_roll_timeout      NUMERIC;
  v_roll_5xx          NUMERIC;
  v_roll_dup          NUMERIC;
  v_roll_ooo          NUMERIC;
  v_roll_complete     NUMERIC;
  v_delivery          TEXT;
  v_http_status       INTEGER;
  v_validation        TEXT;
  v_is_duplicate      BOOLEAN := FALSE;
  v_is_ooo            BOOLEAN := FALSE;
  v_failed_first      BOOLEAN := FALSE;
  v_backoff_ms        INTEGER[];
  v_jitter_pct        NUMERIC;
BEGIN
  SELECT v.*, fo.fleet_operator_id, fo.av_platform, fo.av_api_vehicle_id, fo.make, fo.config
    INTO v_vehicle
    FROM vehicles v
   CROSS JOIN LATERAL (SELECT v.fleet_operator_id, v.platform::text AS av_platform,
                              v.av_api_vehicle_id, v.make, v.config) fo
   WHERE v.id = p_vehicle_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'vehicle % not found', p_vehicle_id;
  END IF;

  v_oem := LOWER(v_vehicle.av_platform);
  SELECT * INTO v_pattern FROM ottoq_oem_webhook_patterns WHERE oem_name = v_oem AND active = TRUE;
  IF NOT FOUND THEN
    -- No pattern → drop silently (real OEM not yet onboarded)
    RETURN NULL;
  END IF;

  -- LIVE DELIVERY ROUTE: a real signed HTTP POST when this OEM is onboarded live.
  IF v_pattern.live_delivery_enabled
     AND v_pattern.live_endpoint_url IS NOT NULL
     AND v_pattern.live_endpoint_url LIKE 'https://%' THEN
    v_payload := ottoq_sim_build_arrival_payload(v_oem, v_vehicle, p_sim_clock_now, p_arrival_soc, p_dispatch_id,
                   abs(hashtextextended(p_vehicle_id::text || p_sim_clock_now::text || 'arrival', 42)), TRUE);
    PERFORM ottoq_oem_deliver_live(v_webhook_id, p_sim_run_id, p_vehicle_id, v_pattern.fleet_operator_id,
                   v_oem, v_pattern.live_endpoint_url, v_payload, v_pattern.signing_secret_ref, p_sim_clock_now);
    RETURN v_webhook_id;
  END IF;

  v_seed         := abs(hashtextextended(p_vehicle_id::text || p_sim_clock_now::text || 'arrival', 42));
  v_max_retries  := COALESCE((v_pattern.retry_policy->>'max_retries')::int, 3);
  v_backoff_ms   := ARRAY(SELECT (jsonb_array_elements_text(v_pattern.retry_policy->'backoff_ms'))::int);
  v_jitter_pct   := COALESCE((v_pattern.retry_policy->>'jitter_pct')::numeric, 15);

  -- ----- Payload completeness roll -----
  v_roll_complete   := ottoq_sim_seeded_random(v_seed, 'complete');
  v_payload_complete := v_roll_complete < v_pattern.payload_completeness_pct;

  IF NOT v_payload_complete THEN
    -- Pick 1-2 optional fields to omit
    v_missing_fields := ARRAY(
      SELECT jsonb_array_elements_text(v_pattern.optional_fields)
      ORDER BY ottoq_sim_seeded_random(v_seed, 'miss_' || jsonb_array_elements_text(v_pattern.optional_fields))
      LIMIT 1 + FLOOR(ottoq_sim_seeded_random(v_seed, 'miss_n') * 2)::int
    );
  END IF;

  v_payload := ottoq_sim_build_arrival_payload(
    v_oem, v_vehicle, p_sim_clock_now, p_arrival_soc, p_dispatch_id, v_seed, v_payload_complete);

  -- ----- Out-of-order delivery roll -----
  v_roll_ooo := ottoq_sim_seeded_random(v_seed, 'ooo');
  v_is_ooo   := v_roll_ooo < v_pattern.out_of_order_pct;

  -- ----- Attempt loop (handles retries) -----
  LOOP
    v_latency_ms := ottoq_sim_sample_lognormal_ms(
      v_pattern.latency_mean_ms, v_pattern.latency_p99_ms, v_seed,
      'lat_' || v_attempt::text);
    v_total_latency_ms := v_total_latency_ms + v_latency_ms;

    v_roll_timeout := ottoq_sim_seeded_random(v_seed, 'timeout_' || v_attempt::text);
    v_roll_auth    := ottoq_sim_seeded_random(v_seed, 'auth_'    || v_attempt::text);
    v_roll_rate    := ottoq_sim_seeded_random(v_seed, 'rate_'    || v_attempt::text);
    v_roll_5xx     := ottoq_sim_seeded_random(v_seed, '5xx_'     || v_attempt::text);

    -- Failure mode cascade
    IF v_roll_timeout < v_pattern.network_timeout_pct THEN
      v_delivery := 'timed_out';   v_http_status := NULL;
    ELSIF v_roll_auth < v_pattern.auth_failure_pct THEN
      v_delivery := 'auth_failed'; v_http_status := 401;
    ELSIF v_roll_rate < v_pattern.rate_limit_pct THEN
      v_delivery := 'rate_limited';v_http_status := 429;
    ELSIF v_roll_5xx < v_pattern.server_error_5xx_pct THEN
      v_delivery := 'server_error';v_http_status := 502;
    ELSE
      v_delivery := 'delivered';   v_http_status := 200;
    END IF;

    -- Log this attempt (whether success or fail)
    INSERT INTO ottoq_oem_webhook_log (
      webhook_id, sim_run_id, vehicle_id, fleet_operator_id,
      oem_name, webhook_type, http_method, endpoint_url,
      payload, payload_complete, payload_missing_fields,
      attempt_num, is_retry, is_duplicate, is_out_of_order, parent_webhook_id,
      latency_ms, http_status, delivery_status, delivery_mode,
      validation_result, sim_clock_emitted_at, sim_clock_delivered_at,
      data_source
    ) VALUES (
      CASE WHEN v_attempt = 1 THEN v_webhook_id ELSE gen_random_uuid() END,
      p_sim_run_id, p_vehicle_id, v_pattern.fleet_operator_id,
      v_oem, 'arrival', 'POST', v_pattern.webhook_endpoint,
      v_payload, v_payload_complete, v_missing_fields,
      v_attempt, v_attempt > 1, FALSE, v_is_ooo,
      CASE WHEN v_attempt > 1 THEN v_webhook_id ELSE NULL END,
      v_latency_ms, v_http_status, v_delivery, 'simulated',
      CASE
        WHEN v_delivery = 'delivered' AND v_payload_complete THEN 'accepted'
        WHEN v_delivery = 'delivered' AND NOT v_payload_complete THEN 'accepted_partial'
        WHEN v_delivery = 'auth_failed' THEN 'rejected_auth'
        WHEN v_delivery IN ('rate_limited','server_error','timed_out') THEN 'pending_retry'
        ELSE 'rejected_other'
      END,
      p_sim_clock_now + (v_total_latency_ms - v_latency_ms || ' milliseconds')::interval,
      CASE WHEN v_delivery = 'delivered'
           THEN p_sim_clock_now + (v_total_latency_ms || ' milliseconds')::interval
           ELSE NULL END,
      'twin'
    );

    EXIT WHEN v_delivery = 'delivered';
    EXIT WHEN v_delivery = 'auth_failed';     -- auth fail terminates
    EXIT WHEN v_attempt >= v_max_retries;     -- exhausted retries

    -- Apply backoff
    IF array_length(v_backoff_ms, 1) >= v_attempt THEN
      v_total_latency_ms := v_total_latency_ms + v_backoff_ms[v_attempt]
                          + FLOOR(v_backoff_ms[v_attempt] * v_jitter_pct / 100.0
                                  * (ottoq_sim_seeded_random(v_seed, 'jit_' || v_attempt::text) - 0.5) * 2)::int;
    END IF;

    v_attempt := v_attempt + 1;
    v_failed_first := TRUE;
  END LOOP;

  -- ----- Duplicate send roll (only on success) -----
  IF v_delivery = 'delivered' THEN
    v_roll_dup := ottoq_sim_seeded_random(v_seed, 'dup');
    IF v_roll_dup < v_pattern.duplicate_send_pct THEN
      v_is_duplicate := TRUE;
      INSERT INTO ottoq_oem_webhook_log (
        webhook_id, sim_run_id, vehicle_id, fleet_operator_id,
        oem_name, webhook_type, http_method, endpoint_url,
        payload, payload_complete,
        attempt_num, is_retry, is_duplicate, parent_webhook_id,
        latency_ms, http_status, delivery_status, delivery_mode,
        validation_result, sim_clock_emitted_at, sim_clock_delivered_at,
        data_source
      ) VALUES (
        gen_random_uuid(),
        p_sim_run_id, p_vehicle_id, v_pattern.fleet_operator_id,
        v_oem, 'arrival', 'POST', v_pattern.webhook_endpoint,
        v_payload, v_payload_complete,
        1, FALSE, TRUE, v_webhook_id,
        ottoq_sim_sample_lognormal_ms(v_pattern.latency_mean_ms, v_pattern.latency_p99_ms, v_seed, 'dup_lat'),
        200, 'delivered', 'simulated',
        'rejected_duplicate',
        p_sim_clock_now + (FLOOR(2000 + ottoq_sim_seeded_random(v_seed, 'dup_off') * 8000) || ' milliseconds')::interval,
        p_sim_clock_now + (FLOOR(2000 + ottoq_sim_seeded_random(v_seed, 'dup_off') * 8000) + 200 || ' milliseconds')::interval,
        'twin'
      );
    END IF;
  END IF;

  -- Emit canonical twin event for forensic replay
  PERFORM ottoq_record_event(
    p_actor_type    := 'oem_dispatch_webhook',
    p_actor_id      := v_oem || '_arrival_mock',
    p_event_type    := 'twin.oem_webhook_emitted',
    p_entity_type   := 'vehicle',
    p_entity_id     := p_vehicle_id,
    p_fleet_operator_id := v_pattern.fleet_operator_id,
    p_payload       := jsonb_build_object(
      'webhook_id',        v_webhook_id,
      'oem',               v_oem,
      'delivery_status',   v_delivery,
      'attempts',          v_attempt,
      'total_latency_ms',  v_total_latency_ms,
      'payload_complete',  v_payload_complete,
      'is_duplicate',      v_is_duplicate,
      'is_out_of_order',   v_is_ooo,
      'soc_at_arrival',    p_arrival_soc
    ),
    p_severity      := CASE WHEN v_delivery = 'delivered' THEN 'info' ELSE 'warning' END,
    p_ingest_source := 'twin',
    p_data_source   := 'twin',
    p_sim_run_id    := p_sim_run_id
  );

  RETURN v_webhook_id;
END;
$function$

