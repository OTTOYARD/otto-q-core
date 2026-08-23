# R-3 — Battery degradation coefficients for a depot scheduling objective

**Filed:** 2026-08-23
**For:** Hermes
**Blocks:** `docs/DEGRADATION_MODEL_PROPOSAL.md` §3; any absolute degradation claim in a
comparison or customer-facing artifact.

## Why this is needed

We are adding pack degradation as a term in the policy-comparison objective, so that a
scheduler which charges gently, parks at a moderate state of charge, and avoids charging cold
or hot packs can be shown to beat one that maximises throughput. The **functional form** is
settled (two-term calendar + cycle, see the proposal). The **coefficients are not**, and no
dataset we hold contains battery health data — ACN-Data has none, and is workplace L2 duty
cycle besides.

We will not invent these. Until this request returns, every absolute fade figure is labelled
`ASSUMPTION — pending R-3`.

## The model we are parameterising

```
capacity_fade = calendar + cycle

calendar = k_cal · exp(−Ea / (R · T_pack)) · f_soc(SoC_parked) · sqrt(t_hours)
cycle    = k_cyc · Ah_throughput · g_rate(C_rate) · h_temp(T_pack)
```

## Questions — answerable, with units

Please answer per chemistry where the literature distinguishes them. Our fleet mixes **NMC**
(Waymo I-Pace class, Zoox) and we expect **LFP** in yard tractors.

1. **Calendar ageing activation energy `Ea`** — value and units (kJ/mol), and the reference
   temperature the fitted `k_cal` assumes.
2. **`f_soc(SoC)`** — the storage-SoC dependence of calendar fade. Ideally a table of relative
   fade rate at 30 / 50 / 70 / 80 / 90 / 100% SoC, normalised to one of them. State which.
3. **Time exponent** — is `sqrt(t)` (SEI-limited) the accepted form for the first 1–3 years, or
   is a different exponent standard? Give the exponent.
4. **`g_rate(C_rate)`** — relative cycle fade at 0.1C / 0.5C / 1C / 1.5C / 2C charge rate,
   normalised to 1C. Note whether the source separates charge rate from discharge rate; we care
   mainly about **charge**.
5. **`h_temp(T)`** — relative cycle fade at pack temperatures −10 / 0 / 10 / 25 / 40 / 50 °C.
   **We specifically need the cold end**, because lithium plating during cold fast-charge is a
   lever our scheduler can actually pull (delay or pre-warm) and we do not want to model it as
   merely "less bad than hot".
6. **`k_cal` and `k_cyc` magnitudes** — enough to produce a plausible absolute number, e.g.
   expected % capacity fade for a pack cycled ~1 full equivalent cycle/day at 25 °C, 1C charge,
   parked at 90%, over 12 months. A single anchor point is sufficient; we can scale from it.
7. **Is there a published depot/fleet-scale study** quantifying capacity fade differences
   attributable to *charging strategy* (e.g. delayed charging, SoC-limited charging, thermal
   pre-conditioning) rather than to cell chemistry? A single credible citation with an effect
   size would be worth more than all of the above for our purposes.

## Not needed

- Cell-level electrochemical models. We need engineering-level coefficients usable in a
  scheduling objective, not a P2D simulation.
- Discharge-side detail beyond what falls out of question 4.

## Answer format

`docs/research/answers/R-3-battery-degradation-coefficients.md`, with each numbered question
answered in order, every figure carrying its units and its source, and **`NOT FOUND` written
where the literature does not give a defensible number** — a gap we know about is worth more
than a plausible-looking value we cannot trace.
