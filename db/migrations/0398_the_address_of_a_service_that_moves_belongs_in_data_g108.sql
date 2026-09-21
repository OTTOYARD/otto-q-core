-- migration-version: 20260921073824
-- migration-name:    the_address_of_a_service_that_moves_belongs_in_data_g108
--
-- 0398  G108, THE LAST LINK. **The CP-SAT service's address lives in a deploy-time secret, and the
--       address moved.** `ottoq-cpsat-propose` reads `OTTOQ_INTEL_URL` from the Supabase function
--       environment, which is set once by hand and never moves. The EC2 box carried **no Elastic
--       IP**, so its public IPv4 changed when it was stopped at 2026-09-21 02:52 and started again
--       at 03:29:21 — and from that moment the secret named an address nothing answers on.
--
-- **THE COST OF THAT, MEASURED (`db/checks/0301` §4–5), and it is the whole of G108:**
--
--   POST /assign lines in the service's own uvicorn access log        **0**
--   /health on loopback                                              answered in **14 ms**
--   /health body                        optimizers ["energy_mpc","cp_sat_forward_lex"]
--   container CPU / loadavg / nproc                                  0.14% / 0.00 / 2
--   edge-side attempts on run f13fc580   **12, all 20005–20011 ms, http_status NULL on every one**
--
-- A healthy, idle, correctly-built solver that has never once been asked a question, and a caller
-- whose twelve attempts cluster inside 6 ms of its timeout — which is a connection that never
-- completes, not a variable-difficulty solve.
--
-- **THE ADDRESS IS NOW STABLE**: an Elastic IP was allocated and associated
-- (`aws-activate-ssm action=assign_eip`), and `http://54.227.173.111:8080/health` answered **from
-- the GitHub runner** — genuinely off the box — listing `cp_sat_forward_lex`. So the security
-- group, the published port and the subnet's route are all confirmed good, and the address will
-- not move again across a stop/start. AWS charges the same $0.005/hour for a public IPv4 whether
-- Elastic or auto-assigned (sourced in the workflow header), so this replaced a charge rather than
-- adding one.
--
-- ══ WHY THIS MIGRATION EXISTS AT ALL, RATHER THAN JUST EDITING THE SECRET ══
--
-- Because the secret cannot be edited from here, and more importantly **because it should not have
-- been the only place the address lived.** A deploy-time secret is the right home for a credential
-- and the wrong home for the location of a service that moves: changing it needs a human with
-- console access, there is no record of when it last changed, and nothing can assert that it points
-- anywhere real. The address of a moving service is DATA.
--
-- So: `public.ottoq_service_endpoints` holds the base URL, and `ottoq-cpsat-propose` prefers it
-- over the environment variable, falling back when the row is absent or malformed. The division is
-- deliberate and must not be blurred:
--
--   **the URL goes in the database** — it is not a secret, it changes, and an operator (or an
--   agent with SQL access and no console) must be able to correct it in one statement;
--   **the TOKEN stays in `OTTOQ_INTEL_TOKEN`** — it is a credential, this repo is public, and
--   nothing about a token being awkward to rotate makes a table the right place for it.
--
-- NOT RUN-SCOPED, so nothing is owed to `ottoq_run_scope_registry`. The table carries no
-- `sim_run_id` / `run_id` / `owning_sim_run_id` / `source_run_id`, which is exactly the set
-- `ottoq_check_run_scope_registry` check (a) watches, so it cannot raise an unregistered-column
-- warning. It is configuration: it must survive every purge, and it does so by not being
-- registered rather than by being classified `evidence`.
--
-- `forces_recert` **FALSE**, and this one is measurable rather than argued: the table is created by
-- this migration, so no digest, fingerprint or KPI view can read it — there was nothing to read
-- until now. `ottoq_world_fingerprint`, `ottoq_frame_hash_payload` and the fourteen atoms are
-- untouched. A new table that nothing hashed references cannot move a hash.

BEGIN;

CREATE TABLE IF NOT EXISTS public.ottoq_service_endpoints (
  service_key  text PRIMARY KEY,
  base_url     text        NOT NULL,
  updated_at   timestamptz NOT NULL DEFAULT now(),
  updated_by   text        NOT NULL DEFAULT current_user,
  note         text,
  -- Shape, not reachability. A value that is not a URL at all is a configuration error worth
  -- refusing at write time; whether anything answers there is the caller's business and is
  -- recorded per attempt in ottoq_model_call_ledger.
  CONSTRAINT ottoq_service_endpoints_url_shape
    CHECK (base_url ~ '^https?://[^[:space:]/]+(/[^[:space:]]*)?$')
);

