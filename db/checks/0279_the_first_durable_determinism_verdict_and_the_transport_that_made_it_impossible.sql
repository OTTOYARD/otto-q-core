-- 0279  G93 CLOSED: THE FIRST DURABLE DETERMINISM VERDICT THIS ENGINE HAS EVER HELD,
--       AND THE TRANSPORT CEILING THAT MADE PRODUCING ONE IMPOSSIBLE THROUGH THE PATH
--       I WAS USING. Ledger and pair change in `db/migrations/0386`.
--
-- Read-only. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8).
--
-- ══ 1. THE VERDICT ═════════════════════════════════════════════════════════
--
--   verdict_id        **3**          (1 and 2 were burned by 0386's own rolled-back
--                                    postflight probes -- `bigserial` is non-transactional,
--                                    the same property 0231 records for `nextval`)
--   certified_at      2026-09-20 17:42:00 UTC  = 12:42 PM CT
--   scenario/seed     busy_day / 314159 / 12 ticks
--   outcome           **passed**   equal true, complete true
--   atoms_compared    **14**       disagreeing_atoms **{}**   null_atoms **{}**
--   engine_hash       49e5ba2a7117
--
-- **This is the validation that `0383`, `0385` and `0386` needed and could not otherwise
-- have.** All three are `forces_recert`-relevant changes to the tick and certification
-- paths, and the fourteen atoms agree byte-for-byte across two arms on an identical seed.
-- `null_atoms` being empty also settles, for this column, that the NULL trap `0386`
-- documents is not currently firing: no atom hash is NULL, so the AND chain is not
-- silently reporting `failed` without a disagreement.
--
-- It is ONE column. Six more twin-depot columns are grinding through the runner (§4), and
-- per 2.9a's blind-spot doctrine one passing pair licenses no general claim.

SELECT verdict_id, certified_at, scenario, seed, ticks, outcome, equal, complete,
       atoms_compared, disagreeing_atoms, null_atoms, left(engine_hash,12) AS engine
  FROM public.ottoq_determinism_verdict_ledger
 ORDER BY verdict_id;

SELECT scenario, seed, ticks, status, satisfies_floor, certified_at
  FROM public.ottoq_determinism_canon
 WHERE depot_id = '11111111-1111-1111-1111-111111111111'
 ORDER BY ticks, scenario, seed;

-- ══ 2. WHY NO VERDICT COULD BE PRODUCED THROUGH THE PATH I WAS USING ═══════
--
-- Every SQL statement in this session runs through the Supabase Management API. **That path
-- cancels any statement at 120 seconds, and it does so twice over:**
--
--   `SELECT pg_sleep(160)`                          -> HTTP 400, **SQLSTATE 57014**,
--                                                      "canceling statement due to statement
--                                                      timeout", at exactly 2m00s.
--   `SET statement_timeout = 0; SELECT pg_sleep(150)` -> **HTTP 524** at 2m05s. The `SET`
--                                                      does lift Postgres's own limit -- the
--                                                      query outlived 120s -- and the edge
--                                                      proxy cuts the connection anyway.
--
-- So raising the client read timeout is useless: the ceiling is the server and then the
-- proxy. **A 12-tick pair takes 192.7 seconds** (job 741's predecessor, measured
-- `end_time - start_time`), so it cannot complete in one call, and my first attempt died
-- client-side at 120s.
--
-- **It rolled back cleanly, which is the part worth recording.** After the timeout there
-- were no new rows in `ottoq_sim_runs`, no new archives and no half-finished arm: the
-- cancelled statement aborted its transaction. So the pair is all-or-nothing under this
-- failure, and the author's comment *"The verdict survives a dropped client"* is about the
-- narrower case where the SERVER finishes and the CLIENT goes away.
--
-- **The role is not the constraint, which rules out the obvious workaround.** `pg_roles`
-- shows `statement_timeout` set for `anon` (15s), `authenticated` (8s), `authenticator`
-- (8s), `service_role` (20s) and `supabase_admin` (0) -- and **`postgres` carries only
-- `search_path`.** A pg_cron job runs as `postgres`, so it inherits no role-level timeout at
-- all. That is why detached execution works and why the `SET` in the existing job is
-- belt-and-braces rather than the mechanism.
--
-- ══ 3. AND TWO CONCLUSIONS I REACHED AND HAD TO WITHDRAW, BOTH FROM READING A
--      MEASUREMENT TOO EARLY ═══════════════════════════════════════════════
--
-- **(a) "pg_cron ran only the first statement."** The first recert job's detail row read
-- `status=succeeded, return_message='SET', end_time=17:42:01` -- one second -- and I
-- concluded the `SELECT` had been dropped and that the multi-statement form was the defect.
-- **pg_cron updates that row as the job progresses.** Re-read afterwards, the same row says
-- `return_message='1 row'`, `end_time=17:45:13`, **192.7 seconds** -- and the verdict was in
-- the ledger the whole time I was diagnosing its absence. A detail row read mid-flight is a
-- progress indicator, not a result.
--
-- **(b) "every visit is superseded, so 0383 is inert."** Measured 217 of 217 visits
-- `superseded` on the twin depot and briefly believed the atom pipeline was dead and my own
-- G86 fix could never fire. It was correct behaviour: the demo run had **completed** at
-- 16:54:00, and `ottoq_tg_close_run_needs_on_terminal` fires
-- `ottoq_close_run_needs(run,'run_completed')` on a terminal run status -- 141 of those 217
-- rows carry `meta->>'close_reason' = 'run_completed'` and name the closer in
-- `meta->>'closed_by'`. I also briefly suspected the `status` column default, which is
-- `'open'`. Both dead ends, both cheap to rule out by reading, both recorded because the
-- same reflex produced 0277's retracted attribution.
--
-- The pattern in both: **a number that looked like a defect was a moment in a process.**

