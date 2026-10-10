-- 0430  **The v2 door is live: it keeps an operator's event time, takes each event once, applies each car's events in
--        the order its operator numbered them, answers only for its own fleet's cars, and signs what it sends with a
--        key it made itself.** Step 3 of the twin data contract review (2026-10-08), built 2026-10-09 between 7:54 and
--        8:09 PM CT by 0650, 0651, 0652 and the edge function ottoq-depot-v2 v1. Twin depot 11111111-…, the only
--        site. Every query below is read-only.
--
-- ══ §1 WHAT STEP 3 ASKED, AND WHERE EACH PART LIVES ══
--
--     the review asked                          where it lives                                   proof
--     a v2 door beside the old one              edge function ottoq-depot-v2 (verify_jwt off;     §2 probes; ottoq-ingest
--                                               the source key is the credential)                 v16 untouched
--     it accepts CloudEvents                    contract/schemas checked at the edge              §2 (e), (g)
--                                               (@cfworker/json-schema 4.1.1), then
--                                               public.ottoq_v2_take_events
--     it keeps event time                       a packet is timed by the event's own time         0650 V1; §2 (g) packet
--     it drops duplicates                       ottoq_v2_inbox UNIQUE (operator, source, id, run) §2 (g) second g430-1
--     it orders by sequence                     ottoq_v2_cursors, one per operator and car        §2 (g) g430-3, g430-2
--     ottoq_api_twin_apply_commands grows       public.ottoq_api_twin_apply_directives (0652);    0652 V1 on the live walk
--       a payload                               the walk runs only what it is handed
--     directives get an id, a version, an       ottoq.ottoq_v2_directive_event (0651): id =       0651 V1; §2 (b) the key
--       expiry and a signature                  command_id, version 1, expiry 2 ticks, ack 1
--                                               tick; Ed25519 detached JWS at the edge
--     the old door stays until nothing uses it  ottoq-ingest v16 and its tables, unchanged        _MANIFEST.md
--
-- ══ §2 PROBED FROM OUTSIDE, 2026-10-10 01:05-01:09 UTC (8:05-8:09 PM CT on 2026-10-09) ══
--
--   (a) GET /nowhere                                   404 no_route
--   (b) GET /jwks, first use                           200, one key: kid ottoq-depot-118daaffe483095d, OKP Ed25519, no d.
--                                                      The function made it, kept its private half in Vault (one
--                                                      vault.secrets row named ottoq_v2_signing_key:<kid>), and the kid
--                                                      is "ottoq-depot-" + the first 16 hex of SHA-256(x): query (1).
--                                                      Asked again later: the same one key, no second.
--   (c) POST /events with no key / a malformed key    401 no_key / 401 malformed_key
--   (d) GET /events                                    405 method
--   (e) POST /events as application/json               415 content_type (structured CloudEvents only)
--   (f) GET /directives with no key                    401 no_key
--   (g) a probe key: shadow data source, the twin depot, streams telemetry/arrival/incident, scoped to Waymo
--       Nashville. One batch of 10 with ?dry_run=true:
--         g430-1 telemetry Waymo-001 seq 1        applied: a packet, SoC fresh, location not sent
--         g430-1 again                             duplicate
--         g430-3 seq 3                             applied, gap_before 1
--         g430-2 seq 2                             late (last applied 3), not applied over it
--         g430-t Tesla-001 (another fleet)         refused vehicle_not_found: the key cannot learn the car exists
--         g430-o source naming another operator    refused source_is_not_this_key
--         g430-f fault summary Waymo-002           applied: one titled exception
--         g430-a arrival intent Waymo-002          applied: the return decision asked (no_live_run), marked en route
--         g430-d departed Waymo-002                applied: kept in the inbox only (wired in step 4)
--         g430-s telemetry with no time            refused at the edge, reason schema, "does not have required
--                                                  property time"
--       200, received 10, applied 5, late 1, duplicate 1, refused 3. Kept: nothing. After it the inbox and cursors
--       held 0 rows, no packet was written in the 15 minutes around it, the exception id did not exist, and the twin's
--       Waymo-002 was still offline: query (2).
--   (h) GET /directives with the shadow key            403 no_directives_for_shadow
--   (i) the probe key revoked at 01:08:32 UTC          then 401 unknown_or_revoked_key on POST /events and GET
--                                                      /directives: query (3).
--
-- ══ §3 NOT YET SEEN LIVE, AND WHY ══
--
--   (a) A signed directive over HTTP. The outbox gives a twin key only its depot's running run's directives, no run
--       was running, and the twin depot holds no production command. The signing is proven offline: tests/
--       depot_v2.test.mjs signs and verifies on the contract's examples, byte for byte as contract/ottoq_contract.py
--       does. The first live signed batch is step 4's first twin run.
--   (b) Once-only across two requests. The HTTP probe was a dry run on purpose: applying a shadow event writes to a
--       twin car outside any run. The same code path took a resent event as a duplicate inside 0650's V1 on the live
--       functions, and in tests/test_v2_door_sql.py.
--   (c) 0652 on a running run. Its V1 ran the live walk on run c9558b2a (completed), rolled back.
--
-- ══ §4 FOUND WHILE BUILDING ══
--
--   (a) G395. The old door's incident stream cannot write. ottoq-ingest inserts exceptions rows with no title, and
--       exceptions.title is NOT NULL with no default (so is vehicle_id, which the old door sends as null when the
--       event names no car). Any incident sent to it fails; the table holds 5 rows, all the twin's, none from it. The v2
--       door writes a title. Query (4).
--   (b) G396. ottoq_ack_vehicle_command's audit event never records. It calls ottoq_record_event with actor_type
--       'vehicle', which ottoq_events' CHECK does not allow ('av_vehicle' is the allowed name), inside EXCEPTION WHEN
--       OTHERS THEN NULL: the ack lands and its event is dropped silently. 0 vehicle.command_ack events, against 6,842
--       commands carrying a confirmer other than the pre-flight check. It also stamps data_source 'production' on
--       every ack, twin commands included. The v2 door records acks as directive.ack with actor oem_dispatch_webhook
--       and the key's own data source. Query (5).
--   (c) A shadow key is taken like production (wall clock, applied to the car's state) and is sent no directives:
--       OTTO-Q decides in shadow and commands nothing. contract/README.md now says so.
--   (d) display_name is not unique across depots: the twin depot and the benchmark depot each have a Waymo-002. The
--       door resolves a reference only among the key's fleets at the key's depot, so the probe touched only the twin's;
--       a car homed at one depot and parked at another would read as vehicle_ref_ambiguous, never as the wrong car.
--
-- ══ REPRODUCE ══

-- (1) the depot's signing key: one active, its kid from its own public half, its private half in Vault
SELECT k.kid, k.public_jwk ->> 'x' AS x, k.created_at, k.retired_at,
       k.kid = 'ottoq-depot-' || left(encode(extensions.digest(k.public_jwk ->> 'x', 'sha256'), 'hex'), 16) AS kid_from_x,
       EXISTS (SELECT 1 FROM vault.secrets s WHERE s.id = k.vault_secret_id AND s.name = 'ottoq_v2_signing_key:' || k.kid) AS in_vault,
       NOT (k.public_jwk ? 'd') AS public_half_only
  FROM public.ottoq_v2_signing_keys k
 ORDER BY k.created_at;

-- (2) the dry run kept nothing (read soon after the probe; later twin runs will fill the inbox in step 4)
SELECT (SELECT count(*) FROM public.ottoq_v2_inbox  WHERE source_name = 'g430_door_probe') AS probe_inbox_rows,
       (SELECT count(*) FROM public.ottoq_v2_cursors WHERE source_name = 'g430_door_probe') AS probe_cursor_rows,
       (SELECT count(*) FROM public.exceptions WHERE id = '5834ab70-12cf-4367-9195-0815469e5833') AS probe_exception,
       (SELECT count(*) FROM public.ottoq_telemetry_packets
         WHERE packet_at BETWEEN '2026-10-10 01:00:00+00' AND '2026-10-10 01:15:00+00') AS packets_around_probe;

-- (3) the probe key: shadow, the twin depot, one fleet, revoked
SELECT id, source_name, data_source, depot_id, streams, fleet_operator_ids, is_active, revoked_at, revoke_reason
  FROM public.ottow_api_keys WHERE source_name = 'g430_door_probe';

-- (4) G395: what an exceptions row must carry, and who wrote the rows there are
SELECT column_name, is_nullable, column_default
  FROM information_schema.columns
 WHERE table_schema = 'public' AND table_name = 'exceptions' AND is_nullable = 'NO' AND column_default IS NULL;
SELECT data_source, count(*) FROM public.exceptions GROUP BY 1;

-- (5) G396: the ack's event, the CHECK it meets, and how many it ever wrote
SELECT position('p_actor_type := ''vehicle''' IN prosrc) > 0 AS passes_vehicle,
       position('EXCEPTION WHEN OTHERS THEN NULL' IN prosrc) > 0 AS swallows_the_failure
  FROM pg_proc WHERE proname = 'ottoq_ack_vehicle_command';
SELECT pg_get_constraintdef(c.oid) LIKE '%''vehicle''::text%' AS vehicle_allowed,
       pg_get_constraintdef(c.oid) LIKE '%''av_vehicle''::text%' AS av_vehicle_allowed
  FROM pg_constraint c WHERE c.conrelid = 'public.ottoq_events'::regclass AND pg_get_constraintdef(c.oid) LIKE '%actor_type%';
SELECT (SELECT count(*) FROM public.ottoq_events WHERE event_type = 'vehicle.command_ack') AS command_ack_events,
       (SELECT count(*) FROM public.ottoq_vehicle_commands
         WHERE confirmed_by IS NOT NULL AND confirmed_by <> 'otto_q_preflight'
           AND status IN ('confirmed', 'refused', 'executed')) AS commands_with_a_confirmer;

-- (6) the three migrations as the ledger holds them, and the walk 0652 patched
SELECT version, name, md5(array_to_string(statements, '')) AS stored_md5
  FROM supabase_migrations.schema_migrations
 WHERE version IN ('20261010005456', '20261010005934', '20261010010118') ORDER BY version;
SELECT md5(pg_get_functiondef('twin.ottoq_sim_confirm_commands(uuid,timestamptz)'::regprocedure)) AS walk_md5;  -- fba6dd47836c81eead40a63846e7f282

-- (7) the HTTP probes, from any shell (no key needed for these):
--   B=https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-depot-v2
--   curl -sS -w '\n%{http_code}\n' $B/jwks                                   # 200, the one key of (1)
--   curl -sS -w '\n%{http_code}\n' -X POST -H 'Content-Type: application/cloudevents+json' --data '{}' $B/events  # 401 no_key
--   curl -sS -w '\n%{http_code}\n' $B/events                                 # 405
--   A keyed probe needs a key from public.ottoq_issue_source_key and public.ottoq_scope_source_key (service role),
--   revoked with public.ottoq_revoke_source_key when done.
