-- STALE: this body is NOT what the catalog holds.
--   file body md5: 32a50b18b48fc97a0e02f232767b1337
--   live      md5: 0c0a02ddcab8a51ddc86cf0451224519
-- md5 at capture: 32a50b18b48fc97a0e02f232767b1337
-- re-measured 2026-09-09 14:15 UTC against gxdrcyphqjzjsuhxuqtg.
-- Read the catalog, not this file: SELECT pg_get_functiondef('public.ottoq_is_overnight_holdout'::regproc);
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
