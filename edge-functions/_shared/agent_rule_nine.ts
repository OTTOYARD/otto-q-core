// agent_rule_nine.ts — v30 (the study of 2026-10-13, AV-9; CLAUDE.md rule 9).
//
// A directive is text an operator reads. On run fd6ed035 (agent v21, 2026-10-06) the agent issued 101 directives saying
// "charge to 80%+", and the board still frames readiness as "min ready SoC (80%)". Rule 9: a car charges to its owner's
// target (ottoq_effective_target_soc_at, 100% unless the owner set less), and no service it needs is skipped, deferred
// or shortened for site optimization. So a directive that INSTRUCTS a charge target under 100% ("charge to 80%+",
// "cap charging at 90%", "end sessions once cars reach 85%") or a skipped, deferred or shortened service is refused, and
// kept in the pass's rejected list with its text. A directive that DESCRIBES state passes: "Waymo-AV-035 is charging
// at 13%", "48 cars below 45%", "never stop a charge at 80%".
//
// The test is deliberately narrow and errs toward passing a description; the prompt (index.ts) states the rule too.

export type RuleNineVerdict = { ok: true } | { ok: false; reason: string; matched: string };

const PCT = String.raw`(\d{1,3}(?:\.\d+)?)\s*%`;
// "charge [up to 3 words] to|up to|until|till|only to N%"
const CHARGE_TARGET = new RegExp(
  String.raw`\b(?:charg\w*|top[\s-]?(?:up|off)\w*|fill\w*)\s+(?:[\w-]+\s+){0,3}?(?:only\s+to|up\s+to|to|until|till)\s+` + PCT, "gi");
// "cap|stop|end|limit|unplug|halt [up to 4 words] at|to|once|when|after [up to 2 words] N%"
const CHARGE_CUT = new RegExp(
  String.raw`\b(?:cap\w*|stop\w*|end\w*|limit\w*|unplug\w*|halt\w*)\s+(?:[\w-]+\s+){0,4}?(?:at|to|once|when|after)\s+(?:[\w-]+\s+){0,2}?` + PCT, "gi");
// "skip|defer|postpone|cancel|shorten|cut short|end early|drop|forgo|waive [up to 40 chars] <a service>"
const SKIP_SERVICE =
  /\b(?:skip\w*|defer\w*|postpon\w*|cancel\w*|shorten\w*|cut\s+short|end\s+early|drop\w*|forgo\w*|waive\w*)\b[^.;!?]{0,40}?\b(?:wash\w*|clean\w*|calibrat\w*|maintenance|pm|service\w*|inspection\w*|top[\s-]?off|charg\w*|readiness\s+check)\b/gi;
// a negation just before the instruction makes it the rule restated, not broken: "never stop a charge at 80%"
const NEGATED = /\b(?:not|never|no|don't|do\s+not|must\s+not|mustn't|without)\s+(?:[\w'-]+\s+){0,4}$/i;

function negated(text: string, at: number): boolean {
  return NEGATED.test(text.slice(Math.max(0, at - 40), at));
}

export function ruleNineDirective(text: string): RuleNineVerdict {
  const t = String(text ?? "");
  for (const re of [CHARGE_TARGET, CHARGE_CUT]) {
    re.lastIndex = 0;
    for (const m of t.matchAll(re)) {
      const pct = Number(m[1]);
      if (!Number.isFinite(pct) || pct >= 100 || negated(t, m.index ?? 0)) continue;
      return { ok: false,
               reason: "rule_9_charge_target: a directive may not set or imply a charge target below 100%; every car charges to its owner's target",
               matched: m[0].trim() };
    }
  }
  SKIP_SERVICE.lastIndex = 0;
  for (const m of t.matchAll(SKIP_SERVICE)) {
    if (negated(t, m.index ?? 0)) continue;
    return { ok: false, reason: "rule_9_service: a directive may not skip, defer or shorten a service or charge a car needs",
             matched: m[0].trim() };
  }
  return { ok: true };
}
