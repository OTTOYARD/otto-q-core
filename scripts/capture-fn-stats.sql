-- Capture pg_stat_user_functions in the format scripts/fn-delta.py reads.
--
-- Run BOTH queries. Query 1 is the diffable capture; query 2 is the overload
-- breakdown that query 1 structurally cannot carry.
--
-- WHY TWO QUERIES INSTEAD OF ONE WITH funcid. `db/evidence/r28_g_fn_baseline.md`
-- was captured at 16:23:39 UTC with bare names, and it cannot be re-captured --
-- its validity rests on having been taken before `r28_g` fired. So the after-
-- capture must match that format exactly or every row diffs as NEW. Query 2
-- carries the argument types alongside, so the overload detail is recorded
-- without breaking the diff. Once both sides of a future round use query 2's
-- shape, query 1 can retire.
--
-- These counters only move in a session that has set track_functions. Verify
-- `SHOW track_functions` is 'none' globally before trusting a delta, or some
-- other session is contributing to it.

-- QUERY 1 -- the diffable capture. Paste inside a ``` fence.
SELECT schemaname || '|' || funcname || '|' || calls || '|'
       || round(self_time::numeric, 1) AS row
  FROM pg_stat_user_functions
 ORDER BY calls DESC, schemaname, funcname;

-- QUERY 2 -- every name that has more than one funcid, with its signature.
-- Empty result = no overloads = query 1 is unambiguous on its own.
SELECT s.schemaname,
       s.funcname,
       s.funcid,
       pg_get_function_identity_arguments(s.funcid) AS args,
       s.calls,
       round(s.self_time::numeric, 1) AS self_ms
  FROM pg_stat_user_functions s
  JOIN (SELECT schemaname, funcname
          FROM pg_stat_user_functions
         GROUP BY schemaname, funcname
        HAVING count(*) > 1) d
    ON d.schemaname = s.schemaname AND d.funcname = s.funcname
 ORDER BY s.schemaname, s.funcname, s.calls DESC;
