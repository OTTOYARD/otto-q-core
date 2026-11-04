#!/usr/bin/env python3
"""Export production's engine schema AS IT RAN, from its catalog, into SQL files the lab loads.

The repository cannot rebuild the engine (G509): its migration files are not the SQL that ran.
This reads production's catalog instead and writes the DDL that recreates every object of
schemas public, ottoq and twin -- the work `pg_dump --schema-only` does, which is not
available here because production's Postgres port is unreachable from the session
(docs/FRONTIER_PLAN_2026-11-03.md, D2). Every read goes through lib/prod_read.py, i.e. the
Management API's read-only endpoint, as supabase_read_only_user in a read-only transaction.

Definitions come from production's own deparsers (pg_get_functiondef, pg_get_viewdef,
pg_get_constraintdef, pg_get_indexdef, pg_get_triggerdef, pg_get_ruledef, pg_get_expr,
format_type), each run with search_path = '' so every name comes out schema-qualified, as
pg_dump does. Extension-owned objects (PostGIS's in public) are left to the extension.

Output, one file per load phase; every statement is preceded by a marker line
    -- @@ <kind> <identity>
so the loader never has to split SQL (function bodies hold semicolons). The exporter refuses to
write a statement that contains the marker, a JWT, or a token-shaped string.

    python -I lab/engine/lib/export_prod.py --out lab/engine/export/2026-11-04
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prod_read  # noqa: E402

SCHEMAS = ("public", "ottoq", "twin")
SCH = "('public','ottoq','twin')"
MARK = "-- @@ "
PREAMBLE = "select pg_catalog.set_config('search_path', '', true); "

# A statement that matches any of these is not written: production's code reads its secrets
# from vault at run time, and an export that ever carries one must stop, not commit it.
SECRET_PATTERNS = [
    re.compile(r"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"),  # a JWT
    re.compile(r"\bsbp_[A-Za-z0-9]{20,}"),  # a Supabase access token
    re.compile(r"\bsk-(ant-)?[A-Za-z0-9_-]{20,}"),  # an API secret key
    re.compile(r"\bnvapi-[A-Za-z0-9_-]{20,}"),  # an NVIDIA API key
]


def not_ext(classid: str, alias: str) -> str:
    return (f"not exists (select 1 from pg_catalog.pg_depend d where d.classid = '{classid}'::pg_catalog.regclass "
            f"and d.objid = {alias}.oid and d.deptype = 'e')")


def read(sql: str) -> tuple[str, list[dict]]:
    """Run `sql` (a SELECT whose rows are wanted) and return (read_at, rows)."""
    wrapped = (PREAMBLE + "select pg_catalog.json_build_object('read_at', pg_catalog.now(), "
               "'rows', coalesce(pg_catalog.json_agg(q), '[]'::pg_catalog.json)) as r from (" + sql + ") q")
    out = prod_read.query(wrapped)
    r = out[0]["r"]
    if isinstance(r, str):
        r = json.loads(r)
    return r["read_at"], r["rows"]


# --------------------------------------------------------------------------- catalog queries

Q_META = f"""
select pg_catalog.version() as version,
       pg_catalog.current_setting('server_version_num') as server_version_num,
       (select pg_catalog.json_object_agg(e.extname, pg_catalog.json_build_object('version', e.extversion,
               'schema', n.nspname)) from pg_catalog.pg_extension e join pg_catalog.pg_namespace n on n.oid = e.extnamespace) as extensions,
       (select pg_catalog.count(*) from supabase_migrations.schema_migrations) as ledger_rows,
       (select pg_catalog.max(version) from supabase_migrations.schema_migrations) as ledger_max_version,
       -- public.ottoq_engine_hash()'s own expression (that function is not executable by the read-only role)
       (select pg_catalog.md5(pg_catalog.string_agg(m.version, ',' order by m.version))
          from supabase_migrations.schema_migrations m) as engine_hash,
       (select d.datcollate || ' / ' || d.datctype || ' / ' || coalesce(d.datlocprovider::text, '') || ' / ' ||
               coalesce(d.datlocale, '') || ' / ' || coalesce(d.datcollversion, '')
          from pg_catalog.pg_database d where d.datname = pg_catalog.current_database()) as database_locale
"""

Q_SCHEMAS = f"""
select n.nspname as name, pg_catalog.quote_ident(n.nspname) as qn, pg_catalog.pg_get_userbyid(n.nspowner) as owner
  from pg_catalog.pg_namespace n where n.nspname in {SCH} order by n.nspname
"""

Q_ENUMS = f"""
select t.oid::bigint as oid, pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(t.typname) as qn,
       pg_catalog.pg_get_userbyid(t.typowner) as owner,
       (select pg_catalog.string_agg(pg_catalog.quote_literal(e.enumlabel), ', ' order by e.enumsortorder)
          from pg_catalog.pg_enum e where e.enumtypid = t.oid) as labels
  from pg_catalog.pg_type t join pg_catalog.pg_namespace n on n.oid = t.typnamespace
 where t.typtype = 'e' and n.nspname in {SCH} and {not_ext('pg_catalog.pg_type', 't')}
 order by 2
