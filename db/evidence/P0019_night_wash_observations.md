# P0019 — first observed execution of the 0018 wash paths

Instance probe before any run: 10x `count(*) from generate_series(1,1000000)` in one
transaction -> min 190.0 ms / median 190.5 ms / max 192.6 ms (spread 2.6 ms). Healthy;
no multi-second outliers, so timings below are not contaminated.

## How night was crossed (this is the part that never worked before)

`ottoq_start_demo_run` forces `ottoq_set_playback(run,'live',speed)`, and live playback
advances the sim clock by REAL elapsed x speed_x with speed_x hard-clamped to 3.0. One
real hour therefore buys three sim hours, so a demo run physically could not reach a
night window. That — not the wash gate — is why every prior run stayed inside 09:00-19:00.

Fix used: after starting, switch the run back to `fixed` playback
(`ottoq_set_playback(run,'fixed',5)`). In fixed mode
`ottoq_sim_advance_tick_world` advances `tick_interval_seconds * time_scale / 60`
= 30 * 60 / 60 = **30 sim-minutes per tick**, and the metronome paces ticks at
`6.0/speed_x` seconds. A full 24-sim-hour day = 48 ticks.

Start time is seed-derived: `ottoq_start_demo_run` sets the start minute-of-day to
`abs(hashtext(seed::text)) % 1440`. Seeds were chosen so the run *starts* in the evening:

  seed 6666   -> offset 1054 -> start 17:34
  seed 131313 -> offset 1138 -> start 18:58

Night in the gate is **America/Chicago local** hour >= 20 or < 6 (see below), i.e.
01:00-11:00 UTC on the sim clock.

## Time-base defect in the night gate (real, currently dormant)

`twin.ottoq_sim_generate_service_manifest`:

    v_hour    := EXTRACT(HOUR FROM (v_clock AT TIME ZONE 'America/Chicago'))::int;
    v_sim_day := (v_clock::date - DATE '2020-01-01');

The night test is Chicago-local, the rotation day is the **UTC** date. For
America/Chicago the whole night window (01:00-11:00 UTC) falls inside one UTC date, so
the rotation day is well defined by luck, not by construction. At a depot whose local
offset is near zero the night would straddle midnight UTC and a single night would be
split across two rotation groups. Not a blocker for this depot; it is a latent seam.

## Rider-flag due time is anchored to the PRE-REBASE start

`ottoq_run_boot_draw` computes `rider_flag_due_at = sim_clock_start + rand*window_h`,
but it runs inside `ottoq_sim_run_scenario`, i.e. BEFORE `ottoq_start_demo_run` rebases
`sim_clock_start` to the seed-derived time of day. Run A started at 17:34 yet produced a
flag due at 13:05 — already in the past at tick 0. The 14-hour daytime flag window is
therefore not aligned with the run's actual window.
