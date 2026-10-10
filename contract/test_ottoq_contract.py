"""OTTO-Q depot contract 0.1 battery (contract/README.md). No database, no network.

T1  every schema is valid 2020-12, its $id names its file, and every $ref in it resolves
T2  every valid example conforms, one per event type
T3  every invalid example is refused for the one reason expect.json names, and for nothing else
T4  the canonicalizer reproduces RFC 8785's own samples
T5  the signer reproduces RFC 8037 A.4; every signed example verifies and is current; any edit breaks it
T6  the telemetry schema admits exactly vss_mapping's VSS paths, each with VSS's datatype
T7  asyncapi.yaml is 3.1.0, its refs resolve, and its ten messages are the ten event types
T8  the README names every event type and every ack reason
T9  every service code in the examples is one the depot publishes
"""
from __future__ import annotations

import copy
import json
import struct
from pathlib import Path

import pytest
import yaml
from jsonschema import Draft202012Validator

import ottoq_contract as kit

HERE = Path(__file__).resolve().parent
VALID = HERE / "examples" / "valid"
INVALID = HERE / "examples" / "invalid"
ALL_TYPES = kit.INBOUND_TYPES + kit.OUTBOUND_TYPES
PREFIX = "com.ottoyard."

# service_cadence_policy.svc where active, read from otto-q-core on 2026-10-09 (16 codes).
# The door refuses a code the depot does not publish, so an example must not use one.
PUBLISHED_SERVICE_CODES = frozenset({
    "charge", "item_retrieval", "triage_check", "interior_inspection", "interior_tidy",
    "sensor_clean", "perimeter_walkaround", "fault_repair", "exterior_wash", "interior_deep_clean",
    "software_update", "sensor_calibration", "mechanical_pm", "cosmetic_repair",
    "remote_diagnostics", "readiness_check",
})


@pytest.fixture(scope="module")
def schemas():
    return kit.load_schemas()


@pytest.fixture(scope="module")
def validator(schemas):
    return kit.envelope_validator(schemas)


def load(path: Path):
    return json.loads(path.read_text())


def walk_refs(node, out):
    if isinstance(node, dict):
        if isinstance(node.get("$ref"), str):
            out.append(node["$ref"])
        for v in node.values():
            walk_refs(v, out)
    elif isinstance(node, list):
        for v in node:
            walk_refs(v, out)
    return out


# ------------------------------------------------------------------- T1

def test_t1_schemas_are_valid_and_every_ref_resolves(schemas):
    assert len(schemas) == 12, sorted(schemas)  # ten types, the envelope, the shared defs
    registry = kit.registry(schemas)
    for sid, schema in schemas.items():
        assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema", sid
        Draft202012Validator.check_schema(schema)
        resolver = registry.resolver(base_uri=sid)
        for ref in walk_refs(schema, []):
            resolver.lookup(ref)  # raises Unresolvable if the target is missing


def test_t1_every_type_has_its_schema_and_its_dataschema(schemas):
    envelope = schemas[kit.ENVELOPE_ID]
    assert tuple(envelope["properties"]["type"]["enum"]) == ALL_TYPES
    for t in ALL_TYPES:
        assert kit.BASE + t[len(PREFIX):] + ".json" in schemas, t


# ------------------------------------------------------------------- T2

def test_t2_one_valid_example_per_type_and_each_conforms(validator):
    files = sorted(VALID.glob("*.json"))
    assert {p.stem for p in files} == {t[len(PREFIX):] for t in ALL_TYPES}
    for path in files:
        event = load(path)
        assert event["type"] == PREFIX + path.stem, path.name
        assert kit.problems(event, validator) == [], path.name


# ------------------------------------------------------------------- T3

def test_t3_every_invalid_example_fails_for_its_named_reason_only(validator):
    expect = load(INVALID / "expect.json")
    files = {p.stem for p in INVALID.glob("*.json")} - {"expect"}
    assert files == set(expect), "an invalid example without an expectation, or the reverse"
    for name, want in expect.items():
        assert (VALID / f"{want['from']}.json").exists(), name
        errors = list(validator.iter_errors(load(INVALID / f"{name}.json")))
        assert errors, f"{name} conforms but should not"
        assert {kit.keyword(e) for e in errors} == {want["expected_keyword"]}, (name, kit.problems(load(INVALID / f"{name}.json"), validator))