"""

Q_COMPOSITES = f"""
select t.oid::bigint as oid, pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(t.typname) as qn,
       pg_catalog.pg_get_userbyid(t.typowner) as owner,
       (select pg_catalog.string_agg(pg_catalog.quote_ident(a.attname) || ' ' || pg_catalog.format_type(a.atttypid, a.atttypmod)
                 || case when a.attcollation <> 0 and a.attcollation <> ty.typcollation
                         then ' COLLATE ' || pg_catalog.quote_ident(cn.nspname) || '.' || pg_catalog.quote_ident(co.collname) else '' end,
                 ', ' order by a.attnum)
          from pg_catalog.pg_attribute a
          join pg_catalog.pg_type ty on ty.oid = a.atttypid
          left join pg_catalog.pg_collation co on co.oid = a.attcollation
          left join pg_catalog.pg_namespace cn on cn.oid = co.collnamespace
         where a.attrelid = t.typrelid and a.attnum > 0 and not a.attisdropped) as cols
  from pg_catalog.pg_type t join pg_catalog.pg_namespace n on n.oid = t.typnamespace
  join pg_catalog.pg_class c on c.oid = t.typrelid
 where t.typtype = 'c' and c.relkind = 'c' and n.nspname in {SCH} and {not_ext('pg_catalog.pg_type', 't')}
 order by 2
"""

Q_UNSUPPORTED = f"""
select 'domain' as kind, pg_catalog.count(*) as n from pg_catalog.pg_type t join pg_catalog.pg_namespace n on n.oid = t.typnamespace
 where t.typtype in ('d', 'r', 'm') and n.nspname in {SCH} and {not_ext('pg_catalog.pg_type', 't')}
union all
select 'relkind ' || c.relkind::text, pg_catalog.count(*) from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace
 where c.relkind in ('p', 'm', 'f') and n.nspname in {SCH} and {not_ext('pg_catalog.pg_class', 'c')} group by c.relkind
union all
select 'typed or inherited table', pg_catalog.count(*) from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace
 where c.relkind = 'r' and n.nspname in {SCH} and (c.reloftype <> 0 or c.relispartition
       or exists (select 1 from pg_catalog.pg_inherits i where i.inhrelid = c.oid or i.inhparent = c.oid))
union all
select 'aggregate or window', pg_catalog.count(*) from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
 where p.prokind in ('a', 'w') and n.nspname in {SCH} and {not_ext('pg_catalog.pg_proc', 'p')}
union all
select 'sql-standard body', pg_catalog.count(*) from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
 where p.prosqlbody is not null and n.nspname in {SCH}
union all
select 'operator', pg_catalog.count(*) from pg_catalog.pg_operator o join pg_catalog.pg_namespace n on n.oid = o.oprnamespace
 where n.nspname in {SCH} and {not_ext('pg_catalog.pg_operator', 'o')}
union all
select 'extended statistics', pg_catalog.count(*) from pg_catalog.pg_statistic_ext s join pg_catalog.pg_namespace n on n.oid = s.stxnamespace
 where n.nspname in {SCH}
union all
select 'view column default', pg_catalog.count(*) from pg_catalog.pg_attrdef ad join pg_catalog.pg_class c on c.oid = ad.adrelid
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace where c.relkind = 'v' and n.nspname in {SCH}
"""

Q_SEQUENCES = f"""
select c.oid::bigint as oid, pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(c.relname) as qn,
       pg_catalog.pg_get_userbyid(c.relowner) as owner, c.relpersistence::text as persistence,
       pg_catalog.format_type(s.seqtypid, null) as typ, s.seqstart::text as start, s.seqincrement::text as inc,
       s.seqmin::text as min, s.seqmax::text as max, s.seqcache::text as cache, s.seqcycle as cycle,
       (select pg_catalog.quote_ident(tn.nspname) || '.' || pg_catalog.quote_ident(tc.relname) || '.' || pg_catalog.quote_ident(a.attname)
          from pg_catalog.pg_depend d join pg_catalog.pg_class tc on tc.oid = d.refobjid
          join pg_catalog.pg_namespace tn on tn.oid = tc.relnamespace
          join pg_catalog.pg_attribute a on a.attrelid = d.refobjid and a.attnum = d.refobjsubid
         where d.classid = 'pg_catalog.pg_class'::pg_catalog.regclass and d.objid = c.oid
           and d.refclassid = 'pg_catalog.pg_class'::pg_catalog.regclass and d.deptype = 'a') as owned_by,
       exists (select 1 from pg_catalog.pg_depend d where d.classid = 'pg_catalog.pg_class'::pg_catalog.regclass
                  and d.objid = c.oid and d.deptype = 'i') as is_identity,
       case when pg_catalog.has_sequence_privilege(c.oid, 'SELECT,USAGE')
            then pg_catalog.pg_sequence_last_value(c.oid)::text end as last_value
  from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  join pg_catalog.pg_sequence s on s.seqrelid = c.oid
 where c.relkind = 'S' and n.nspname in {SCH} and {not_ext('pg_catalog.pg_class', 'c')}
 order by 2
