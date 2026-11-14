import assert from "node:assert/strict";
import test from "node:test";

import {
  checkDirectiveFacts,
  factsReason,
  newFactsTally,
  tallyFacts,
} from "../edge-functions/_shared/agent_directive_facts.ts";
import { WAKE_BRIEF_PROMPT } from "../edge-functions/_shared/agent_wake_brief.ts";

// edge function v34 (db/checks/0494, G548): what a directive says about a car whose charge a fault cut, against the
// brief the model was sent. The cases marked REAL are directives and brief rows read from ottoq_agent_pass_evidence
// on 2026-11-14 (passes 10304, 10317, 10330 and the three samples of the primary model).

const BRIEF = {
  v: 1,
  reasons: ["charger_fault"],
  subjects: {
    charges_cut_by_fault: { count: 4, cars: [
      { car: "Waymo-AV-024", new: false, post: "NASH-DCFC-STALL-28", state: "staged_awaiting_service", min_ago: 72,
        soc_now: 97, cut_at_soc: 97, target: 100, waiting_in_line_pos: 18 },
      { car: "Waymo-AV-039", new: false, post: "NASH-DCFC-STALL-09", min_ago: 107, soc_now: 98, cut_at_soc: 98,
        waiting_in_line_pos: 21 },
      { car: "Zoox-AV-076", new: true, post: "NASH-DCFC-STALL-13", charging_again_on: "NASH-DCFC-STALL-03",
        again_after_min: 1, min_ago: 2, cut_at_soc: 90, target: 100 },
      { car: "Waymo-AV-003", new: true, post: "NASH-DCFC-STALL-10", charging_again_on: "NASH-DCFC-STALL-08",
        again_after_min: 1, min_ago: 1, cut_at_soc: 55, target: 100 }] },
    chargers_faulted: { count: 1, chargers: [{ post: "NASH-DCFC-STALL-13", new: true }] },
    past_contract_wait: { longest: [{ car: "Tesla-AV-060" }, { car: "Waymo-AV-024" }] },
    emergencies: [],
  },
};

const check = (text, brief = BRIEF) => checkDirectiveFacts(brief, text);

test("no brief, no text, no cut car in the brief or none named: nothing is checked", () => {
  assert.deepEqual(check("anything", null), { cars: 0, checked: 0, wrong: [] });
  assert.deepEqual(check(""), { cars: 0, checked: 0, wrong: [] });
  assert.deepEqual(check(undefined), { cars: 0, checked: 0, wrong: [] });
  assert.deepEqual(check("Waymo-AV-024 waits", { v: 1, subjects: {} }), { cars: 0, checked: 0, wrong: [] });
  assert.deepEqual(check("NASH-DCFC-STALL-13 faulted; the wall is the posts, 40 cars queued."), { cars: 0, checked: 0, wrong: [] });
  // a longer name that contains a cut car's name is not that car
  assert.equal(check("Waymo-AV-0244 at pos 3").cars, 0);
});

test("REAL, the primary model: a cut charge described from the brief has nothing wrong", () => {
  const a = check("Charger fault at NASH-DCFC-STALL-13 (fault.session_aborted_other) cut Zoox-AV-076 charge at 90% " +
                  "(target 100%). Car now charging again on NASH-DCFC-STALL-03.");
  assert.deepEqual(a, { cars: 1, checked: 1, wrong: [] });
  const b = check("New charger fault at NASH-DCFC-STALL-10 (fault.thermal_emergency) 1 min ago. Waymo-AV-003 charge cut " +
                  "at 55% (target 100%) now charging again on NASH-DCFC-STALL-08 after 1 min. Verify stall-10 repair " +
                  "and that Waymo-AV-003 reaches full target.");
  assert.equal(b.cars, 1);
  assert.deepEqual(b.wrong, []);
  assert.ok(b.checked >= 2);                                    // the post it charges on again, and the cut SoC
});

test("REAL, the first fallback: minutes copied from its last answer, and a post the brief never gave the car", () => {
  const a = check("FAULT NASH-DCFC-STALL-28: Waymo-AV-024 charge cut 46 min ago, waiting in line pos 21. Fault " +
                  "connector_cable. Car still waiting, battery 97%, target 100. Check charging again on " +
                  "NASH-DCFC-STALL-14 within 6 min.");
  assert.equal(a.cars, 1);
  assert.deepEqual(a.wrong, [
    { car: "Waymo-AV-024", field: "post", said: "NASH-DCFC-STALL-14", brief: "NASH-DCFC-STALL-28" },
    { car: "Waymo-AV-024", field: "line_pos", said: "21", brief: "18" },
    { car: "Waymo-AV-024", field: "min_ago", said: "46", brief: "72" }]);
  assert.equal(a.checked, 3);
  assert.equal(factsReason(a), "contradicts the brief: Waymo-AV-024 post said NASH-DCFC-STALL-14, the brief has " +
    "NASH-DCFC-STALL-28; Waymo-AV-024 line_pos said 21, the brief has 18; Waymo-AV-024 min_ago said 46, the brief has 72");
});

test("the same directive with the brief's own numbers is right, and minutes are right within 3", () => {
  const ok = "FAULT NASH-DCFC-STALL-28: Waymo-AV-024 charge cut 72 min ago, waiting in line pos 18. Car still " +
             "waiting, battery 97%, target 100. Check charging again on available DCFC.";
  assert.deepEqual(check(ok), { cars: 1, checked: 2, wrong: [] });
  assert.deepEqual(check(ok.replace("72 min", "75 minutes")).wrong, []);
  assert.deepEqual(check(ok.replace("72 min", "69 min")).wrong, []);
  assert.equal(check(ok.replace("72 min", "76 min")).wrong[0].field, "min_ago");
  assert.equal(check(ok.replace("72 min", "68 min")).wrong[0].field, "min_ago");
});