# ------------------------------------------------------------------- T4

RFC8785_APPENDIX_B = [  # IEEE 754 bits -> canonical text
    ("0000000000000000", "0"), ("8000000000000000", "0"),
    ("0000000000000001", "5e-324"), ("8000000000000001", "-5e-324"),
    ("7fefffffffffffff", "1.7976931348623157e+308"), ("ffefffffffffffff", "-1.7976931348623157e+308"),
    ("4340000000000000", "9007199254740992"), ("c340000000000000", "-9007199254740992"),
    ("4430000000000000", "295147905179352830000"),
    ("44b52d02c7e14af5", "9.999999999999997e+22"), ("44b52d02c7e14af6", "1e+23"),
    ("44b52d02c7e14af7", "1.0000000000000001e+23"),
    ("444b1ae4d6e2ef4e", "999999999999999700000"), ("444b1ae4d6e2ef4f", "999999999999999900000"),
    ("444b1ae4d6e2ef50", "1e+21"),
    ("3eb0c6f7a0b5ed8c", "9.999999999999997e-7"), ("3eb0c6f7a0b5ed8d", "0.000001"),
    ("41b3de4355555553", "333333333.3333332"), ("41b3de4355555554", "333333333.33333325"),
    ("41b3de4355555555", "333333333.3333333"), ("41b3de4355555556", "333333333.3333334"),
    ("41b3de4355555557", "333333333.33333343"),
    ("becbf647612f3696", "-0.0000033333333333333333"),
    ("43143ff3c1cb0959", "1424953923781206.2"),
]


@pytest.mark.parametrize("bits,text", RFC8785_APPENDIX_B)
def test_t4_numbers_match_rfc8785_appendix_b(bits, text):
    value = struct.unpack(">d", bytes.fromhex(bits))[0]
    assert kit.canonicalize(value).decode() == text


@pytest.mark.parametrize("bits", ["7fffffffffffffff", "7ff0000000000000"])
def test_t4_nan_and_infinity_have_no_canonical_form(bits):
    with pytest.raises(ValueError):
        kit.canonicalize(struct.unpack(">d", bytes.fromhex(bits))[0])


def test_t4_rfc8785_section_3_2_2_sample():
    source = r'''{
      "numbers": [333333333.33333329, 1E30, 4.50, 2e-3, 0.000000000000000000000000001],
      "string": "\u20ac$\u000F\u000aA'\u0042\u0022\u005c\\\"\/",
      "literals": [null, true, false]
    }'''
    expected = r'''{"literals":[null,true,false],"numbers":[333333333.3333333,1e+30,4.5,0.002,1e-27],"string":"€$\u000f\nA'B\"\\\\\"/"}'''
    assert kit.canonicalize(json.loads(source)).decode() == expected


def test_t4_rfc8785_section_3_2_3_sort_order():
    source = r'''{
      "\u20ac": "Euro Sign",
      "\r": "Carriage Return",
      "\ufb33": "Hebrew Letter Dalet With Dagesh",
      "1": "One",
      "\ud83d\ude00": "Emoji: Grinning Face",
      "\u0080": "Control",
      "\u00f6": "Latin Small Letter O With Diaeresis"
    }'''
    ordered = list(json.loads(kit.canonicalize(json.loads(source))).values())
    assert ordered == ["Carriage Return", "One", "Control", "Latin Small Letter O With Diaeresis",
                       "Euro Sign", "Emoji: Grinning Face", "Hebrew Letter Dalet With Dagesh"]


# ------------------------------------------------------------------- T5

def test_t5_signer_reproduces_rfc8037_a4():
    key = kit.example_key()
    header, payload = "eyJhbGciOiJFZERTQSJ9", kit.b64u(b"Example of Ed25519 signing")
    assert payload == "RXhhbXBsZSBvZiBFZDI1NTE5IHNpZ25pbmc"
    signature = kit.b64u(key.sign(f"{header}.{payload}".encode()))
    assert signature == "hgyY0il_MGCjP0JzlnLWG1PPOt7-09PGcvMg3AIbQR6dWbhijcNR4ki4iylGjg5BhVsPt9g7sVvpAr_MuM0KAg"


