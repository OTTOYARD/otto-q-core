-- 0174  A rule that cannot fire should not look like one that enforces.
--       Read-only instrument. forces_recert = FALSE - adds a view and a summary
--       function; touches no engine function and no rule.
--
-- docs/DECISION_BOUNDARY.md established that nine of twenty-nine active rules
-- have never been evaluated, six of them `block` severity, because they are
-- scoped to action names the engine never announces. It also said the part that
-- is not defensible either way:
--
--   "a rule registered active at block severity that cannot fire looks
--    identical in the registry to one that enforces."
--
-- That is what this fixes. Not the rules - the VISIBILITY of the gap. Until the
-- unannounced actions are wired (an engine change, its own round), the honest
-- thing is that nobody can quote a rule count without the enforced count beside
-- it.
--
-- THE RETENTION CAVEAT IS BUILT IN, NOT REMEMBERED. ottoq_rule_evaluations is
-- purged on a rolling window; at the time of writing it held 3.9M rows spanning
-- five days (2026-08-28 to 2026-09-02). Five days is not history. An earlier
-- version of this finding reasoned circularly from "which rules fired lately"
-- and had to be withdrawn (db/checks/0081 records the same lesson from the
-- stranding investigation). So the view REPORTS its own window rather than
-- letting a reader assume one, and the verdict column says "no evaluations in
-- the retained window" - never "dead".

CREATE OR REPLACE VIEW public.ottoq_rule_enforcement_reality AS
WITH win AS (
  SELECT min(evaluated_at) AS window_start,
         max(evaluated_at) AS window_end,
         GREATEST(1, (max(evaluated_at)::date - min(evaluated_at)::date)) AS window_days
    FROM ottoq_rule_evaluations
)
SELECT r.rule_code,
       r.severity,
       r.enforcement,
       r.status,
       array_to_string(r.applies_to_actions, ',') AS applies_to_actions,
       ev.n                                       AS evaluations_in_window,
       w.window_start,
       w.window_end,
       w.window_days,
       -- The verdict is deliberately about the WINDOW, never about the rule's
       -- existence. "not_observed" is a statement about evidence, not a claim
       -- that the rule is dead.
       CASE WHEN ev.n > 0 THEN 'enforcing'
            ELSE 'not_observed_in_window' END     AS reality,
       -- The one that matters for any quoted count: an active BLOCK rule with no
       -- observed evaluation is being described as an inviolable constraint
       -- while carrying no evidence that it constrains anything.
       (r.status = 'active' AND r.enforcement = 'block' AND ev.n = 0) AS block_without_evidence
  FROM ottoq_rules r
  CROSS JOIN win w
  CROSS JOIN LATERAL (SELECT count(*) AS n FROM ottoq_rule_evaluations e
                       WHERE e.rule_code = r.rule_code) ev;

COMMENT ON VIEW public.ottoq_rule_enforcement_reality IS
  'Per rule: is it actually observed enforcing, over the window ottoq_rule_evaluations currently retains. reality = not_observed_in_window is a statement about EVIDENCE, not a claim the rule is dead - the evaluations table is purged on a rolling window and five days is not history (0174).';

CREATE OR REPLACE FUNCTION public.ottoq_rules_headline()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public','extensions'
AS $fn$
  SELECT jsonb_build_object(
    'registered_active',        count(*) FILTER (WHERE status='active'),
    'observed_enforcing',       count(*) FILTER (WHERE status='active' AND reality='enforcing'),
    'not_observed_in_window',   count(*) FILTER (WHERE status='active' AND reality<>'enforcing'),
    'block_without_evidence',   count(*) FILTER (WHERE block_without_evidence),
    'evidence_window_days',     max(window_days),
    'evidence_window_start',    max(window_start),
    'evidence_window_end',      max(window_end),
    'caveat', 'not_observed_in_window means no evaluation inside the retained window. The window is short (evidence_window_days) because ottoq_rule_evaluations is purged; a rule that fires rarely is indistinguishable from one that cannot fire, by this measure alone. The structural test is whether the engine ever announces the rule''s action - see docs/DECISION_BOUNDARY.md.',
    'never_quote_without', 'Quote registered_active and observed_enforcing together. They are not the same number.'
  ) FROM public.ottoq_rule_enforcement_reality;
$fn$;

COMMENT ON FUNCTION public.ottoq_rules_headline() IS
  'The rule count and the enforced count in one object, so the first cannot be quoted without the second. 0174.';

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('a_rule_that_cannot_fire_should_not_look_like_one_that_enforces', false,
        'Read-only instrument. Adds ottoq_rule_enforcement_reality and ottoq_rules_headline so a rule count cannot be quoted without the observed-enforcing count beside it. Touches no engine function and no rule. The retention caveat is built into the output rather than left for a reader to remember - the verdict is about the evidence window, never a claim that a rule is dead.', now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
