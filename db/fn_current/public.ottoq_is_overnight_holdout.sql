-- CAPTURED LIVE from gxdrcyphqjzjsuhxuqtg via pg_get_functiondef, date not recorded
-- md5 at capture: 32a50b18b48fc97a0e02f232767b1337
--   (this pin was computed FROM THIS FILE on 2026-09-08 because the capture shipped without one.
--    It therefore proves only that the file has not been edited SINCE; it is not evidence
--    about the catalog. The live comparison on the next line is.)
-- STALE: this body is NOT what the catalog holds. Measured 2026-09-08:
--   live 0c0a02ddcab8a51ddc86cf0451224519
--   here 32a50b18b48fc97a0e02f232767b1337
--   Read it as a point-in-time record, never as 'what the engine does now'.
--   db/fn_current/README.md carries the whole drift table and how to refresh.
CREATE OR REPLACE FUNCTION public.ottoq_is_overnight_holdout(p_vehicle uuid, p_run uuid, p_clock timestamp with time zone, p_pct integer DEFAULT 1)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT (abs(hashtextextended(
     p_vehicle::text || ':' || p_run::text || ':' ||
     (((p_clock AT TIME ZONE 'America/Chicago') - interval '5 hours')::date)::text, 7)) % 100)
   < GREATEST(1, COALESCE(p_pct,1));
$function$
;
