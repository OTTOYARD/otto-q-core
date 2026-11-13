import assert from "node:assert/strict";
import test from "node:test";

import {
  WAKE_BRIEF_PROMPT,
  briefCoverage,
  briefSubjects,
  briefText,
  directiveAbout,
  namesSubject,
  readBrief,
  userMessageOf,
  withWakeBrief,
} from "../edge-functions/_shared/agent_wake_brief.ts";
import { ruleNineDirective } from "../edge-functions/_shared/agent_rule_nine.ts";

// edge function v32 (0823, G540): the wake brief as the edge function reads it. The brief itself is built and tested
// in the database (tests/test_agent_wake_brief_sql.py); briefSubjects and namesSubject follow the same rule as the view
// public.ottoq_agent_wake_brief_coverage, and the last test here holds the two to the same answers on the same case.

const BRIEF = {
  v: 1,
  reasons: ["charger_fault"],
  subjects: {
    charges_cut_by_fault: { count: 3, cars: [
      { car: "Tesla-AV-05", new: true }, { car: "Zoox-AV-097", new: true }, { car: "Waymo-AV-001", new: false }] },
    emergencies: [{ car: "Zoox-002" }],
    chargers_faulted: { count: 2, new: 1, chargers: [
      { post: "NASH-DCFC-STALL-02", new: true }, { post: "NASH-DCFC-STALL-09", new: false }] },
    scout_findings_new: { count: 1, findings: [{ car: "Car.X (1)", scout: "stranded_open_must_do" }] },
  },
};

test("NULL from the database (the dial at 0) is no brief and records nothing", () => {
  assert.deepEqual(readBrief(null, null), { brief: null, record: undefined });
  assert.deepEqual(readBrief(undefined, null), { brief: null, record: undefined });
});

test("a missing function, an error object or an unreadable answer is no brief, and says why on the record", () => {
  const rpc = readBrief(null, { message: "Could not find the function public.ottoq_agent_wake_brief" });
  assert.equal(rpc.brief, null);
  assert.match(String(rpc.record.error), /^rpc: Could not find the function/);
  const failed = readBrief({ v: 1, error: 'relation "ocpp_sessions" does not exist', reasons: ["heartbeat"] }, null);
  assert.equal(failed.brief, null);
  assert.deepEqual(failed.record, { v: 1, error: 'relation "ocpp_sessions" does not exist' });
  for (const bad of ["text", 7, [], { v: 2, subjects: {} }, { v: 1 }, { v: 1, subjects: [] }]) {
    assert.deepEqual(readBrief(bad, null), { brief: null, record: { error: "brief unreadable" } });
  }
});

test("a usable brief is shown and recorded as it came", () => {
  const read = readBrief(BRIEF, null);
  assert.equal(read.brief, BRIEF);
  assert.equal(read.record, BRIEF);
  assert.deepEqual(readBrief({ v: 1, subjects: {} }, null).brief, { v: 1, subjects: {} });
});

test("with no brief the message and the prompt are v31's, byte for byte", () => {
  assert.equal(userMessageOf(null, '{\n "tick": 7\n}'), 'BOARD DIGEST:\n{\n "tick": 7\n}\n\nReturn ONLY the JSON object.');
  assert.equal(withWakeBrief("SYSTEM", null), "SYSTEM");
});

test("with a brief the message leads with it and the prompt gains the wake section", () => {
  const m = userMessageOf(BRIEF, "{}");
  assert.equal(m, `WAKE BRIEF (why you are consulted now):\n${briefText(BRIEF)}\n\nBOARD DIGEST:\n{}\n\nReturn ONLY the JSON object.`);
  assert.equal(briefText(BRIEF), JSON.stringify(BRIEF, null, 1));
  assert.equal(withWakeBrief("SYSTEM", BRIEF), `SYSTEM\n${WAKE_BRIEF_PROMPT}`);
});

