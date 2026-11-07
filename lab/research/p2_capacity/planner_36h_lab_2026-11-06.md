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
**$73 a day** on no battery. Held to the day plan's own 6 PM charge, perfect foresight saves $334 (the table above), so
the day plan takes 22%; free to choose the battery's charge at 6 PM and at the end, both priced at the replacement cost as
every plan is below, it saves $495 ($1,128.94 a day), and the day plan takes 15%. On the 12-hour days it took half. The
600 kWh call reserve costs perfect foresight nothing on any of the six.

### The planner in steady state (read 2026-11-06 by 11:08 UTC; the planner days ran 10:21-11:07 UTC)

Every bill over the window at the base day's states: each plan charged for the stored energy it brought in at 6 PM above the
base day's and credited for what it left above the base day's end, at the day plan's replacement cost ($0.070 a kWh;
`planner_table.py --charge-start`), and perfect foresight free to choose both on the same terms (`bound_energy.py`'s
`perfect_foresight_free_start`). The planners fill the battery on day 1 for the evening they know is billed and open the
window at 90% (2,689-2,838 kWh) where the day plan opens it at 35-53%; checked on two seeds, the energy they brought in cost
them $95.37 and $133.82 on day 1 against $93.74 and $116.11 charged here, and their day-1 peaks were lower than the day
plan's on all four seeds read (171717: 820 against 1,032 kW), so filling up added no demand charge. `b36fc` is the day plan
with G524's forecast fix (`whatif_dayplan_on_charger.sql`).

| seed | day plan | no battery | another seed's shape | learned + q80 band | day plan, G524 fix | perfect foresight | PF holding the reserve |
|---|---:|---:|---:|---:|---:|---:|---:|
| 18 |
| 171717 | 1512.83 (1000, 23:35) | 1683.91 | 1385.41 (811, 12:30) | 1348.48 (748, 23:20) | 1523.18 (1016, 23:35) | 1119.34 | 1119.34 |
| 424242 | 1539.61 (1019, 23:00) | 1610.88 | 1377.38 (755, 12:10) | 1343.89 (711, 11:45) | 1544.15 (1027, 23:00) | 1141.76 | 1141.76 |
| 616161 | 1696.98 (1160, 22:45) | 1701.86 | 1458.80 (800, 12:30) | 1396.57 (704, 23:40) | 1697.58 (1163, 22:45) | 1212.05 | 1212.05 |
| 818181 | 1576.41 (1066, 22:45) | 1617.14 | 1293.62 (636, 09:55) | 1291.43 (628, 23:40) | 1552.94 (1033, 22:50) | 1129.14 | 1129.14 |
| 919191 | 1486.24 (1018, 22:50) | 1529.85 | 1316.90 (753, 12:30) | 1296.10 (730, 22:30) | 1491.77 (1026, 22:50) | 1051.27 | 1051.27 |
| 373737 | 1491.76 (975, 22:15) | 1601.00 | 1337.75 (718, 17:05) | 1271.25 (632, 23:40) | 1501.56 (990, 22:15) | 1120.10 | 1120.10 |

| plan | mean bill | saving on the day plan | seeds beating the day plan | seeds beating the shape | share of the gap to perfect foresight closed |
|---|---:|---:|---:|---:|---:|
| the day plan as it runs | $1,550.64 | | | | 0% |
| the day plan with G524's forecast fix | $1,551.86 | -$1.23 | 1 of 6 | 0 of 6 | 0% |
| the planner on another seed's 36-hour load | $1,361.64 | $188.99 | 6 of 6 | | 45% |
| **the planner on the learned forecast + its 80th-percentile miss** | **$1,324.62** | **$226.02** | **6 of 6** | **6 of 6** | **54%** |
| perfect foresight, free to choose the battery's charge at both ends | $1,128.94 | | | | |

Every planner day kept every car-facing line of its base day's scorecard (no call came on any of the six 36-hour days).

## What it says

1. **In steady state the planner is worth more, not less: $226 a day on the day plan, on all six seeds ($164-300), against
   $129 on the 12-hour days.** The learned band beats a copied day's load on all six ($37 a day). The day plan's bill is set
   by the evening's wave of returns (975-1,160 kW at 10:15-11:35 PM); the planner, knowing the evening is billed, fills the
   battery by 6 PM and holds its billed half hour to 628-748 kW (in the late evening on five seeds, at 11:45 AM on 424242). Against no battery the planner saves $299 a day where the day plan
   saves $73.
2. **G524's forecast fix is worth nothing here either** (-$1.23 a day, 1 of 6 seeds). A truer forecast inside the day plan
   does not change how it spends the evening (it charges into the wave when the load is under its level and raises the level
   when a spike comes, seed 424242: 973.5 kW to 1,191-1,229 kW); a plan that budgets the battery over the whole evening does.
   G524 stays a measured error with no cost of its own; the build is the planner.
3. **The build, priced.** On the twin's demand model the planner is worth about $226 a day at one depot, some $6,800 a
   month with each day billed for its own peak (the tariff bills the month's highest half hour; the planner's billed half hour
   is 252-456 kW under the day plan's on every seed, so the month's would be too). It is what production's optimizer
   already is (`ottoq-intelligence/app/optimizers/energy_mpc.py`: a load forecast and a per-step uncertainty band), fed
   what the lab planner is fed: the learned forecast refit nightly from the depot's own days (an estimate, rule 10), its
   80th-percentile miss as the band, the tariff, the billed peak so far and the call reserve (a per-step floor the service
   does not take yet), with plan-follow (0799) on. The cars are never touched: the battery only moves the grid draw.

Lab days, 116 cars, one scenario, six seeds, a 36-hour run with the billing period from 6 PM (`bess_plan_bill_from_min`
= 720 is a lab value above the dial's catalogued 0-240): a reading of the method on the twin, not a forecast of
production's bill.
