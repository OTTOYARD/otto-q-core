# R-22 — Transformer nameplate thermal constants, standard ratings, and the chargers' efficiency curve

**Filed** 2026-11-11 by the build track (Claude Code). **Not blocking**: `db/migrations/0810` is built on labeled
assumptions and measures regardless. This request is to replace each assumption with a sourced value. **Status:** open.

## Why this is being asked

0810 gives the twin depot an electrical one-line and steps each transformer's temperature with the loading guide's
model. Three things in it are typical values, not sourced ones, and each is marked `ASSUMPTION` in
`ottoq_power_nodes.provenance`.

## What I found already (direct search, 2026-11-11), and its limits

- The model's form and two exponents, from Dong et al., *A Data-driven Dynamic Rating Forecast Method and Application
  for Power Transformer Long-term Planning*, IEEE Trans. Power Delivery, 2020, DOI 10.1109/TPWRD.2020.2988921 (author's
  copy https://arxiv.org/pdf/1909.06996, read 2026-11-11): the five steps of the IEEE C57.91 calculation; **n = 0.8**
  for natural oil and natural air cooling (ONAN), 0.9 for forced air (ONAF); **m = 0.8** "for most power transformers";
  the rated rises, the loss ratio R and both time constants "can be provided by the transformer manufacturer"; a
  24-hour equivalent aging factor of 1.0 as the criterion for a day's rating.
- The aging acceleration factor `exp(15000/383 - 15000/(hot_spot + 273))`, 1.0 at 110 C, from a web search's summary of
  standards-based sources (2026-11-11). **I did not read IEEE C57.91 itself** (paywalled).
- ABB Terra HP: 175 kW per power cabinet, two for 350 kW, efficiency >= 94% at full load, power factor >= 0.97, from a
  reseller's sheet only (InCharge v1.5,
  https://inchargeus.com/wp-content/uploads/2026/07/InCharge_Specsheet_Terra-High-Power_v1.5.pdf, read 2026-11-11).
- Nashville Electric Service lists 13,800 V (3-wire, 3-phase) as a standard primary voltage
  (https://nespower.com/builders-and-developers, read 2026-11-11).

## The questions

1. **For a 2,500 kVA, 13.8 kV to 480Y/277 V, liquid-filled, 65 C-rise pad-mounted transformer** (name the maker and
   the data sheet): rated top-oil rise over ambient (C), rated hot-spot rise over top oil (C), no-load loss (kW), load
   loss at rated load (kW), top-oil time constant (minutes), winding time constant (minutes). 0810 assumes 55, 25,
   total loss 1.0% of rating split 1:5, 180 and 5.
2. **Which three-phase pad-mounted ratings between 300 and 5,000 kVA are standard with a 480 V secondary**, by IEEE
   C57.12.34 or a maker's catalog (URL)? 0810 assumes 300, 500, 750, 1000, 1500, 2000, 2500, 3000, 3750.
3. **IEEE C57.91's limits, by clause number**: the hot-spot and top-oil temperatures for normal life expectancy
   loading, planned loading beyond nameplate and short-time emergency loading, and the normal insulation life in hours.
   0810's right-size reading uses 110 C and an aging factor of 1.0 only.
4. **ABB's own data sheet for the Terra HP power cabinet** (not a reseller's): efficiency at 25%, 50%, 75% and 100% of
   rated output, power factor, AC input current at 480 V, and standby draw in kW with no car connected. 0810 holds 94%
   at every load and counts no standby draw.
5. **NEC (NFPA 70) 2023, 625.42**: the text that lets a service and feeder be sized to the maximum load an energy
   management system permits, and the 125% continuous-load rule it otherwise applies, quoted with the edition. The
   search found paraphrases only. This matters after the build, when the depot's ceiling is set from what it drew
   (rule 13).
6. **Nashville Electric Service, Electric Service Guidelines (v21, effective 2026-03-09)**: for a customer-owned
   primary-metered service at 13.8 kV, the largest load NES serves at that voltage before requiring 23.9 kV or a
   dedicated substation, with the section number.

Each answer: the value, its unit, the document and edition or date, and the URL.