test("each car is read in its own words: a list of cars does not lend one car's numbers to another", () => {
  // REAL shape (pass 8411): a contract-wait list, each car with its own place
  const list = "Three cars past contract wait: Tesla-AV-060 (pos 3, 61 min wait, 22% SoC), Waymo-AV-024 (pos 18, 48 min " +
               "wait, 97% SoC), Waymo-AV-039 (pos 21, 45 min wait).";
  assert.deepEqual(check(list), { cars: 2, checked: 2, wrong: [] });
  const swapped = list.replace("Waymo-AV-024 (pos 18", "Waymo-AV-024 (pos 3").replace("Tesla-AV-060 (pos 3", "Tesla-AV-060 (pos 18");
  assert.deepEqual(check(swapped).wrong, [{ car: "Waymo-AV-024", field: "line_pos", said: "3", brief: "18" }]);
  // what is said before a car's name (the faulted post, another car's post) is not held against it
  assert.deepEqual(check("NASH-DCFC-STALL-13 faulted. Zoox-AV-076 is charging again on NASH-DCFC-STALL-03. " +
                         "Waymo-AV-003 is charging again on NASH-DCFC-STALL-08.").wrong, []);
  // and a pairing with the wrong post is found (the fallback's replay of pass 9078 did this)
  const wrong = check("Zoox-AV-076 is charging again on NASH-DCFC-STALL-08. Waymo-AV-003 is charging again on NASH-DCFC-STALL-03.");
  assert.deepEqual(wrong.wrong.map((w) => [w.car, w.said]),
                   [["Zoox-AV-076", "NASH-DCFC-STALL-08"], ["Waymo-AV-003", "NASH-DCFC-STALL-03"]]);
});

test("a place in line said of a car that is charging again is wrong; a cut SoC is exact; a post is read by its number", () => {
  assert.deepEqual(check("Zoox-AV-076 waits at pos 4.").wrong,
                   [{ car: "Zoox-AV-076", field: "line_pos", said: "4", brief: "not in line" }]);
  assert.equal(check("Zoox-AV-076 was cut at 91% by a fault.").wrong[0].field, "cut_soc");
  assert.deepEqual(check("Zoox-AV-076 was cut by a fault at 90 %.").wrong, []);
  assert.deepEqual(check("zoox-av-076 charging again on nash-dcfc-stall-3.").wrong, []);      // case and a bare number
  assert.equal(check("Zoox-AV-076 charging again on NASH-DCFC-STALL-30.").wrong.length, 1);   // 30 is not 3 or 03
  assert.deepEqual(check("Zoox-AV-076 charging again on NASH-DCFC-STALL-031.").wrong.length, 1);
  // a percentage that is not a cut SoC, and "after N min", are not facts this reads
  assert.deepEqual(check("Zoox-AV-076 is at 93% now, charging again after 1 min, 40% of posts busy.").wrong, []);
});

test("a car listed twice (two charges cut) is right by either row, and a brief with no posts reads no post", () => {
  const twice = { v: 1, subjects: { charges_cut_by_fault: { cars: [
    { car: "A-1", post: "P-01", min_ago: 90, cut_at_soc: 60, waiting_in_line_pos: 4 },
    { car: "A-1", post: "P-07", min_ago: 10, cut_at_soc: 80, charging_again_on: "P-02" }] } } };
  assert.deepEqual(check("A-1 cut at 60% 10 min ago on P-07, pos 4, now on P-02.", twice).wrong, []);
  assert.equal(check("A-1 cut at 70% on P-03.", twice).wrong.length, 2);
  const bare = { v: 1, subjects: { charges_cut_by_fault: { cars: [{ car: "A-1", min_ago: 5 }] } } };
  assert.deepEqual(check("A-1 cut 5 min ago on ANY-POST-9, pos 2.", bare),
                   { cars: 1, checked: 2, wrong: [{ car: "A-1", field: "line_pos", said: "2", brief: "not in line" }] });
});

test("the tally counts directives that named a cut car, keeps 12 misses and marks the refused", () => {
  const t = newFactsTally();
  tallyFacts(t, check("the wall is the posts"), false);
  assert.deepEqual(t, { directives: 0, facts_checked: 0, facts_wrong: 0, refused: 0, misses: [] });
  tallyFacts(t, check("Waymo-AV-024 cut 72 min ago, pos 18."), false);
  tallyFacts(t, check("Waymo-AV-024 cut 46 min ago, pos 21."), true);
  assert.deepEqual({ ...t, misses: t.misses.length }, { directives: 2, facts_checked: 4, facts_wrong: 2, refused: 1, misses: 2 });
  assert.ok(t.misses.every((m) => m.refused === true));
  for (let i = 0; i < 10; i++) tallyFacts(t, check("Waymo-AV-024 cut 46 min ago, pos 21."), false);
  assert.equal(t.misses.length, 12);
  assert.equal(t.facts_wrong, 22);
});

test("the brief's prompt tells the model to write a waiting car again from this brief's numbers", () => {
  assert.match(WAKE_BRIEF_PROMPT, /write its directive again from THIS brief's numbers \(min_ago, waiting_in_line_pos, soc_now\): never copy a number from last_answer\.you_said/);
  assert.match(WAKE_BRIEF_PROMPT, /never name a post for a car other than the two the brief gives it \(post, charging_again_on\)/);
});