COMMENT ON TABLE public.ottoq_service_endpoints IS
  '0398. Base URLs of external compute services the engine calls, so the location of a service '
  'that moves is DATA and not a deploy-time secret. NEVER put a credential here -- tokens stay in '
  'the Supabase function environment. Not run-scoped: no sim_run_id, so ottoq_check_run_scope_'
  'registry has nothing to classify and the purge has nothing to delete. Read by '
  'ottoq-cpsat-propose, which prefers this over OTTOQ_INTEL_URL and records which source it used '
  'in the ledger detail.';

COMMENT ON COLUMN public.ottoq_service_endpoints.base_url IS
  'Scheme, host and port, no trailing slash and no path unless the service needs one. The caller '
  'appends its own path (/assign, /health).';

-- The intelligence service, at the Elastic IP associated 2026-09-21 07:24 UTC and verified
-- answering /health from off the box with cp_sat_forward_lex in its optimizer list.
INSERT INTO public.ottoq_service_endpoints (service_key, base_url, updated_by, note)
VALUES ('intelligence', 'http://54.227.173.111:8080', 'migration_0398',
        'Elastic IP, associated 2026-09-21 07:24 UTC by aws-activate-ssm action=assign_eip. '
        'Stable across stop/start, which the previous auto-assigned address was not -- that is '
        'G108. Verified from the GitHub runner: /health 200 listing cp_sat_forward_lex.')
ON CONFLICT (service_key) DO UPDATE
  SET base_url = EXCLUDED.base_url, updated_at = now(),
      updated_by = EXCLUDED.updated_by, note = EXCLUDED.note;

-- The getter, so callers never hand-roll the lookup and a missing row is a NULL rather than an
-- error. SECURITY INVOKER on purpose: this is not privileged data.
CREATE OR REPLACE FUNCTION public.ottoq_service_endpoint(p_service_key text)
RETURNS text LANGUAGE sql STABLE AS $fn$
  SELECT base_url FROM public.ottoq_service_endpoints WHERE service_key = p_service_key;
$fn$;

COMMENT ON FUNCTION public.ottoq_service_endpoint(text) IS
  '0398. The base URL for a service, or NULL if unconfigured. NULL means "fall back to the '
  'environment", never "fail" -- see ottoq-cpsat-propose.';

-- And the assertion, because a row that points nowhere is the failure mode this whole migration is
-- about. It checks what SQL can check -- that the row exists and is shaped like a URL -- and says
-- plainly that reachability is not checkable from here.
CREATE OR REPLACE FUNCTION public.ottoq_assert_service_endpoints()
RETURNS TABLE(service_key text, base_url text, verdict text)
LANGUAGE sql STABLE AS $fn$
  SELECT 'intelligence'::text,
         COALESCE(public.ottoq_service_endpoint('intelligence'), '(absent)'),
         CASE
           WHEN public.ottoq_service_endpoint('intelligence') IS NULL
             THEN 'FAIL: no row, so ottoq-cpsat-propose falls back to OTTOQ_INTEL_URL -- which is '
                  'what G108 is about. Insert the address.'
           ELSE 'shape OK. Reachability is NOT asserted here and cannot be: the only honest '
                'witness is POST /assign lines in the service''s own access log, counted on the '
                'box over SSM by something that is not the caller making the claim.'
         END;
$fn$;

-- forces_recert FALSE. A table created by this migration cannot be read by any existing digest.
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0398_the_address_of_a_service_that_moves_belongs_in_data_g108',
        FALSE,
        '0398 creates public.ottoq_service_endpoints plus ottoq_service_endpoint(text) and '
        'ottoq_assert_service_endpoints(). Nothing hashed can reference a table that did not exist '
        'until this migration ran, so no fingerprint, frame payload or KPI view changes: '
        'ottoq_world_fingerprint, ottoq_frame_hash_payload and the fourteen atoms are untouched. '
        'Measured rather than argued -- the table is new, and a new table nothing reads cannot move '
        'a hash. It is also not run-scoped (no sim_run_id), so the purge neither deletes it nor '
        'needs a ottoq_run_scope_registry row for it.',
        now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert, note = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

COMMIT;