def test_t5_example_jwks_is_the_public_half_of_the_example_key():
    keys = kit.public_keys(kit.example_jwks())
    assert set(keys) == {kit.EXAMPLE_KID}
    assert keys[kit.EXAMPLE_KID].public_bytes_raw() == kit.example_key().public_key().public_bytes_raw()


def test_t5_every_signed_example_verifies_and_is_current():
    keys = kit.public_keys(kit.example_jwks())
    signed = [p for p in sorted((HERE / "examples").glob("*/*.json")) if "ottoqsig" in load(p)]
    assert len(signed) >= len(kit.OUTBOUND_TYPES)
    for path in signed:
        assert kit.verify(load(path), keys) == kit.EXAMPLE_KID, path.name
    for t in kit.OUTBOUND_TYPES:
        assert "ottoqsig" in load(VALID / f"{t[len(PREFIX):]}.json"), t
    assert kit.sign_examples(check=True) == 0, "run: python3 contract/ottoq_contract.py sign-examples"


@pytest.mark.parametrize("tamper", [
    pytest.param(lambda e: e["data"].__setitem__("target_soc_pct", 90), id="data"),
    pytest.param(lambda e: e.__setitem__("subject", "SIMB-0007"), id="subject"),
    pytest.param(lambda e: e.__setitem__("source", "urn:ottoq:depot:22222222-2222-2222-2222-222222222222"), id="source"),
    pytest.param(lambda e: e.__setitem__("id", "ottoq-999999"), id="id"),
    pytest.param(lambda e: e.__setitem__("time", "2026-10-09T14:01:01Z"), id="time"),
])
def test_t5_signature_covers_the_whole_event(tamper):
    keys = kit.public_keys(kit.example_jwks())
    event = load(VALID / "directive.charge.plan.json")
    tamper(event)
    with pytest.raises(kit.SignatureError, match="does not verify"):
        kit.verify(event, keys)


def test_t5_only_detached_ed25519_with_a_known_kid_verifies():
    keys = kit.public_keys(kit.example_jwks())
    event = load(VALID / "directive.charge.plan.json")
    key = kit.example_key()

    def with_header(header: dict) -> dict:
        h = kit.b64u(json.dumps(header, separators=(",", ":")).encode())
        sig = key.sign(f"{h}.{kit.b64u(kit.signing_payload(event))}".encode())
        return {**event, "ottoqsig": f"{h}..{kit.b64u(sig)}"}

    with pytest.raises(kit.SignatureError, match="Ed25519 only"):
        kit.verify(with_header({"alg": "EdDSA", "kid": kit.EXAMPLE_KID}), keys)
    with pytest.raises(kit.SignatureError, match="unknown kid"):
        kit.verify(with_header({"alg": "Ed25519", "kid": "some-other-key"}), keys)
    with pytest.raises(kit.SignatureError, match="exactly alg and kid"):
        kit.verify(with_header({"alg": "Ed25519", "kid": kit.EXAMPLE_KID, "b64": False}), keys)
    attached = event["ottoqsig"].replace("..", "." + kit.b64u(kit.signing_payload(event)) + ".")
    with pytest.raises(kit.SignatureError, match="detached"):
        kit.verify({**event, "ottoqsig": attached}, keys)
    assert kit.verify(with_header({"kid": kit.EXAMPLE_KID, "alg": "Ed25519"}), keys) == kit.EXAMPLE_KID


def test_t5_a_private_key_is_never_accepted_as_a_verification_key():
    jwks = copy.deepcopy(kit.example_jwks())
    jwks["keys"][0]["d"] = "x"
    with pytest.raises(kit.SignatureError, match="not a public Ed25519 key"):
        kit.public_keys(jwks)


# ------------------------------------------------------------------- T6

def _json_type(value_schema: dict, registry, base: str) -> dict:
    """The value schema with any $ref chain followed."""
    resolver = registry.resolver(base_uri=base)
    while "$ref" in value_schema:
        resolved = resolver.lookup(value_schema["$ref"])
        value_schema, resolver = resolved.contents, resolved.resolver
    return value_schema