"""

Q_TABLES = f"""
select c.oid::bigint as oid, n.nspname as schema, c.relname as name,
       pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(c.relname) as qn,
       pg_catalog.pg_get_userbyid(c.relowner) as owner, c.relpersistence::text as persistence,
       c.reloptions as reloptions, c.relrowsecurity as rls, c.relforcerowsecurity as force_rls,
       c.relreplident::text as replident,
       (select pg_catalog.json_agg(pg_catalog.json_build_object(
                 'name', a.attname, 'qname', pg_catalog.quote_ident(a.attname),
                 'type', pg_catalog.format_type(a.atttypid, a.atttypmod),
                 'notnull', a.attnotnull, 'identity', a.attidentity::text, 'generated', a.attgenerated::text,
                 'default', pg_catalog.pg_get_expr(ad.adbin, ad.adrelid),
                 'collate', case when a.attcollation <> 0 and a.attcollation <> ty.typcollation
                                 then pg_catalog.quote_ident(cn.nspname) || '.' || pg_catalog.quote_ident(co.collname) end,
                 'storage', case when a.attstorage <> ty.typstorage then a.attstorage::text end,
                 'compression', nullif(a.attcompression::text, ''),
                 'stattarget', a.attstattarget,
                 'options', a.attoptions,
                 'identity_seq', case when a.attidentity <> '' then pg_catalog.pg_get_serial_sequence(
                                   pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(c.relname), a.attname) end)
                 order by a.attnum)
          from pg_catalog.pg_attribute a
          join pg_catalog.pg_type ty on ty.oid = a.atttypid
          left join pg_catalog.pg_attrdef ad on ad.adrelid = a.attrelid and ad.adnum = a.attnum
          left join pg_catalog.pg_collation co on co.oid = a.attcollation
          left join pg_catalog.pg_namespace cn on cn.oid = co.collnamespace
         where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped) as cols
  from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace
 where c.relkind = 'r' and n.nspname in {SCH} and {not_ext('pg_catalog.pg_class', 'c')}
 order by 4
"""

Q_IDENTITY_SEQS = f"""
select pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(c.relname) as qn,
       s.seqstart::text as start, s.seqincrement::text as inc, s.seqmin::text as min, s.seqmax::text as max,
       s.seqcache::text as cache, s.seqcycle as cycle,
       case when pg_catalog.has_sequence_privilege(c.oid, 'SELECT,USAGE')
            then pg_catalog.pg_sequence_last_value(c.oid)::text end as last_value
  from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  join pg_catalog.pg_sequence s on s.seqrelid = c.oid
 where c.relkind = 'S' and n.nspname in {SCH}
   and exists (select 1 from pg_catalog.pg_depend d where d.classid = 'pg_catalog.pg_class'::pg_catalog.regclass
                  and d.objid = c.oid and d.deptype = 'i')
"""


def q_functions(lo: int, hi: int) -> str:
    return f"""
select p.oid::bigint as oid, n.nspname as schema, p.proname as name, p.prokind::text as kind,
       pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(p.proname) as qn,
       pg_catalog.pg_get_function_identity_arguments(p.oid) as identity_args,
       pg_catalog.pg_get_userbyid(p.proowner) as owner,
       pg_catalog.pg_get_functiondef(p.oid) as def,
       pg_catalog.md5(p.prosrc) as prosrc_md5
  from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
 where n.nspname in {SCH} and {not_ext('pg_catalog.pg_proc', 'p')}
   and p.prokind in ('f', 'p') and p.oid >= {lo} and p.oid < {hi}
 order by p.oid
"""


Q_FUNCTION_OIDS = f"""
select p.oid::bigint as oid from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
 where n.nspname in {SCH} and {not_ext('pg_catalog.pg_proc', 'p')} and p.prokind in ('f', 'p') order by 1
"""

Q_VIEWS = f"""
select c.oid::bigint as oid, pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(c.relname) as qn,
       pg_catalog.pg_get_userbyid(c.relowner) as owner, c.reloptions as reloptions,
       pg_catalog.pg_get_viewdef(c.oid) as def
  from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace
 where c.relkind = 'v' and n.nspname in {SCH} and {not_ext('pg_catalog.pg_class', 'c')}
 order by 2
"""

Q_CONSTRAINTS = f"""
select co.oid::bigint as oid, co.contype::text as type, pg_catalog.quote_ident(co.conname) as qname,
       pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(c.relname) as qtable,
       pg_catalog.pg_get_constraintdef(co.oid) as def
  from pg_catalog.pg_constraint co
  join pg_catalog.pg_class c on c.oid = co.conrelid
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
 where n.nspname in {SCH} and co.contype in ('p', 'u', 'x', 'c', 'f') and {not_ext('pg_catalog.pg_class', 'c')}
   and co.conislocal
 order by 4, 3
"""

Q_INDEXES = f"""
select i.indexrelid::bigint as oid, pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(ic.relname) as qn,
       pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(c.relname) as qtable,
       pg_catalog.pg_get_indexdef(i.indexrelid) as def, i.indisclustered as clustered, i.indisreplident as replident,
       exists (select 1 from pg_catalog.pg_constraint co where co.conindid = i.indexrelid and co.conrelid = i.indrelid
                  and co.contype in ('p', 'u', 'x')) as by_constraint
  from pg_catalog.pg_index i
  join pg_catalog.pg_class ic on ic.oid = i.indexrelid
  join pg_catalog.pg_class c on c.oid = i.indrelid
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
 where n.nspname in {SCH} and {not_ext('pg_catalog.pg_class', 'c')}
 order by 2
"""

Q_TRIGGERS = f"""
select t.oid::bigint as oid, pg_catalog.quote_ident(t.tgname) as qname,
       pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(c.relname) as qtable,
       pg_catalog.pg_get_triggerdef(t.oid) as def, t.tgenabled::text as enabled
  from pg_catalog.pg_trigger t
  join pg_catalog.pg_class c on c.oid = t.tgrelid
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
 where not t.tgisinternal and n.nspname in {SCH} and {not_ext('pg_catalog.pg_class', 'c')}
 order by 3, 2
"""

Q_RULES = f"""
select r.oid::bigint as oid, pg_catalog.quote_ident(r.rulename) as qname,
       pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(c.relname) as qtable,
       pg_catalog.pg_get_ruledef(r.oid) as def, r.ev_enabled::text as enabled
  from pg_catalog.pg_rewrite r
  join pg_catalog.pg_class c on c.oid = r.ev_class
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
 where r.rulename <> '_RETURN' and n.nspname in {SCH} and {not_ext('pg_catalog.pg_class', 'c')}
 order by 3, 2
