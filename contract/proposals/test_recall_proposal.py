"""The contract 0.2 recall directive, as proposed (contract/proposals/README.md). Not part of 0.1: this validates the
draft against 0.1's own shared definitions so the proposal cannot drift from the directive rules it reuses."""
import json
import os
import sys

from jsonschema import Draft202012Validator
from referencing import Resource

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import ottoq_contract as kit  # noqa: E402

SCHEMA = json.load(open(os.path.join(HERE, "directive.recall.json")))
EXAMPLE = json.load(open(os.path.join(HERE, "directive.recall.example.json")))


def _validator():
    reg = kit.registry().with_resource(SCHEMA["$id"], Resource.from_contents(SCHEMA))
    Draft202012Validator.check_schema(SCHEMA)
    return Draft202012Validator(SCHEMA, registry=reg)


def test_the_example_is_a_valid_recall():
    assert list(_validator().iter_errors(EXAMPLE)) == []


def test_a_recall_without_its_directive_header_or_with_a_target_is_refused():
    v = _validator()
    no_expiry = {k: x for k, x in EXAMPLE.items() if k != "expires_at"}
    assert list(v.iter_errors(no_expiry)), "a recall must expire like every directive"
    with_target = dict(EXAMPLE, charge_target_pct=80)
    assert list(v.iter_errors(with_target)), "a recall cannot carry a charge target (rule 8)"
    bad_reason = dict(EXAMPLE, reason="throughput")
    assert list(v.iter_errors(bad_reason)), "reasons are a closed list"


def test_it_is_not_in_the_0_1_schema_set():
    assert not any("recall" in sid for sid in kit.load_schemas())