def test_t6_telemetry_signals_are_vss_mapping_paths_with_vss_datatypes(schemas):
    mapping = load(HERE / "vss_mapping.json")
    reference = mapping["vss_reference"]
    telemetry_id = kit.BASE + "vehicle.telemetry.json"
    telemetry = schemas[telemetry_id]
    signals = telemetry["properties"]["signals"]["properties"]
    assert set(signals) == set(reference)
    assert {f["vss"] for f in mapping["fields"]} <= set(reference)
    registry = kit.registry(schemas)
    uint_max = {"uint8": 255, "uint16": 65535, "uint32": 4294967295}
    for path, ref in signals.items():
        signal_def = _json_type(ref, registry, telemetry_id)
        value = _json_type(signal_def["properties"]["value"], registry, telemetry_id)
        datatype = reference[path]["datatype"]
        if datatype in ("float", "double"):
            assert value["type"] == "number", path
        elif datatype in uint_max:
            assert value["type"] == "integer" and value["minimum"] >= 0 and value["maximum"] <= uint_max[datatype], path
        elif datatype == "boolean":
            assert value["type"] == "boolean", path
        elif datatype == "string[]":
            assert value["type"] == "array" and value["items"]["type"] == "string", path
        else:
            pytest.fail(f"{path}: VSS datatype {datatype} has no rule here")


# ------------------------------------------------------------------- T7

def _pointer(doc, ref: str):
    node = doc
    for part in ref[2:].split("/"):
        node = node[part.replace("~1", "/").replace("~0", "~")]
    return node


def test_t7_asyncapi_index_matches_the_schemas(schemas, validator):
    doc = yaml.safe_load((HERE / "asyncapi.yaml").read_text())
    assert doc["asyncapi"] == "3.1.0"
    for ref in walk_refs(doc, []):
        if ref.startswith("#/"):
            _pointer(doc, ref)
        else:
            assert ref == "./schemas/envelope.json", ref
            assert (HERE / ref).exists()
    messages = doc["components"]["messages"]
    assert sorted(m["name"] for m in messages.values()) == sorted(ALL_TYPES)
    registry = kit.registry(schemas)
    for m in messages.values():
        payload = m["payload"]
        assert payload["schemaFormat"] == "application/schema+json;version=2020-12"
        assert payload["schema"]["allOf"][1]["properties"]["type"]["const"] == m["name"]
        schema = json.loads(json.dumps(payload["schema"]).replace("./schemas/", kit.BASE))
        message_validator = Draft202012Validator(schema, registry=registry)
        own = load(VALID / f"{m['name'][len(PREFIX):]}.json")
        assert message_validator.is_valid(own), m["name"]
        other = next(t for t in ALL_TYPES if t != m["name"])
        assert not message_validator.is_valid(load(VALID / f"{other[len(PREFIX):]}.json")), m["name"]
    ops = {o["action"]: o for o in doc["operations"].values()}
    assert set(ops) == {"receive", "send"}
    for action, channel, types in (("receive", "events", kit.INBOUND_TYPES), ("send", "directives", kit.OUTBOUND_TYPES)):
        assert ops[action]["channel"]["$ref"] == f"#/channels/{channel}"
        names = [_pointer(doc, r["$ref"])["$ref"] for r in ops[action]["messages"]]
        assert sorted(_pointer(doc, n)["name"] for n in names) == sorted(types), action


# ------------------------------------------------------------------- T8

def test_t8_readme_names_every_type_and_every_ack_reason(schemas):
    readme = (HERE / "README.md").read_text()
    for t in ALL_TYPES:
        assert f"`{t[len(PREFIX):]}`" in readme, t
    for reason in schemas[kit.BASE + "defs.json"]["$defs"]["ackReason"]["enum"]:
        assert f"| `{reason}` |" in readme, reason


# ------------------------------------------------------------------- T9

def test_t9_example_service_codes_are_published():
    used = set()
    for path in VALID.glob("*.json"):
        data = load(path)["data"]
        used |= set(data.get("services_needed", [])) | set(data.get("open_services", []))
        used |= {op["service_code"] for op in data.get("operations", [])}
    assert used, "no example names a service"
    assert used <= PUBLISHED_SERVICE_CODES, sorted(used - PUBLISHED_SERVICE_CODES)