"""

Q_POLICIES = f"""
select po.oid::bigint as oid, pg_catalog.quote_ident(po.polname) as qname,
       pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(c.relname) as qtable,
       po.polpermissive as permissive, po.polcmd::text as cmd,
       case when po.polroles = '{{0}}'::pg_catalog.oid[] then 'PUBLIC'
            else (select pg_catalog.string_agg(case when r = 0 then 'PUBLIC' else pg_catalog.quote_ident(pg_catalog.pg_get_userbyid(r)) end, ', ' order by ord)
                    from pg_catalog.unnest(po.polroles) with ordinality u(r, ord)) end as roles,
       pg_catalog.pg_get_expr(po.polqual, po.polrelid) as qual,
       pg_catalog.pg_get_expr(po.polwithcheck, po.polrelid) as withcheck
  from pg_catalog.pg_policy po
  join pg_catalog.pg_class c on c.oid = po.polrelid
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
 where n.nspname in {SCH}
 order by 3, 2
"""

Q_COMMENTS = f"""
with d as (select * from pg_catalog.pg_description)
select 'SCHEMA ' || pg_catalog.quote_ident(n.nspname) as target, d.description as text
  from d join pg_catalog.pg_namespace n on d.classoid = 'pg_catalog.pg_namespace'::pg_catalog.regclass and d.objoid = n.oid
 where n.nspname in {SCH}
union all
select case c.relkind when 'r' then 'TABLE ' when 'v' then 'VIEW ' when 'S' then 'SEQUENCE ' when 'i' then 'INDEX '
                      else 'TABLE ' end
       || pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(c.relname), d.description
  from d join pg_catalog.pg_class c on d.classoid = 'pg_catalog.pg_class'::pg_catalog.regclass and d.objoid = c.oid and d.objsubid = 0
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
 where n.nspname in {SCH} and c.relkind in ('r', 'v', 'S', 'i') and {not_ext('pg_catalog.pg_class', 'c')}
union all
select 'COLUMN ' || pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(c.relname) || '.' || pg_catalog.quote_ident(a.attname),
       d.description
  from d join pg_catalog.pg_class c on d.classoid = 'pg_catalog.pg_class'::pg_catalog.regclass and d.objoid = c.oid and d.objsubid > 0
  join pg_catalog.pg_attribute a on a.attrelid = c.oid and a.attnum = d.objsubid
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
 where n.nspname in {SCH} and {not_ext('pg_catalog.pg_class', 'c')}
union all
select case p.prokind when 'p' then 'PROCEDURE ' else 'FUNCTION ' end
       || pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(p.proname)
       || '(' || pg_catalog.pg_get_function_identity_arguments(p.oid) || ')', d.description
  from d join pg_catalog.pg_proc p on d.classoid = 'pg_catalog.pg_proc'::pg_catalog.regclass and d.objoid = p.oid
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
 where n.nspname in {SCH} and {not_ext('pg_catalog.pg_proc', 'p')}
union all
select 'TYPE ' || pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(t.typname), d.description
  from d join pg_catalog.pg_type t on d.classoid = 'pg_catalog.pg_type'::pg_catalog.regclass and d.objoid = t.oid
  join pg_catalog.pg_namespace n on n.oid = t.typnamespace
 where n.nspname in {SCH} and {not_ext('pg_catalog.pg_type', 't')}
   and (t.typtype = 'e' or (t.typtype = 'c' and (select c2.relkind from pg_catalog.pg_class c2 where c2.oid = t.typrelid) = 'c'))
union all
select 'CONSTRAINT ' || pg_catalog.quote_ident(co.conname) || ' ON ' || pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(c.relname),
       d.description
  from d join pg_catalog.pg_constraint co on d.classoid = 'pg_catalog.pg_constraint'::pg_catalog.regclass and d.objoid = co.oid
  join pg_catalog.pg_class c on c.oid = co.conrelid join pg_catalog.pg_namespace n on n.oid = c.relnamespace
 where n.nspname in {SCH}
union all
select 'TRIGGER ' || pg_catalog.quote_ident(t.tgname) || ' ON ' || pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(c.relname),
       d.description
  from d join pg_catalog.pg_trigger t on d.classoid = 'pg_catalog.pg_trigger'::pg_catalog.regclass and d.objoid = t.oid
  join pg_catalog.pg_class c on c.oid = t.tgrelid join pg_catalog.pg_namespace n on n.oid = c.relnamespace
 where n.nspname in {SCH}
union all
select 'POLICY ' || pg_catalog.quote_ident(po.polname) || ' ON ' || pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(c.relname),
       d.description
  from d join pg_catalog.pg_policy po on d.classoid = 'pg_catalog.pg_policy'::pg_catalog.regclass and d.objoid = po.oid
  join pg_catalog.pg_class c on c.oid = po.polrelid join pg_catalog.pg_namespace n on n.oid = c.relnamespace
 where n.nspname in {SCH}
union all
select 'RULE ' || pg_catalog.quote_ident(r.rulename) || ' ON ' || pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(c.relname),
       d.description
  from d join pg_catalog.pg_rewrite r on d.classoid = 'pg_catalog.pg_rewrite'::pg_catalog.regclass and d.objoid = r.oid
  join pg_catalog.pg_class c on c.oid = r.ev_class join pg_catalog.pg_namespace n on n.oid = c.relnamespace
 where n.nspname in {SCH} and r.rulename <> '_RETURN' and {not_ext('pg_catalog.pg_class', 'c')}
