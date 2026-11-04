-- lab/engine/sql/fidelity_extra.sql
-- What sql/fidelity_objects.sql does not compare, in the same shape (kind, s, ident, h1, h2, h3),
-- run identically on the lab and on production (read-only). Same search_path rule as that file.
--
--   kind         ident                           h1                                h2
--   acl          TABLE|SEQUENCE|FUNCTION|...     the ACL as text (aclitem[]::text)  owner
--                name (columns: table.column)
--   comment      the COMMENT ON target           md5(description)
--   sequence     name                            type|start|inc|min|max|cache|cycle  owned by (table.column, or '')
--   default_acl  role schema objtype             the default ACL as text
--   cron_job     jobid                           md5(schedule|command|jobname|username|database)   (active is not
--                                                                                    compared: the lab keeps every job off)
--   ledger       versions                        md5 of the versions joined by ',' (= ottoq_engine_hash())   row count
SELECT 'acl'::text AS kind, n.nspname::text AS s,
       CASE c.relkind WHEN 'S' THEN 'SEQUENCE ' ELSE 'TABLE ' END || c.relname AS ident,
       COALESCE(c.relacl::text, '') AS h1, pg_get_userbyid(c.relowner)::text AS h2, ''::text AS h3
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname IN ('public', 'ottoq', 'twin') AND c.relkind IN ('r', 'v', 'S')
   AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_class'::regclass AND d.objid = c.oid AND d.deptype = 'e')
UNION ALL
SELECT 'acl', n.nspname, 'COLUMN ' || c.relname || '.' || a.attname, a.attacl::text, '', ''
  FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname IN ('public', 'ottoq', 'twin') AND a.attnum > 0 AND NOT a.attisdropped AND a.attacl IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_class'::regclass AND d.objid = c.oid AND d.deptype = 'e')
UNION ALL
SELECT 'acl', n.nspname, 'FUNCTION ' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
       COALESCE(p.proacl::text, ''), pg_get_userbyid(p.proowner)::text, ''
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public', 'ottoq', 'twin')
   AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e')
UNION ALL
SELECT 'acl', n.nspname, 'SCHEMA ' || n.nspname, COALESCE(n.nspacl::text, ''), pg_get_userbyid(n.nspowner)::text, ''
  FROM pg_namespace n WHERE n.nspname IN ('public', 'ottoq', 'twin')
UNION ALL
SELECT 'acl', n.nspname, 'TYPE ' || t.typname, COALESCE(t.typacl::text, ''), pg_get_userbyid(t.typowner)::text, ''
  FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
 WHERE n.nspname IN ('public', 'ottoq', 'twin')
   AND (t.typtype = 'e' OR (t.typtype = 'c' AND EXISTS (SELECT 1 FROM pg_class c WHERE c.oid = t.typrelid AND c.relkind = 'c')))
   AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_type'::regclass AND d.objid = t.oid AND d.deptype = 'e')
UNION ALL
SELECT 'comment', n.nspname,
       CASE c.relkind WHEN 'r' THEN 'TABLE ' WHEN 'v' THEN 'VIEW ' WHEN 'S' THEN 'SEQUENCE ' WHEN 'i' THEN 'INDEX ' ELSE 'REL ' END
         || c.relname || CASE WHEN d.objsubid > 0 THEN '.' || a.attname ELSE '' END,
       md5(d.description), '', ''
  FROM pg_description d JOIN pg_class c ON d.classoid = 'pg_class'::regclass AND d.objoid = c.oid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  LEFT JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = d.objsubid AND d.objsubid > 0
 WHERE n.nspname IN ('public', 'ottoq', 'twin')
   AND NOT EXISTS (SELECT 1 FROM pg_depend x WHERE x.classid = 'pg_class'::regclass AND x.objid = c.oid AND x.deptype = 'e')
UNION ALL
SELECT 'comment', n.nspname, 'FUNCTION ' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')', md5(d.description), '', ''
  FROM pg_description d JOIN pg_proc p ON d.classoid = 'pg_proc'::regclass AND d.objoid = p.oid
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public', 'ottoq', 'twin')
   AND NOT EXISTS (SELECT 1 FROM pg_depend x WHERE x.classid = 'pg_proc'::regclass AND x.objid = p.oid AND x.deptype = 'e')
