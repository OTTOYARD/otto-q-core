# R-2 · VDA 5050: which version H1 actually captured, and the actionType vocabulary

**Filed:** 2026-08-22 by Claude Code (build track), during Run 4 / Phase C10.
**Blocking:** removing `PROVISIONAL` markers from `adapters/vda5050/adapter.py`.
The adapter is built and working against H1's capture; these two gaps are what
keep it a draft rather than a specification.

## 1. The version discrepancy — please resolve which is right

`docs/research/H1-intralogistics.md` states in prose that VDA 5050 is at
**"Version 3.0.0 (March 2026)"**, and its FINDINGS paragraph describes 3.0.0
capabilities. But **every JSON example in the same file carries
`"version": "1.3.2"`** — both the `/order` and the `/state` capture.

Both cannot describe the same capture. Which is it?

- If the schemas captured are **1.3.2**, then the 3.0.0 prose describes a version
  we have not seen the schemas for, and we need the 3.0.0 `/order` and `/state`
  schemas before claiming 3.0.0 support.
- If the schemas are **3.0.0** and the `"version"` literals are stale copies from
  older examples, say so and we will treat the captured fields as 3.0.0.

Concretely: **did `/order` or `/state` gain, lose, or rename any field between
1.3.2 and 3.0.0?** If the answer is "no changes to these two messages", that
closes this cleanly and the adapter can name a version with confidence.

The adapter currently reads the wire `version` string, echoes it back, and never
parses it for behaviour — deliberately safe, but it means we cannot yet state a
conformance claim.

## 2. The predefined `actionType` vocabulary

H1 captures the `/order` action structure precisely (`actionId`, `actionType`,
`blockingType` with values NONE/SOFT/SINGLE/HARD, `actionParameters[{key,value}]`)
and gives `loadUnload` and `driveThroughSpeedGate` as examples. It does not
enumerate the predefined `actionType` set.

1. **What is the complete predefined `actionType` vocabulary** in the version
   answered in (1)?
2. **Is there a standard action for charging** — starting a charge, docking to a
   charger, or presenting for a battery swap? If so, exact spelling and its
   `actionParameters`.
3. **How are vendor/custom actions namespaced?** Is there a convention (prefix,
   reverse-DNS, a registry), or is any non-predefined string acceptable?
4. **What does a robot do with an `actionType` it does not recognise** — reject
   the order, report `FAILED`, or ignore the action? This decides whether our
   custom actions fail loudly or silently, which is the difference between a
   usable integration and a dangerous one.

The adapter currently emits OTTO-Q-namespaced custom actions (`ottoq.startCharging`
and friends). That was chosen as the safe direction on the reasoning that an
unrecognised custom action should be rejected loudly, whereas a *guessed* standard
name could silently collide with a real one and trigger the wrong behaviour on a
real robot. Question 4 is what confirms or refutes that reasoning.

## 3. One integration question

H1 says commercial orchestrators (KINEXON, tracio, openmaind) act as a master
controller on top of vendor FMSs using VDA 5050. **Does a VDA 5050 master
controller typically expose the robot `/state` stream to a third party**, or does
it terminate it? Step 3 of our handoff sequence in `adapters/vda5050/adapter.py`
("master → OTTO-Q: /state forwarded, or tapped") is the one step we have marked
`[integration]` rather than owned by a named party, because we do not know whether
it is a supported path, a custom integration, or an MQTT topic subscription
alongside the master.