SELECT n.meta->>'closed_by' AS closed_by, n.meta->>'close_reason' AS reason, count(*) AS n
  FROM public.ottoq_visit_needs n
 WHERE n.depot_id = '11111111-1111-1111-1111-111111111111'
 GROUP BY 1,2 ORDER BY 3 DESC;

-- ══ 4. THE RUNNER, AND WHY IT IS A CRON JOB RATHER THAN A MIGRATION ════════
--
-- `ottoq_cert_columns` declares the canon matrix, `ottoq_cert_matrix` reports it, and
-- `ottoq_cert_recert_floor` expires it -- **and nothing executed it.** Recertification had
-- always been someone calling `ottoq_determinism_pair` by hand. That is structurally the
-- same shape as G86: a declared thing with a reporter and no executor.
--
-- `ottoq-recert-runner` (pg_cron job 741, `* * * * *`) closes it with no new schema:
--
--     SET statement_timeout = 0;
--     DO $runner$ ... $runner$;
--
-- One `DO` block, so it is a single statement that begins after the `SET` has taken effect.
-- It takes `pg_try_advisory_xact_lock(hashtext('ottoq_recert_runner'))` so a firing during a
-- 193-second pair returns immediately rather than starting a second pair -- two pairs would
-- fight, because each one resets the fleet. It refuses while any run is `running` or
-- `paused`. It reads the next due column straight from `ottoq_determinism_canon`, so the
-- definition of "due" lives in one place. The same posture as the existing (inactive)
-- `ottoq-cert-battery` job 13, which is where the pattern was found.
--
-- **Scoped to the twin depot on purpose (rule 8), which leaves two canon columns
-- uncertified and that is a judgement rather than an oversight.** Two of the nine declared
-- columns are `grid_smoke` on fixture depot `aacd0bb0-…`, kept because they are the only
-- columns exercising the 0132 site power gate under a tight cap. They are a regression
-- canary, not a site validation -- but rule 8 is stated absolutely ("do not test or validate
-- across multiple sites"), so the runner does not touch them and they will keep reading
-- `NEVER CERTIFIED DURABLY`. **Whether a fixture-depot determinism canary counts as
-- "validating a second site" is Chase's call, not mine to assume either way.**

SELECT j.jobid, j.jobname, j.schedule, j.active
  FROM cron.job j WHERE j.jobname = 'ottoq-recert-runner';

SELECT r.status, left(r.return_message,40) AS msg,
       r.start_time::timestamp(0) AS started,
       EXTRACT(EPOCH FROM (r.end_time - r.start_time))::numeric(8,1) AS secs
  FROM cron.job_run_details r
  JOIN cron.job j ON j.jobid = r.jobid
 WHERE j.jobname = 'ottoq-recert-runner'
 ORDER BY r.start_time DESC LIMIT 10;

-- ══ 5. WHAT THIS DOES AND DOES NOT LICENSE ═════════════════════════════════
--
-- SAY: *"the fourteen-atom verdict is now durable, and the first pair recorded under it
-- passed with zero disagreeing atoms"* -- and give the verdict_id and the date, because the
-- ledger is `class='evidence'` and survives the purge that erased its 1,166 predecessors.
--
-- DO NOT SAY the canon matrix is green. Seven twin-depot columns must pass before that
-- sentence exists, two fixture columns are deliberately out of scope, and a single 12-tick
-- pair is the fastest and shallowest column in the matrix -- `ottoq_cert_columns` records
-- that 0108 and 0193 both broke first at 48 ticks, which is exactly why the 48-tick column
-- exists and why it must not be the one that quietly stops running.
