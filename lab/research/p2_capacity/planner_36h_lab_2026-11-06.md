# The battery planner in steady state: 36-hour days billed from 6 PM (research lab, 2026-11-06)

**Question.** The 12-hour study (`planner_0801_lab_2026-11-06.md`) found a planner on the learned forecast and its
80th-percentile band saving $129 a day on the day plan, and found what was left to be the battery's charge at 6 AM: a lab
day starts at 6 AM with the whole fleet at the depot at once (a boot artifact) and the battery as the boot left it, so no
plan can refill it overnight for that surge. What is the planner worth when it can?

## Method

- **Days.** `normal_day`, 116 cars, 36 hours from 6 AM day 1 to 6 PM day 2 (432 ticks of 5 minutes), seeds 171717, 424242,
  616161, 818181, 919191 and 373737, on `ottoq_lab_0801` (a seed's cars reproduce).
- **The bill** covers the last 24 hours only, 6 PM day 1 to 6 PM day 2 (`bound_energy.py --window-start-h 12`): the
  evening, the night, the next morning's surge and the day, with the battery as it stood at 6 PM. Each plan's billing
  period starts there too, so neither treats day 1's 6 AM start-up peak as already paid for the next day: the day plan's
  ratchet through `bess_plan_bill_from_min` = 720 (a lab value: the dial is catalogued 0-240 and its reader does not clamp),
  the planner through a second billing period from the same minute (`--battery-lp-bill-from-min 720`; each period pays
  for its own highest half hour).
- **Plans**, each against its seed's base day car for car: the day plan as it runs (`b36`); the planner on the next
  seed's 36-hour load before the battery, step by step (`p36shape`); the planner on the learned forecast plus its
  80th-percentile out-of-sample miss for the next four hours and the shape beyond (`p36q80`), the forecast fitted on the
  other five seeds' 36-hour days (every hour of day and night).
- **Bills** at the base day's end-of-day charge, no battery at the same charge, perfect foresight over the window (ending
  no emptier than the base day), as in the 12-hour study (`planner_table.py --base b36 --arms p36shape,p36q80 --window 12`).

## Results

RESULTS_PENDING