"""

# ACLs. One row per object with a non-null ACL; `entries` is the exploded list. Column ACLs are
# their own target. The owner and grantor are carried so the loader can reproduce the ACL exactly.
Q_ACLS = f"""
with objs as (
  select case c.relkind when 'S' then 'SEQUENCE' else 'TABLE' end as kind,
         pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(c.relname) as target, null::text as col,
         c.relowner as owner, c.relacl as acl
    from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace
   where c.relkind in ('r', 'v', 'S') and n.nspname in {SCH} and c.relacl is not null and {not_ext('pg_catalog.pg_class', 'c')}
  union all
  select 'COLUMN', pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(c.relname), pg_catalog.quote_ident(a.attname),
         c.relowner, a.attacl
    from pg_catalog.pg_attribute a join pg_catalog.pg_class c on c.oid = a.attrelid
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
   where a.attnum > 0 and not a.attisdropped and a.attacl is not null and n.nspname in {SCH} and {not_ext('pg_catalog.pg_class', 'c')}
  union all
  select case p.prokind when 'p' then 'PROCEDURE' else 'FUNCTION' end,
         pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(p.proname) || '(' || pg_catalog.pg_get_function_identity_arguments(p.oid) || ')',
         null, p.proowner, p.proacl
    from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname in {SCH} and p.proacl is not null and {not_ext('pg_catalog.pg_proc', 'p')}
  union all
  select 'SCHEMA', pg_catalog.quote_ident(n.nspname), null, n.nspowner, n.nspacl
    from pg_catalog.pg_namespace n where n.nspname in {SCH} and n.nspacl is not null
  union all
  select 'TYPE', pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(t.typname), null, t.typowner, t.typacl
    from pg_catalog.pg_type t join pg_catalog.pg_namespace n on n.oid = t.typnamespace
   where n.nspname in {SCH} and t.typacl is not null and t.typtype in ('e', 'c') and {not_ext('pg_catalog.pg_type', 't')}
)
select o.kind, o.target, o.col, pg_catalog.pg_get_userbyid(o.owner) as owner, o.acl::text as acl_text,
       (select pg_catalog.json_agg(pg_catalog.json_build_object(
                 'grantee', case when x.grantee = 0 then 'PUBLIC' else pg_catalog.quote_ident(pg_catalog.pg_get_userbyid(x.grantee)) end,
                 'grantor', pg_catalog.pg_get_userbyid(x.grantor),
                 'privilege', x.privilege_type, 'grantable', x.is_grantable) order by x.ord)
          from pg_catalog.aclexplode(o.acl) with ordinality x(grantor, grantee, privilege_type, is_grantable, ord)) as entries
  from objs o
 order by 1, 2, 3
"""

Q_CRON = """
select j.jobid, j.schedule, j.command, j.nodename, j.nodeport, j.database, j.username, j.active, j.jobname
  from cron.job j order by j.jobid
"""

# Default privileges, for the schemas the lab has. The loader installs them LAST, so the objects
# it creates carry production's explicit ACLs (phase 18) and nothing more, and an object the lab
# creates afterwards (a later migration) gets what it would get in production.
Q_DEFAULT_ACL = """
select pg_catalog.quote_ident(pg_catalog.pg_get_userbyid(d.defaclrole)) as role, pg_catalog.quote_ident(n.nspname) as schema,
       d.defaclobjtype::text as objtype, d.defaclacl::text as acl_text,
       (select pg_catalog.json_agg(pg_catalog.json_build_object(
                 'grantee', case when x.grantee = 0 then 'PUBLIC' else pg_catalog.quote_ident(pg_catalog.pg_get_userbyid(x.grantee)) end,
                 'privilege', x.privilege_type, 'grantable', x.is_grantable) order by x.grantee, x.privilege_type)
          from pg_catalog.aclexplode(d.defaclacl) x) as entries
  from pg_catalog.pg_default_acl d join pg_catalog.pg_namespace n on n.oid = d.defaclnamespace
 where n.nspname in ('public', 'storage', 'extensions', 'cron', 'auth')
 order by 1, 2, 3
