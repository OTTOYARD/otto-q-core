-- call closure of the demo-run start and the two cron tick entry points, in the lab copy
WITH RECURSIVE fn AS (
  SELECT p.oid, n.nspname AS s, p.proname AS name, p.prosrc
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','ottoq','twin')
     AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e')
), names AS (SELECT DISTINCT name FROM fn),
seed AS (SELECT oid FROM fn WHERE (s, name) IN (('public','ottoq_start_demo_run'),('public','ottoq_cron_tick'),('public','ottoq_demo_metronome'))),
clo(oid) AS (
  SELECT oid FROM seed
  UNION
  SELECT f2.oid FROM clo JOIN fn f1 ON f1.oid = clo.oid
    JOIN fn f2 ON f1.prosrc ~ ('\m' || f2.name || '\s*\(')
)
SELECT 'fn' AS k, count(*)::text FROM (SELECT DISTINCT oid FROM clo) x
UNION ALL
SELECT 'tbl', string_agg(DISTINCT c.relnamespace::regnamespace::text || '.' || c.relname, ',' ORDER BY c.relnamespace::regnamespace::text || '.' || c.relname)
  FROM (SELECT DISTINCT oid FROM clo) x JOIN fn ON fn.oid = x.oid
  JOIN pg_class c ON c.relkind IN ('r','p','v') AND c.relnamespace::regnamespace::text IN ('public','twin')
   AND fn.prosrc ~ ('\m' || c.relname || '\M');