UNION ALL
SELECT 'comment', n.nspname, 'TYPE ' || t.typname, md5(d.description), '', ''
  FROM pg_description d JOIN pg_type t ON d.classoid = 'pg_type'::regclass AND d.objoid = t.oid
  JOIN pg_namespace n ON n.oid = t.typnamespace
 WHERE n.nspname IN ('public', 'ottoq', 'twin')
   AND NOT EXISTS (SELECT 1 FROM pg_depend x WHERE x.classid = 'pg_type'::regclass AND x.objid = t.oid AND x.deptype = 'e')
UNION ALL
SELECT 'comment', n.nspname, 'CONSTRAINT ' || c.relname || '.' || k.conname, md5(d.description), '', ''
  FROM pg_description d JOIN pg_constraint k ON d.classoid = 'pg_constraint'::regclass AND d.objoid = k.oid
  JOIN pg_class c ON c.oid = k.conrelid JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname IN ('public', 'ottoq', 'twin')
UNION ALL
SELECT 'comment', n.nspname, 'TRIGGER ' || c.relname || '.' || g.tgname, md5(d.description), '', ''
  FROM pg_description d JOIN pg_trigger g ON d.classoid = 'pg_trigger'::regclass AND d.objoid = g.oid
  JOIN pg_class c ON c.oid = g.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname IN ('public', 'ottoq', 'twin')
UNION ALL
SELECT 'comment', n.nspname, 'POLICY ' || c.relname || '.' || po.polname, md5(d.description), '', ''
  FROM pg_description d JOIN pg_policy po ON d.classoid = 'pg_policy'::regclass AND d.objoid = po.oid
  JOIN pg_class c ON c.oid = po.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname IN ('public', 'ottoq', 'twin')
UNION ALL
SELECT 'comment', n.nspname, 'SCHEMA ' || n.nspname, md5(d.description), '', ''
  FROM pg_description d JOIN pg_namespace n ON d.classoid = 'pg_namespace'::regclass AND d.objoid = n.oid
 WHERE n.nspname IN ('public', 'ottoq', 'twin')
UNION ALL
SELECT 'sequence', n.nspname, c.relname,
       concat_ws('|', format_type(q.seqtypid, NULL), q.seqstart, q.seqincrement, q.seqmin, q.seqmax, q.seqcache, q.seqcycle, c.relpersistence),
       COALESCE((SELECT tc.relname || '.' || a.attname || ':' || d.deptype::text
                   FROM pg_depend d JOIN pg_class tc ON tc.oid = d.refobjid
                   JOIN pg_attribute a ON a.attrelid = d.refobjid AND a.attnum = d.refobjsubid
                  WHERE d.classid = 'pg_class'::regclass AND d.objid = c.oid AND d.refclassid = 'pg_class'::regclass
                    AND d.deptype IN ('a', 'i')), ''), ''
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace JOIN pg_sequence q ON q.seqrelid = c.oid
 WHERE n.nspname IN ('public', 'ottoq', 'twin') AND c.relkind = 'S'
   AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_class'::regclass AND d.objid = c.oid AND d.deptype = 'e')
UNION ALL
SELECT 'default_acl', COALESCE(n.nspname, ''), pg_get_userbyid(d.defaclrole) || ' ' || COALESCE(n.nspname, '-') || ' ' || d.defaclobjtype::text,
       d.defaclacl::text, '', ''
  FROM pg_default_acl d LEFT JOIN pg_namespace n ON n.oid = d.defaclnamespace
 WHERE n.nspname IN ('public', 'storage', 'extensions', 'cron', 'auth')
UNION ALL
SELECT 'cron_job', 'cron', j.jobid::text,
       md5(concat_ws('|', j.schedule, j.command, j.jobname, j.username, j.database)), '', ''
  FROM cron.job j
UNION ALL
SELECT 'ledger', 'supabase_migrations', 'versions',
       (SELECT md5(string_agg(m.version, ',' ORDER BY m.version)) FROM supabase_migrations.schema_migrations m),
       (SELECT count(*)::text FROM supabase_migrations.schema_migrations), ''
