-- 0493  A bay held for a car due (0835), a directive's facts against its brief (agent v34), and the size of the idle
--       posts under charge-port-side routing.
--
-- Twin depot 11111111-1111-1111-1111-111111111111, scenario busy_day. Read 2026-11-14 05:43 to 06:28 UTC (11:43 PM
-- 2026-11-13 to 12:28 AM CT) unless a section says otherwise. Engine rows are purged by the next demo start; the
-- agent's evidence (ottoq_agent_pass_evidence, class evidence) is what most of this reads, and it survives.
-- Single readings and counts over unpaired runs with different seeds. No pair, no sweep (rule 12).
--
-- §1 G541, SECOND HALF: THE BOARD COUNTED A BAY IDLE WHILE THE CALENDAR HAD ALREADY SEATED A CAR IN IT.
--
--    Runs 14d6eda7, c8913ea2 and 1902d13b (all after 0829). The board's constraint block against ottoq_stall_bookings,
--    both in sim time:
--      consulted boards                                                     81   (28 + 26 + 27)
--      wash bays "idle with a car ready"                                    16   (1 + 6 + 9)
--      of those, a wash booking already on the calendar began within
--        1.1 minutes of the board's clock                                    9
--        10 minutes                                                         13
--      the three left: the next wash began 11.2, 16.8 and 23.0 minutes later
--      wash bays' busy_now under the bookings covering the clock             5 of 81
--      service bays' busy_now over the bookings covering the clock           6 of 81   (a car in the bay past its window)
--    WHAT IT SAYS. On 13 of the 16 the idle bay was a booked car's and the car was on its way in. The board counted
--    busy by the cars' states and ready by the line, so the bay read idle and the same car read ready for it.
--    WHAT IT DOES NOT SAY. That any car waited for a wash bay: on a95e51a3 cars entered one a median 1.9 minutes
--    after staging (0492 §4). The three boards left are not explained here.
--    FIX: db/migrations/0835 (public.ottoq_depot_constraint, the bays only). §7 has its apply and its first run.
--
-- §2 MEASURED AWAY: THE WASH BAYS' "detail" BOOKINGS BLOCK NOTHING.
--
--    While reading §1: on c8913ea2 and 1902d13b the wash bays carry 61 bookings with purpose 'detail' for
--    interior_deep_clean, work 0817 moved to the charging posts. All 61 are released with release_reason
--    'cabin_work_is_the_posts_arm', a median 1.6 and 1.7 sim minutes after they were booked (max 4.3), and none after
--    its window began. No bay minute was held. (released_at on this table is sim time: it precedes booked_at, the
--    real clock, by hours.) Not a defect; not built.
--
-- §3 G545: WHAT A DIRECTIVE SAYS ABOUT A CUT CAR, AGAINST THE BRIEF THE MODEL WAS SENT.
--
--    v32 counts whether a directive names its subject. Nothing read whether what it says is true (0492 §6).
--    Graded by the deployed function itself (POST {"grade_pass_ids": [...]}, agent v34, function version 50,
--    06:27:45 UTC; no model call, no write): every consulted pass at the twin depot that kept a brief with subjects
--    and an answer, 2026-11-13 03:11 UTC onward.
--                                            passes  directives  naming a cut car  facts read  wrong
--      nvidia/nemotron-3-ultra-550b-a55b        242         703               244         478      7   (1.5%)
--      nvidia/nemotron-3.5-lightning-30b-a3b     24          70                20          32     10   (31%)
--    A fact is a post, a place in line ("pos N"), minutes since the cut ("N min ago", within 3) or the SoC the charge
--    was cut at, read in the words after the car's name up to the next car the brief names.
--    The primary's 7: two in pass 10330 are real (it repeated "check charging again on NASH-DCFC-STALL-14" from the
--    fallback's directive of two passes before, of two cars the brief had waiting in line with no post); five are a
--    place in line one to three off, or said of a car the cut-charge rows have charging again, in a list built from
--    another part of the brief. Those five are not established as the model's error.
--    The fallback's: minutes copied from its own last answer ("cut 46 min ago" at 72 and at 102 minutes), a post the
--    brief never gave the car, a place in line.
--    WHAT WAS BUILT. edge-functions/_shared/agent_directive_facts.ts. Every miss is counted on the pass
--    (levers.directive_facts and the decision row). A directive a FALLBACK model wrote that contradicts the brief is
--    not applied; it is kept, with what it said and what the brief holds, in the rejected list. The primary's are
--    applied and counted: at 7 in 478, five of them not established, refusing would cost more alerts than it saves.
--    The brief's prompt now says a car still waiting is written again from this brief's numbers.
--    WHAT IT DOES NOT DO. It reads a directive against the brief, not the brief against the depot; it reads cut cars
--    only; and a fact it cannot find in the text is not checked.
--
-- §4 THE FALLBACK HAS NOW ANSWERED LIVE PASSES (open in 0492 §6).
--
--    24 consulted passes since 2026-11-13 03:11 UTC were answered by nvidia/nemotron-3.5-lightning-30b-a3b on live
--    runs, with 70 directives (§3's second row). So v33's chain works on a live primary failure. Its directives are
--    marked by_fallback_model, and from v34 the ones that contradict the brief are not applied.
--
-- §5 G542, READ AGAIN: A CUT CAR KEEPS ITS WAIT, AND THE LONG WAITS ARE THE WHOLE LINE'S.
--
--    Run c8913ea2: Waymo-AV-024, cut at 97% by fault.connector_cable, was still waiting 155 minutes later (line place
--    20, then 18, 13, 12); Waymo-AV-039, cut at 98%, 160 minutes (briefs of passes 10304 to 10359).
--    Read: public.ottoq_charge_wait_min adds the minutes a car banked in earlier waiting states of the run
--    (0551, config.charge_wait), and the bank is dropped only off the site or at target less one. A car cut at 97% or
--    98% of a 100% target keeps it. So the cut car is not sent to the back.
--    Read on the live run 7435e685 at tick 220 (sim 16:48): 49 cars in the line, the first thirteen places waiting
--    123 to 157 minutes for 12 to 72 minutes of charge. Every car past the 90-minute floor is served longest wait
--    first (0642), so a cut car waits with the line.
--    WHAT IT SAYS. The 39 minutes of 0488 §5 and the 160 here are the line's length, not a rule against cut cars.
--    Whether a cut car should take the next free post is still an ordering question, owner by owner (rule 14).
--
-- §6 THE SIZE OF THE IDLE POSTS UNDER charge_port_side_routing (0824, on since 2026-11-13 04:42:22 UTC).
--
--    0824 §3 states the cost before the switch (78 of 116 cars take only a left-arm post; 15 of the 30 posts have
--    one) and 0490 reads the first runs. This is its size on the agent's stored boards (constraint.resources, posts),
--    means over each run's consulted boards:
--      run       first board (UTC)  cars queued  posts busy  posts idle  idle with 10+ queued
--      893a0313  11-12 04:32           17.5         21.6        6.2          1.9
--      5480be1f  11-12 06:09           17.5         20.7        6.6          1.9
--      56d8465f  11-12 14:04           32.7         22.1        1.6          1.4
--      0e3cc3c2  11-12 16:35           21.5         21.2        4.4          1.5
--      02ca304f  11-12 20:26           18.7         23.7        5.2          1.9
--      cce21ff2  11-13 00:37           21.5         21.2        6.1          1.7
--      b848a046  11-13 03:11           22.8         21.6        5.2          1.9
--      a95e51a3  11-13 04:24           28.0         17.0       11.5         11.5   <- 0824 applied during this run
--      56642c31  11-13 12:45           38.4         17.3        9.4          9.4
--      9085ca36  11-13 16:40           38.7         17.0       10.5         10.5
--      7a08f52a  11-13 19:58           41.0         19.6        7.0          7.0
--      c86b46e1  11-13 21:12           38.2         19.2        8.7          8.7
--      14d6eda7  11-14 00:48           34.9         16.4        9.4          9.4
--      c8913ea2  11-14 01:58           43.5         18.2        7.8          7.8
--      1902d13b  11-14 03:13           43.0         17.4        9.1          9.1
--    Inside a95e51a3 the posts read 26 to 30 busy and none idle on every board to 04:53 UTC, then fell: 17 busy at
--    05:00, 0 busy with 26 queued and 30 idle at 05:15 (0490 §1 is that run's defect, fixed by 0825 at 05:42).
--    On the live run 7435e685 (146 cars, after 0833) at tick 233: 46 cars in the line, every one needing a left-arm
--    post; the one free post has a right arm and fits none of them; of the 15 left-arm posts in use, 4 held a car
--    that can charge on either side.
--    WHAT IT SAYS. With the rule on, 7 to 11 posts stand idle on the mean board while 35 to 43 cars queue, against
--    1.4 to 1.9 idle and 17 to 33 queued on the seven runs before. The line roughly doubled.
--    WHAT IT DOES NOT SAY. That the rule is wrong: it is the arm's reach, on Chase's instruction, and 0824 names the
--    answers (hardware on the side the fleet needs; rule 13). The runs are unpaired, with different seeds, and other
--    changes landed between them (0827 to 0833). The board's idle count before 0835 does not subtract a post a car is
--    on its way to.
--    Not changed here: it is another branch's work in progress. Reported to Chase.

-- ── §1 query: the stored boards against the calendar ──
WITH e AS (
  SELECT e.pass_id, e.sim_run_id, e.board_text::jsonb b FROM ottoq_agent_pass_evidence e
   WHERE e.sim_run_id IN ('14d6eda7-796d-4a48-a5f8-8e786e683032', '1902d13b-8ed0-4855-8e2a-d5f7eddbc71a',
                          'c8913ea2-96fb-4f16-ad89-f39e7115b917') AND e.consulted AND e.board_text LIKE '{%'),
r AS MATERIALIZED (
  SELECT e.pass_id, e.sim_run_id, (e.b ->> 'sim_clock')::timestamptz clk, x.r
    FROM e, jsonb_array_elements(e.b -> 'constraint' -> 'resources') x(r)
   WHERE x.r ->> 'resource' = 'wash_bay' AND (x.r ->> 'idle_with_car_ready')::int > 0),
wb AS MATERIALIZED (
  SELECT b.sim_run_id, lower(b.during) lo FROM ottoq_stall_bookings b JOIN stalls s ON s.id = b.stall_id
   WHERE b.sim_run_id IN (SELECT sim_run_id FROM r) AND s.stall_type::text = 'wash_bay'
     AND s.depot_id = '11111111-1111-1111-1111-111111111111')
SELECT left(r.sim_run_id::text, 8) run, r.pass_id, r.r ->> 'busy_now' busy, r.r ->> 'queued_cars' queued,
       (SELECT round(extract(epoch FROM min(lo) - r.clk) / 60.0, 1) FROM wb
         WHERE wb.sim_run_id = r.sim_run_id AND lo > r.clk) next_wash_starts_in_min      -- sim clock, never now()
  FROM r ORDER BY 1, 2;

-- ── §3: grade stored passes with the deployed function (while a run is live), then read the answer ──
-- SELECT net.http_post(url := 'https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-orchestrator-agent',
--   headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' ||
--     (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'ottoq_anon_key')),
--   body := jsonb_build_object('grade_pass_ids', (SELECT jsonb_agg(pass_id ORDER BY pass_id)
--     FROM ottoq_agent_pass_evidence e WHERE e.consulted AND e.depot_id = '11111111-1111-1111-1111-111111111111'
--       AND e.wake -> 'brief' -> 'subjects' IS NOT NULL AND e.answer IS NOT NULL)), timeout_milliseconds := 30000);
-- then, with the id it returned:
-- SELECT right(p ->> 'model_answered', 22) model, count(*) passes, sum((p ->> 'directives')::int) directives,
--        sum((p -> 'facts' ->> 'directives')::int) naming_a_cut_car, sum((p -> 'facts' ->> 'facts_checked')::int) facts,
--        sum((p -> 'facts' ->> 'facts_wrong')::int) wrong
--   FROM net._http_response r, jsonb_array_elements(r.content::jsonb -> 'passes') p WHERE r.id = :id GROUP BY 1;

-- ── §6 query: the posts on each run's stored boards ──
SELECT left(e.sim_run_id::text, 8) run, to_char(min(e.recorded_at), 'MM-DD HH24:MI') first_board_utc,
       round(avg((p.r ->> 'queued_cars')::numeric), 1) queued, round(avg((p.r ->> 'busy_now')::numeric), 1) busy,
       round(avg((p.r ->> 'idle_now')::numeric), 1) idle,
       round(avg((p.r ->> 'idle_now')::numeric) FILTER (WHERE (p.r ->> 'queued_cars')::int >= 10), 1) idle_with_10_queued
  FROM ottoq_agent_pass_evidence e, jsonb_array_elements(e.board_text::jsonb -> 'constraint' -> 'resources') p(r)
 WHERE e.consulted AND e.board_text LIKE '{%' AND p.r ->> 'resource' = 'posts'
   AND e.depot_id = '11111111-1111-1111-1111-111111111111' AND e.recorded_at > '2026-11-12 00:00+00'
 GROUP BY e.sim_run_id HAVING count(*) >= 12 ORDER BY min(e.recorded_at);
