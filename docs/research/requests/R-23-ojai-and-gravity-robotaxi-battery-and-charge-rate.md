# R-23 — Waymo Ojai and Lucid Gravity robotaxi: battery, charge rate, inlet

Filed 2026-11-14 by Claude Code. Not blocking: migration 0833 is applied with the labelled assumptions below.

`db/migrations/0833` put 24 Waymo Ojais and 6 Lucid Gravity robotaxis in the twin depot's fleet. Four of their facts
are assumptions. Please answer each with the value, the date it applies to, and a source URL.

## Waymo Ojai (built by Zeekr)

1. Peak DC fast-charge power, kW. Assumed: 200. Found: "800 V", "faster than the I-PACE", no figure
   (https://www.arenaev.com/waymo_launches_first_purposebuilt_robotaxi-news-5924.php, read 2026-11-14).
2. Usable and gross battery energy, kWh. Used: 93 gross (https://carnewschina.com/?p=265625). One earlier report said
   76 kWh LFP (evdances.com). Which is the US vehicle's, and is there a filing (NHTSA) that states it?
3. Charge inlet: connector (CCS1 or NACS), which side of the car, distance from the nose or tail in metres, height in
   metres. Assumed since 0824: CCS1, left rear quarter, 1.856 m behind the car's middle, 0.95 m high.
4. A DC charge curve (power against state of charge), if one is published or measured.

## Lucid Gravity as the Lucid, Uber and Nuro robotaxi

5. Which battery pack the robotaxi carries, kWh. Assumed: the Grand Touring's 123 kWh gross
   (https://evkx.net/models/lucid/gravity/gravity_gt-s/).
6. Its peak DC power, kW, on a 1,000 V charger and on a 500 V charger. Assumed: 400 kW (https://gcn.com/?p=22469
   reports 400 kW on 1,000 V and up to 225 kW on 500 V).
7. Who owns and who operates the vehicles in the program (Uber, a fleet partner, Nuro, Lucid). The twin names the
   owner 'Uber Robotaxi Nashville'; that is a placeholder.