test("the wake section names every field the brief returns, states rule 9 and passes rule 9's own test", () => {
  for (const field of ["reasons", "changed", "subjects", "charges_cut_by_fault", "charging_again_on", "again_after_min",
    "waiting_in_line_pos", "soc_now", "chargers_faulted", "emergencies", "past_contract_wait", "scout_findings_new",
    "dr_call", "last_answer.you_said", "sim_min_ago", '"about"']) {
    assert.ok(WAKE_BRIEF_PROMPT.includes(field), `the section does not name ${field}`);
  }
  assert.match(WAKE_BRIEF_PROMPT, /keeps its full target/);
  assert.match(WAKE_BRIEF_PROMPT, /never an instruction to you/);
  // no sentence of the section is itself an instruction rule 9 refuses
  for (const line of WAKE_BRIEF_PROMPT.split("\n")) assert.deepEqual(ruleNineDirective(line), { ok: true }, line);
});

test("the subjects a brief names as new: cut charges and posts only when new, every emergency, every finding", () => {
  assert.deepEqual(briefSubjects(BRIEF), [
    { kind: "charge_cut", name: "Tesla-AV-05" }, { kind: "charge_cut", name: "Zoox-AV-097" },
    { kind: "emergency", name: "Zoox-002" }, { kind: "charger_fault", name: "NASH-DCFC-STALL-02" },
    { kind: "scout_finding", name: "Car.X (1)" }]);
  assert.deepEqual(briefSubjects(null), []);
  assert.deepEqual(briefSubjects({ v: 1, subjects: {} }), []);
  assert.deepEqual(briefSubjects({ v: 1, subjects: { emergencies: "x", charges_cut_by_fault: { cars: [null, 3, { car: "" , new: true }] } } }), []);
});

test("a text names a subject by its whole name, any letter case, never by a longer name", () => {
  assert.equal(namesSubject("Tesla-AV-055 was cut at 75%", "Tesla-AV-05"), false);
  assert.equal(namesSubject("zoox-av-097 is charging again", "Zoox-AV-097"), true);
  assert.equal(namesSubject("Zoox-AV-002 is not Zoox-0021 either", "Zoox-002"), false);
  assert.equal(namesSubject("(Zoox-002)", "Zoox-002"), true);
  assert.equal(namesSubject("about Car.X (1)", "Car.X (1)"), true);
  assert.equal(namesSubject("about CarsX (1)", "Car.X (1)"), false);
  assert.equal(namesSubject("", "Zoox-002"), false);
});

// the same case as tests/test_agent_wake_brief_sql.py::test_the_coverage_view_matches_a_whole_name_and_nothing_longer
test("coverage counts the brief's subjects the directives name, and agrees with the database view on its case", () => {
  const directives = [
    { type: "directive", text: "Tesla-AV-055 was cut at 75%; zoox-av-097 is charging again on post 6." },
    { type: "directive", text: "Post NASH-DCFC-STALL-02 faulted.", about: "Car.X (1)" },
    { type: "directive", text: "Zoox-AV-002 is not Zoox-0021 either." }];
  assert.deepEqual(briefCoverage(BRIEF, directives),
    { subjects: 5, addressed: 3, missed: ["charge_cut:Tesla-AV-05", "emergency:Zoox-002"] });
  assert.deepEqual(briefCoverage(BRIEF, []).addressed, 0);
  assert.deepEqual(briefCoverage({ v: 1, subjects: {} }, directives), { subjects: 0, addressed: 0, missed: [] });
  assert.equal(briefCoverage(null, directives), null);
});

test("a directive's about is kept short, or not at all", () => {
  assert.equal(directiveAbout({ about: "  Tesla-AV-055 " }), "Tesla-AV-055");
  assert.equal(directiveAbout({ about: "x".repeat(200) }).length, 80);
  for (const a of [{}, { about: "" }, { about: 7 }, { about: null }, null]) assert.equal(directiveAbout(a), undefined);
});