"""

Q_LEDGER = """
select m.version, m.name, m.created_by from supabase_migrations.schema_migrations m order by m.version
"""


# --------------------------------------------------------------------------- statement writers

class Phase:
    def __init__(self, name: str):
        self.name = name
        self.stmts: list[tuple[str, str, str]] = []

    def add(self, kind: str, ident: str, sql: str) -> None:
        sql = sql.strip()
        if not sql.endswith(";"):
            sql += ";"
        if MARK.strip() in sql:
            raise SystemExit(f"refusing: statement for {kind} {ident} contains the marker")
        for pat in SECRET_PATTERNS:
            if pat.search(sql):
                raise SystemExit(f"refusing: statement for {kind} {ident} matches a secret pattern ({pat.pattern})")
        self.stmts.append((kind, ident.replace("\n", " "), sql))

    def write(self, path: str) -> dict:
        with open(path, "w") as fh:
            fh.write(f"-- {os.path.basename(path)}: {len(self.stmts)} statements, exported from production's catalog\n")
            for kind, ident, sql in self.stmts:
                fh.write(f"{MARK}{kind} {ident}\n{sql}\n")
        data = open(path, "rb").read()
        return {"file": os.path.basename(path), "statements": len(self.stmts), "bytes": len(data),
                "sha256": hashlib.sha256(data).hexdigest()}


def seq_options(s: dict, typ: str | None = None) -> str:
    parts = []
    if typ:
        parts.append(f"AS {typ}")
    parts += [f"INCREMENT BY {s['inc']}", f"MINVALUE {s['min']}", f"MAXVALUE {s['max']}",
              f"START WITH {s['start']}", f"CACHE {s['cache']}", "CYCLE" if s["cycle"] else "NO CYCLE"]
    return " ".join(parts)


def reloptions_sql(opts) -> str:
    if not opts:
        return ""
    return " WITH (" + ", ".join(opts) + ")"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    reads: dict[str, str] = {}
    counts: dict[str, int] = {}

    def get(label: str, sql: str) -> list[dict]:
        at, rows = read(sql)
        reads[label] = at
        counts[label] = len(rows)
        print(f"  read {label:<16} {len(rows):>6} rows at {at}", file=sys.stderr)
        return rows

    print("== reading production's catalog (read-only endpoint)", file=sys.stderr)
    meta = get("meta", Q_META)[0]
    unsupported = [r for r in get("unsupported", Q_UNSUPPORTED) if r["n"]]
    if unsupported:
        raise SystemExit(f"refusing: object kinds this exporter does not reproduce: {unsupported}")
    schemas = get("schemas", Q_SCHEMAS)
    enums = get("enums", Q_ENUMS)
    composites = get("composites", Q_COMPOSITES)
    sequences = get("sequences", Q_SEQUENCES)
    identity_seqs = {r["qn"]: r for r in get("identity_seqs", Q_IDENTITY_SEQS)}
    tables = get("tables", Q_TABLES)
    oids = [r["oid"] for r in get("function_oids", Q_FUNCTION_OIDS)]
    functions: list[dict] = []
    for i in range(0, len(oids), 250):
        chunk = oids[i:i + 250]
        at, rows = read(q_functions(chunk[0], chunk[-1] + 1))
        reads[f"functions[{i}]"] = at
        functions += rows
    counts["functions"] = len(functions)
    print(f"  read functions        {len(functions):>6} rows", file=sys.stderr)
    if len(functions) != len(oids):
        raise SystemExit(f"function count moved during the read: {len(oids)} oids, {len(functions)} definitions")
    views = get("views", Q_VIEWS)
    constraints = get("constraints", Q_CONSTRAINTS)
    indexes = get("indexes", Q_INDEXES)
    triggers = get("triggers", Q_TRIGGERS)
    rules = get("rules", Q_RULES)
    policies = get("policies", Q_POLICIES)
    comments = get("comments", Q_COMMENTS)
    acls = get("acls", Q_ACLS)
    cron = get("cron", Q_CRON)
    ledger = get("ledger", Q_LEDGER)
    default_acls = get("default_acls", Q_DEFAULT_ACL)

    phases: dict[str, Phase] = {}

    def ph(name: str) -> Phase:
        return phases.setdefault(name, Phase(name))

    # 01 schemas (public exists everywhere)
    for s in schemas:
        if s["name"] != "public":
            ph("01_schemas").add("schema", s["qn"], f"CREATE SCHEMA IF NOT EXISTS {s['qn']}")
        if s["owner"] not in ("postgres", "pg_database_owner"):
            ph("01_schemas").add("owner", s["qn"], f"ALTER SCHEMA {s['qn']} OWNER TO {s['owner']}")
    # 02 enum types
    for t in enums:
        ph("02_types").add("enum", t["qn"], f"CREATE TYPE {t['qn']} AS ENUM ({t['labels'] or ''})")
    # 03 sequences (identity sequences come with their column)
    for s in sequences:
        if s["is_identity"]:
            continue
        unlogged = "UNLOGGED " if s["persistence"] == "u" else ""
        ph("03_sequences").add("sequence", s["qn"],
                               f"CREATE {unlogged}SEQUENCE {s['qn']} {seq_options(s, s['typ'])}")
    # 04 composite types
    for t in composites:
        ph("04_types_composite").add("composite", t["qn"], f"CREATE TYPE {t['qn']} AS ({t['cols'] or ''})")
    # 05 tables, 07 defaults
    for t in tables:
        cols = []
        for c in t["cols"] or []:
            col = f"{c['qname']} {c['type']}"
            if c["collate"]:
                col += f" COLLATE {c['collate']}"
            if c["generated"] == "s":
                col += f" GENERATED ALWAYS AS ({c['default']}) STORED"
            if c["identity"] in ("a", "d"):
                s = identity_seqs.get(c["identity_seq"]) if c["identity_seq"] else None
                how = "ALWAYS" if c["identity"] == "a" else "BY DEFAULT"
                opts = f" (SEQUENCE NAME {c['identity_seq']} {seq_options(s)})" if s else ""
                col += f" GENERATED {how} AS IDENTITY{opts}"
            if c["notnull"]:
                col += " NOT NULL"
            cols.append(col)
            if c["default"] is not None and c["generated"] != "s":
                ph("07_defaults").add("default", f"{t['qn']}.{c['qname']}",
                                      f"ALTER TABLE ONLY {t['qn']} ALTER COLUMN {c['qname']} SET DEFAULT {c['default']}")
            if c["storage"]:
                kind = {"p": "PLAIN", "e": "EXTERNAL", "m": "MAIN", "x": "EXTENDED"}[c["storage"]]
                ph("07_defaults").add("storage", f"{t['qn']}.{c['qname']}",
                                      f"ALTER TABLE ONLY {t['qn']} ALTER COLUMN {c['qname']} SET STORAGE {kind}")
            if c["stattarget"] is not None and c["stattarget"] >= 0:
                ph("07_defaults").add("statistics", f"{t['qn']}.{c['qname']}",
                                      f"ALTER TABLE ONLY {t['qn']} ALTER COLUMN {c['qname']} SET STATISTICS {c['stattarget']}")
            if c["options"]:
                ph("07_defaults").add("attoptions", f"{t['qn']}.{c['qname']}",
                                      f"ALTER TABLE ONLY {t['qn']} ALTER COLUMN {c['qname']} SET ({', '.join(c['options'])})")
        unlogged = "UNLOGGED " if t["persistence"] == "u" else ""
        body = ",\n    ".join(cols)
        ph("05_tables").add("table", t["qn"], f"CREATE {unlogged}TABLE {t['qn']} (\n    {body}\n){reloptions_sql(t['reloptions'])}")
        if t["owner"] != "postgres":
            ph("19_owners").add("owner", t["qn"], f"ALTER TABLE {t['qn']} OWNER TO {t['owner']}")
        if t["rls"]:
            ph("16_rls").add("rls", t["qn"], f"ALTER TABLE {t['qn']} ENABLE ROW LEVEL SECURITY")
        if t["force_rls"]:
            ph("16_rls").add("force_rls", t["qn"], f"ALTER TABLE {t['qn']} FORCE ROW LEVEL SECURITY")
        if t["replident"] == "f":
            ph("16_rls").add("replica_identity", t["qn"], f"ALTER TABLE {t['qn']} REPLICA IDENTITY FULL")
        elif t["replident"] == "n":
            ph("16_rls").add("replica_identity", t["qn"], f"ALTER TABLE {t['qn']} REPLICA IDENTITY NOTHING")
    # 06 functions
    for f in functions:
        ident = f"{f['qn']}({f['identity_args']})"
        ph("06_functions").add("procedure" if f["kind"] == "p" else "function", ident, f["def"])
        if f["owner"] != "postgres":
            what = "PROCEDURE" if f["kind"] == "p" else "FUNCTION"
            ph("19_owners").add("owner", ident, f"ALTER {what} {ident} OWNER TO {f['owner']}")
    # 08 sequence ownership
    for s in sequences:
        if s["owned_by"] and not s["is_identity"]:
            ph("08_sequence_owned_by").add("owned_by", s["qn"], f"ALTER SEQUENCE {s['qn']} OWNED BY {s['owned_by']}")
        if s["owner"] != "postgres":
            ph("19_owners").add("owner", s["qn"], f"ALTER SEQUENCE {s['qn']} OWNER TO {s['owner']}")
    # 09 views
    for v in views:
        ph("09_views").add("view", v["qn"], f"CREATE VIEW {v['qn']}{reloptions_sql(v['reloptions'])} AS\n{v['def']}")
        if v["owner"] != "postgres":
            ph("19_owners").add("owner", v["qn"], f"ALTER VIEW {v['qn']} OWNER TO {v['owner']}")
    # 10-12 constraints
    order = {"p": "10_constraints_keys", "u": "10_constraints_keys", "x": "10_constraints_keys",
             "c": "11_constraints_check", "f": "12_constraints_fk"}
    for c in constraints:
        ph(order[c["type"]]).add(f"constraint_{c['type']}", f"{c['qtable']}.{c['qname']}",
                                 f"ALTER TABLE ONLY {c['qtable']} ADD CONSTRAINT {c['qname']} {c['def']}")
    # 13 indexes
    for i in indexes:
        if not i["by_constraint"]:
            ph("13_indexes").add("index", i["qn"], i["def"])
        if i["clustered"]:
            ph("13_indexes_post").add("cluster_on", i["qn"],
                                      f"ALTER TABLE {i['qtable']} CLUSTER ON {i['qn'].split('.', 1)[1]}")
        if i["replident"]:
            ph("13_indexes_post").add("replica_identity", i["qn"],
                                      f"ALTER TABLE {i['qtable']} REPLICA IDENTITY USING INDEX {i['qn'].split('.', 1)[1]}")
    # 14 triggers
    for t in triggers:
        ph("14_triggers").add("trigger", f"{t['qtable']}.{t['qname']}", t["def"])
        state = {"D": "DISABLE", "R": "ENABLE REPLICA", "A": "ENABLE ALWAYS"}.get(t["enabled"])
        if state:
            ph("14_triggers").add("trigger_state", f"{t['qtable']}.{t['qname']}",
                                  f"ALTER TABLE {t['qtable']} {state} TRIGGER {t['qname']}")
    # 15 rules
    for r in rules:
        ph("15_rules").add("rule", f"{r['qtable']}.{r['qname']}", r["def"])
        state = {"D": "DISABLE", "R": "ENABLE REPLICA", "A": "ENABLE ALWAYS"}.get(r["enabled"])
        if state:
            ph("15_rules").add("rule_state", f"{r['qtable']}.{r['qname']}", f"ALTER TABLE {r['qtable']} {state} RULE {r['qname']}")
    # 16 policies (RLS switches were added above)
    cmds = {"r": "SELECT", "a": "INSERT", "w": "UPDATE", "d": "DELETE", "*": "ALL"}
    for p in policies:
        sql = (f"CREATE POLICY {p['qname']} ON {p['qtable']} AS {'PERMISSIVE' if p['permissive'] else 'RESTRICTIVE'} "
               f"FOR {cmds[p['cmd']]} TO {p['roles']}")
        if p["qual"] is not None:
            sql += f" USING ({p['qual']})"
        if p["withcheck"] is not None:
            sql += f" WITH CHECK ({p['withcheck']})"
        ph("16_rls").add("policy", f"{p['qtable']}.{p['qname']}", sql)
    # 17 comments
    for c in comments:
        lit = "E'" + c["text"].replace("\\", "\\\\").replace("'", "''") + "'"
        ph("17_comments").add("comment", c["target"], f"COMMENT ON {c['target']} IS {lit}")
    # 18 ACLs: reproduce each non-null ACL exactly (the loader creates objects with no default
    # privileges in force, so a NULL ACL in production stays NULL in the lab).
    for o in acls:
        kind, target, col = o["kind"], o["target"], o["col"]
        ident = f"{kind} {target}" + (f"({col})" if col else "")
        if kind == "COLUMN":
            on = f"TABLE {target}"
            privs = lambda p: f"{p} ({col})"  # noqa: E731
            ph("18_acl").add("acl_reset", ident, f"REVOKE ALL ({col}) ON {on} FROM PUBLIC")
        else:
            on = f"{kind} {target}"
            privs = lambda p: p  # noqa: E731
            # Revoke from everyone the ACL will name (and the owner and PUBLIC): an object that
            # already carries grants (a schema the shims made) then starts empty, and the grants
            # below rebuild production's array in its own order.
            who = ["PUBLIC", pg_ident(o["owner"])]
            for e in o["entries"] or []:
                if e["grantee"] not in who:
                    who.append(e["grantee"])
            ph("18_acl").add("acl_reset", ident, f"REVOKE ALL ON {on} FROM {', '.join(who)}")
        # aclexplode lists entries in the array's own order; GRANT appends a new grantee at the end,
        # so granting in that order reproduces production's array, not just its contents.
        merged: dict[tuple[str, bool], list[str]] = {}
        for e in o["entries"] or []:
            merged.setdefault((e["grantee"], bool(e["grantable"])), []).append(privs(e["privilege"]))
        for (grantee, grantable), plist in merged.items():
            grant = f"GRANT {', '.join(plist)} ON {on} TO {grantee}"
            if grantable:
                grant += " WITH GRANT OPTION"
            ph("18_acl").add("acl_grant", ident, grant)
    # 20 sequence values (the lab's ids continue where production's do)
    for s in sequences:
        if s["last_value"] is not None and not s["is_identity"]:
            ph("20_sequence_values").add("setval", s["qn"],
                                         f"SELECT pg_catalog.setval({sql_lit(s['qn'])}, {s['last_value']}, true)")
    for qn, s in identity_seqs.items():
        if s["last_value"] is not None:
            ph("20_sequence_values").add("setval", qn, f"SELECT pg_catalog.setval({sql_lit(qn)}, {s['last_value']}, true)")
    # 21 cron jobs, every one inactive in the lab
    for j in cron:
        ph("21_cron").add("cron_job", f"{j['jobid']} {j['jobname'] or ''}",
                          "INSERT INTO cron.job (jobid, schedule, command, nodename, nodeport, database, username, active, jobname) "
                          f"VALUES ({j['jobid']}, {sql_lit(j['schedule'])}, {sql_lit(j['command'])}, {sql_lit(j['nodename'])}, "
                          f"{j['nodeport']}, {sql_lit(j['database'])}, {sql_lit(j['username'])}, false, {sql_lit(j['jobname'])})")
    if cron:
        ph("21_cron").add("cron_seq", "cron.jobid_seq",
                          f"SELECT pg_catalog.setval('cron.jobid_seq', {max(j['jobid'] for j in cron)}, true)")
    # 22 the migration ledger's versions and names (statements are not copied: the schema is)
    for m in ledger:
        ph("22_ledger").add("ledger", m["version"],
                            "INSERT INTO supabase_migrations.schema_migrations (version, name, created_by) VALUES "
                            f"({sql_lit(m['version'])}, {sql_lit(m['name'])}, {sql_lit(m['created_by'])})")

    # 23 default privileges, last
    objtypes = {"r": "TABLES", "S": "SEQUENCES", "f": "FUNCTIONS", "T": "TYPES", "n": "SCHEMAS"}
    for d in default_acls:
        merged: dict[tuple[str, bool], list[str]] = {}
        for e in d["entries"] or []:
            merged.setdefault((e["grantee"], bool(e["grantable"])), []).append(e["privilege"])
        for (grantee, grantable), plist in merged.items():
            sql = (f"ALTER DEFAULT PRIVILEGES FOR ROLE {d['role']} IN SCHEMA {d['schema']} "
                   f"GRANT {', '.join(plist)} ON {objtypes[d['objtype']]} TO {grantee}")
            if grantable:
                sql += " WITH GRANT OPTION"
            ph("23_default_privileges").add("default_acl", f"{d['role']} {d['schema']} {d['objtype']}", sql)

    files = []
    for name in sorted(phases):
        files.append(phases[name].write(os.path.join(a.out, f"{name}.sql")))
    manifest = {
        "exported_by": "lab/engine/lib/export_prod.py",
        "source": {"project_ref": prod_read.PROJECT_REF, "endpoint": "POST /v1/projects/{ref}/database/query/read-only",
                   "role": "supabase_read_only_user"},
        "finished_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "production": meta,
        "reads": reads,
        "counts": counts,
        "files": files,
    }
    with open(os.path.join(a.out, "manifest.json"), "w") as fh:
        json.dump(manifest, fh, indent=1, sort_keys=False)
        fh.write("\n")
    print(f"== wrote {len(files)} files, {sum(f['statements'] for f in files)} statements to {a.out}", file=sys.stderr)
    return 0


def sql_lit(v) -> str:
    if v is None:
        return "NULL"
    return "'" + str(v).replace("'", "''") + "'"


def pg_ident(name: str) -> str:
    return name if re.fullmatch(r"[a-z_][a-z0-9_$]*", name) else '"' + name.replace('"', '""') + '"'


if __name__ == "__main__":
    sys.exit(main())
