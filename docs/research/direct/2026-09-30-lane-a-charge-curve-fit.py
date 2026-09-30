#!/usr/bin/env python3
"""Fit the twin's fast-charge curves to public data. Reproduces every number in
2026-09-30-lane-a-service-time-calibration.md, section 2.

Data: "Digitized Electric Vehicle Fast-Charging Profiles by Model (Power vs SOC/SOE, CSV Format) - Version 1",
figshare, CC BY 4.0, doi:10.6084/m9.figshare.30570653.v1, published 2025-11-08. 99 power-vs-state-of-charge curves
digitized from Fastned and InsideEVs (accessed by the authors Feb-Jul 2025). Downloaded here by URL, never committed.

Integration matches public.ottoq_estimate_charge_minutes exactly: 1% steps, the power at the step's starting charge,
minutes = (1% of usable kWh) / kW * 60. Nominal conditions: 25 C, state of health 100%, a 350 kW charger.

Usage: python3 2026-09-30-lane-a-charge-curve-fit.py [path/to/main.csv]
"""
import collections
import csv
import statistics as st
import sys
import urllib.request

MAIN_CSV_URL = "https://ndownloader.figshare.com/files/59409860"  # main-data-fastcharge-profile-het.csv
MODEL_Y_FILE = "Tesla Model Y Long Range_300kW_SOC vs charge speed"
SOC = list(range(0, 101, 5))


def load(path):
    rows, usable = collections.defaultdict(list), {}
    with open(path, encoding="utf-8-sig") as f:
        for r in csv.DictReader(f):
            try:
                s, p = float(r["soe.percent"]), float(r["power.kW"])
            except ValueError:
                continue
            rows[r["filename"]].append((s, p))
            usable[r["filename"]] = float(r["usable_pack.kWh"] or "nan")
    for k in rows:
        rows[k].sort()
    return rows, usable


def interp(pts, s):
    if s <= pts[0][0]:
        return pts[0][1]
    for (a, pa), (b, pb) in zip(pts, pts[1:]):
        if a <= s <= b:
            return pa + (pb - pa) * (s - a) / (b - a) if b > a else pa
    return pts[-1][1]


def rate(c, s, kwh, vmax, charger=350.0):
    lo = int(s // 5) * 5
    hi = min(lo + 5, 100)
    cs = c[lo] if hi == lo else c[lo] + (c[hi] - c[lo]) * (s - lo) / 5
    return min(charger, vmax, kwh * cs)


def minutes(c, kwh, vmax, a, b):
    t, s = 0.0, a
    while s < b:
        t += (kwh / 100.0) / rate(c, s, kwh, vmax) * 60.0
        s += 1
    return round(t, 1)


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "main.csv"
    try:
        open(path).close()
    except OSError:
        urllib.request.urlretrieve(MAIN_CSV_URL, path)
    rows, usable = load(path)

    # Profiles measured from <=12% to >=98%: the only ones that show the last 20% of a charge.
    full = [k for k, p in rows.items() if p[0][0] <= 12 and p[-1][0] >= 98]

    def tail(rel):
        return {s: st.median(interp(rows[k], min(s, rows[k][-1][0])) / interp(rows[k], rel) for k in full)
                for s in (80, 85, 90, 95, 100) if s >= rel}

    tail80, tail90 = tail(80), tail(90)
    ratio = sorted(minutes_profile(rows[k], usable[k], 80, 100) / minutes_profile(rows[k], usable[k], 10, 80)
                   for k in full)
    q = st.quantiles(ratio, n=4)
    print(f"{len(rows)} profiles, {len(full)} measured from <=12% to >=98%")
    print(f"80-100% time / 10-80% time: p25 {q[0]:.2f}, median {st.median(ratio):.2f}, p75 {q[2]:.2f}")
    print("tail, power relative to power at 80%:", {s: round(v, 3) for s, v in tail80.items()})

    # 1. Tesla Model Y Long Range: its own measured curve (Fastned), in kW per usable kWh (C), 75.0 kWh usable.
    my, e_y = rows[MODEL_Y_FILE], 75.0
    c_y = {s: (interp(my, max(s, my[0][0])) / e_y if s <= 90 else interp(my, 90) / e_y * tail90[s]) for s in SOC}

    # 2. Typical battery: the median kW per usable kWh over every profile that covers that state of charge.
    c_g = {s: st.median(interp(p, s) / usable[k] for k, p in rows.items()
                        if p[0][0] <= max(s, 12) and p[-1][0] >= min(s, 98) and usable[k] == usable[k]) for s in SOC}

    # 3. Jaguar I-PACE: no measured curve is public as data. Hold the car's 104 kW to 50%, taper linearly to a fitted
    #    value at 80%, then the median tail. The one fitted number makes 10-80% equal EV Database's published 45 min.
    e_i, v_i = 84.7, 104.0

    def ipace(c80):
        c = {}
        for s in SOC:
            if s <= 50:
                c[s] = 3.0  # above the car's own cap; the cap (104 kW) binds
            elif s <= 80:
                c[s] = v_i / e_i + (c80 - v_i / e_i) * (s - 50) / 30
            else:
                c[s] = c80 * tail80[s]
        return c

    lo, hi = 0.1, 1.2
    for _ in range(60):
        mid = (lo + hi) / 2
        lo, hi = (mid, hi) if minutes(ipace(mid), e_i, v_i, 10, 80) > 45.0 else (lo, mid)
    c_i = ipace((lo + hi) / 2)
    print(f"I-PACE fitted: {(lo + hi) / 2:.3f} kW per kWh at 80% ({(lo + hi) / 2 * e_i:.1f} kW)")

    print(f"\n{'battery':34s} {'10-80':>6s} {'80-100':>7s} {'20-100':>7s}")
    for name, c, e, v in (("Tesla Model Y LR (75 kWh, 250 kW)", c_y, 75.0, 250.0),
                          ("Jaguar I-PACE (84.7 kWh, 104 kW)", c_i, e_i, v_i),
                          ("Zoox (133 kWh, 100 kW), typical", c_g, 133.0, 100.0),
                          ("Zoox (133 kWh, 200 kW), typical", c_g, 133.0, 200.0)):
        print(f"{name:34s} {minutes(c, e, v, 10, 80):6.1f} {minutes(c, e, v, 80, 100):7.1f} {minutes(c, e, v, 20, 100):7.1f}")

    print("\nkW per usable kWh at 0, 5, ..., 100% (the tables the migration carries):")
    for name, c in (("model_y_lr_measured", c_y), ("ipace_fitted", c_i), ("typical_median", c_g)):
        print(name, [round(min(c[s], 3.0), 3) for s in SOC])


def minutes_profile(pts, kwh, a, b):
    t, s = 0.0, a
    while s < b:
        t += (kwh / 100.0) / max(interp(pts, min(s + 0.5, pts[-1][0])), 0.5) * 60.0
        s += 1
    return t


if __name__ == "__main__":
    main()
