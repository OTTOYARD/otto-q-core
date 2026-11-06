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

### The day plan in steady state (base days read 2026-11-06 by 10:22 UTC)

| seed | battery at 6 PM day 1 -> 6 PM day 2, kWh | day plan (peak kW, the half hour's end CT) | no battery, same end charge | perfect foresight |
|---|---:|---:|---:|---:|
| 171717 | 1,349 -> 2,704 | $1,512.83 (1,000, 11:35 PM) | $1,683.91 (1,271, 9:35 PM) | $1,271.53 (696, 6:30 PM) |
| 424242 | 1,084 -> 2,704 | $1,539.61 (1,019, 11:00 PM) | $1,610.88 (1,140, 11:00 PM) | $1,296.27 (707, 6:30 PM) |
| 616161 | 1,087 -> 2,708 | $1,696.98 (1,160, 10:45 PM) | $1,701.86 (1,189, 10:45 PM) | $1,392.10 (767, 7:00 PM) |
| 818181 | 1,175 -> 2,702 | $1,576.41 (1,066, 10:45 PM) | $1,617.14 (1,144, 10:35 PM) | $1,296.66 (716, 6:40 PM) |
| 919191 | 1,378 -> 2,712 | $1,486.24 (1,018, 10:50 PM) | $1,529.85 (1,104, 9:35 PM) | $1,190.97 (626, 6:30 PM) |
| 373737 | 1,586 -> 2,689 | $1,491.76 (975, 10:15 PM) | $1,601.00 (1,162, 9:35 PM) | $1,295.32 (727, 6:35 PM) |
| **mean** | | **$1,550.64** | **$1,624.11** | **$1,290.48** |

In steady state the bill is not the morning's. On every seed the day plan's billed half hour is between 10:15 and 11:35 PM,
in the evening's wave of returns (seed 424242: 42 visits opened in the 9 PM hour, standard and immediate dispatches, then
32 at 10 PM, 23 of them overnight holds), when charging spikes to 700-1,200 kW (1,135 kW at 9:15 PM, 1,204 kW at 10:45 PM). The battery stands near 35% then, and the day plan spends the evening alternating between charging it from
the grid (`plan_charge`, 40-180 kW into the spikes) and defending a level near 1,000 kW (`plan_defend_level`). It saves
**$73 a day** on no battery, 22% of what perfect foresight saves ($334); on the 12-hour days it saved half. The 600 kWh
call reserve costs perfect foresight nothing on any of the six.

RESULTS_PENDING
