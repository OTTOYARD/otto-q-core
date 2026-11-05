# Would the agent's orders help owners if each owner kept its places? (G512 §4, answered: G515)

Rule 14 lets a rule added for the depot's sake "trade places only among one owner's own cars" (0781's exit key does).
0479 §4 asked whether the agent's charge orders, projected that way, would be fair by construction and then only need
judging per owner. This replays all 370 graded decisions with the projection.

| file | what |
|---|---|
| `projection.py` | for each decision: the kernel's line at the order's moment (the order in which the cars present first get a seat in the kernel's expected future), each owner keeping the positions its cars hold, re-ranked inside them by the agent; the projected order and the kernel's own line, both as explicit orders through the same path, rolled forward in the check's 12 futures and in hindsight; each owner compared (`-v worker`: `--worker N --workers 3`, one per core) |
| `report.sql` | the classes in hindsight, side by side with the orders as given (0478), the futures, a fair referee's takes |
| `results_2026-11-05.txt` | the output |

Run in a clone of the lab that holds the research schema of `lab/research/p0_referee_per_owner/` and
`p1_referee_owner_futures/` (here `ottoq_lab_proj`, cloned from `ottoq_lab` on 2026-11-05).

## What it found (2026-11-05 22:02 UTC = 4:02 PM CT; G515)

| in hindsight, against the kernel's own line | projected | as given (0478) |
|---|---:|---:|
| good for every owner | 25 | 35 |
| trades one owner for another | 188 | 250 |
| bad for every owner | 46 | 45 |
| no owner changes | 111 | 40 |

No projected order was good for every owner in more than 7 of the check's 12 futures; a referee that requires it in 8 or
more takes none. The 22 orders the projection leaves as the kernel's read no change for every owner. A first pass that
compared the projection with the kernel's own unordered path read 9 of those 22 as changed: the two paths differ, so it
was discarded and the comparison made like for like.

Why: the posts are shared. Which of an owner's cars takes a seat decides when that post frees again (charges differ in
length), which moves every car after it, whoever owns it. Keeping each owner's places keeps the order fair, not each
owner's outcome. So the agent's per-tick orders stay a background challenger (0795), and a within-owner rule like 0781's
exit key should be measured owner by owner before its places are read as a guarantee.
