-- lab/engine/sql/fidelity_objects.sql
-- One row per engine object in schemas public / ottoq / twin, with content
-- hashes. The SAME text runs on the lab and on production (read-only), so the
-- two sides can be compared bucket by bucket without moving any body or row.
-- Extension-owned objects (PostGIS, btree_gist, ...) are excluded on both sides.
-- Both sides must run with search_path "$user", public, extensions (production's
-- default, and the lab database's), because type names print relative to it.
--
--   kind       ident                          h1                         h2 (h3: routines only)
--   routine    name(identity args)            md5(prosrc)                md5(header: kind, language, volatility,
--                                                                          security definer, strict, set-returning,
--                                                                          parallel, leakproof, cost, rows, full
--                                                                          argument list with defaults, result, SET)
--                                                                        h3 = md5(prosrc with -- and /* */ comments
--                                                                          removed and whitespace runs collapsed):
--                                                                          tells "same code, other comments" apart
--   table      name  (relkind r, p)           md5(columns, attnum order) md5(columns, name order)
--   view       name  (relkind v, m)           md5(columns, attnum order) md5(pg_get_viewdef)
--   constraint table.conname                  md5(pg_get_constraintdef)
--   index      table.indexname                md5(pg_get_indexdef)
--   trigger    table.tgname (not internal)    md5(pg_get_triggerdef)
--   policy     table.policyname               md5(permissive|roles|cmd|qual|with_check)
--   rls        table (relkind r, p)           relrowsecurity|relforcerowsecurity
--   type       name (enum, composite, domain) md5(labels / attributes / base)
-- A column is "name:type:not null:default:identity:generated".
WITH o AS (
  SELECT 'routine'::text AS kind, n.nspname::text AS s,
         p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS ident,
         md5(p.prosrc) AS h1,
         md5(concat_ws('|', p.prokind, l.lanname, p.provolatile, p.prosecdef, p.proisstrict, p.proretset,
                       p.proparallel, p.proleakproof, p.procost, p.prorows, pg_get_function_arguments(p.oid),
                       pg_get_function_result(p.oid), array_to_string(p.proconfig, ','))) AS h2,
         md5(btrim(regexp_replace(regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', ' ', 'g'),
                                                 '--[^\n]*', ' ', 'g'), '\s+', ' ', 'g'))) AS h3
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_language l ON l.oid = p.prolang
   WHERE n.nspname IN ('public', 'ottoq', 'twin')
     AND NOT EXISTS (SELECT 1 FROM pg_depend d
                      WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e')
  UNION ALL
  SELECT CASE WHEN c.relkind IN ('r', 'p') THEN 'table' ELSE 'view' END, n.nspname::text, c.relname::text,
         md5(string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull || ':' ||
                        COALESCE(pg_get_expr(ad.adbin, ad.adrelid), '') || ':' || a.attidentity::text || ':' || a.attgenerated::text,
                        ',' ORDER BY a.attnum)),
         CASE WHEN c.relkind IN ('r', 'p')
              THEN md5(string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull || ':' ||
                                  COALESCE(pg_get_expr(ad.adbin, ad.adrelid), '') || ':' || a.attidentity::text || ':' || a.attgenerated::text,
                                  ',' ORDER BY a.attname COLLATE "C"))
              ELSE md5(pg_get_viewdef(c.oid)) END, ''
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
    LEFT JOIN pg_attrdef ad ON ad.adrelid = c.oid AND ad.adnum = a.attnum
   WHERE n.nspname IN ('public', 'ottoq', 'twin') AND c.relkind IN ('r', 'p', 'v', 'm')
     AND NOT EXISTS (SELECT 1 FROM pg_depend d
                      WHERE d.classid = 'pg_class'::regclass AND d.objid = c.oid AND d.deptype = 'e')
   GROUP BY c.oid, c.relkind, n.nspname, c.relname
  UNION ALL
  SELECT 'constraint', n.nspname::text, c.relname || '.' || k.conname, md5(pg_get_constraintdef(k.oid)), '', ''
    FROM pg_constraint k JOIN pg_class c ON c.oid = k.conrelid JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname IN ('public', 'ottoq', 'twin')
     AND NOT EXISTS (SELECT 1 FROM pg_depend d
                      WHERE d.classid = 'pg_class'::regclass AND d.objid = c.oid AND d.deptype = 'e')
  UNION ALL
  SELECT 'index', n.nspname::text, t.relname || '.' || i.relname, md5(pg_get_indexdef(x.indexrelid)), '', ''
    FROM pg_index x JOIN pg_class i ON i.oid = x.indexrelid JOIN pg_class t ON t.oid = x.indrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
   WHERE n.nspname IN ('public', 'ottoq', 'twin')
     AND NOT EXISTS (SELECT 1 FROM pg_depend d
                      WHERE d.classid = 'pg_class'::regclass AND d.objid = t.oid AND d.deptype = 'e')
  UNION ALL
  SELECT 'trigger', n.nspname::text, c.relname || '.' || g.tgname, md5(pg_get_triggerdef(g.oid)), '', ''
    FROM pg_trigger g JOIN pg_class c ON c.oid = g.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname IN ('public', 'ottoq', 'twin') AND NOT g.tgisinternal
  UNION ALL
  SELECT 'policy', schemaname::text, tablename || '.' || policyname,
         md5(concat_ws('|', permissive, roles::text, cmd, qual, with_check)), '', ''
    FROM pg_policies WHERE schemaname IN ('public', 'ottoq', 'twin')
  UNION ALL
  SELECT 'rls', n.nspname::text, c.relname::text, c.relrowsecurity || '|' || c.relforcerowsecurity, '', ''
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname IN ('public', 'ottoq', 'twin') AND c.relkind IN ('r', 'p')
     AND NOT EXISTS (SELECT 1 FROM pg_depend d
                      WHERE d.classid = 'pg_class'::regclass AND d.objid = c.oid AND d.deptype = 'e')
  UNION ALL
  SELECT 'type', n.nspname::text, t.typname::text,
         md5(CASE t.typtype
               WHEN 'e' THEN (SELECT string_agg(e.enumlabel, ',' ORDER BY e.enumsortorder) FROM pg_enum e WHERE e.enumtypid = t.oid)
               WHEN 'c' THEN (SELECT string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' ORDER BY a.attnum)
                                FROM pg_attribute a WHERE a.attrelid = t.typrelid AND a.attnum > 0 AND NOT a.attisdropped)
               ELSE format_type(t.typbasetype, t.typtypmod) END), '', ''
    FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
   WHERE n.nspname IN ('public', 'ottoq', 'twin')
     AND (t.typtype IN ('e', 'd') OR (t.typtype = 'c' AND EXISTS (SELECT 1 FROM pg_class c WHERE c.oid = t.typrelid AND c.relkind = 'c')))
     AND NOT EXISTS (SELECT 1 FROM pg_depend d
                      WHERE d.classid = 'pg_type'::regclass AND d.objid = t.oid AND d.deptype = 'e')
)
