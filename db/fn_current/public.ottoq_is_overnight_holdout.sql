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
