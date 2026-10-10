"""OTTO-Q depot contract 0.1: the conformance kit.

Checks an event against the contract's schemas, and signs and verifies the
`ottoqsig` attribute that everything OTTO-Q sends carries. Needs jsonschema,
referencing and cryptography, pinned in requirements.txt. No database, no network.

    python3 contract/ottoq_contract.py check FILE... [--jwks FILE]
        Validate each event. With --jwks, also verify every signature.
    python3 contract/ottoq_contract.py sign-examples [--check]
        Re-sign the examples that carry a signature, with the RFC 8037 test key.
        Ed25519 is deterministic (RFC 8032), so --check reports any example whose
        committed signature is not the one this kit computes.

The signature (README, Signatures): a detached JWS in compact form (RFC 7515
Appendix F) with protected header {"alg":"Ed25519","kid":...} (RFC 9864 names the
algorithm; "EdDSA" is deprecated there). Its payload is the RFC 8785 canonical form
of the whole event without `ottoqsig`. So:

    ottoqsig = B64U(header) + ".." + B64U(Ed25519(B64U(header) + "." + B64U(JCS(event - ottoqsig))))
"""
from __future__ import annotations

import argparse
import base64
import json
import math
import re
import sys
from pathlib import Path

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey
from jsonschema import Draft202012Validator, ValidationError
from referencing import Registry, Resource

HERE = Path(__file__).resolve().parent
SCHEMA_DIR = HERE / "schemas"
EXAMPLES = HERE / "examples"
BASE = "https://ottoyard.com/schemas/ottoq/contract/0.1/"
ENVELOPE_ID = BASE + "envelope.json"

INBOUND_TYPES = (
    "com.ottoyard.vehicle.telemetry",
    "com.ottoyard.depot.arrival.intent",
    "com.ottoyard.vehicle.fault.summary",
    "com.ottoyard.vehicle.departed",
    "com.ottoyard.directive.ack",
)
OUTBOUND_TYPES = (
    "com.ottoyard.directive.stall.assignment",
    "com.ottoyard.directive.charge.plan",
    "com.ottoyard.directive.service.schedule",
    "com.ottoyard.readiness.forecast",
    "com.ottoyard.capacity.offer",
)

# The published test key of RFC 8037 Appendix A.1 (the same key as RFC 8032 section
# 7.1, TEST 1). It signs the examples so that anyone can check a verifier against
# them. It is public by construction and must never sign anything a depot sends:
# real depot keys live in the platform's key store, never in this repository.
EXAMPLE_KID = "rfc8037-a1-test-key"
_EXAMPLE_PRIVATE_KEY_HEX = "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"


class SignatureError(Exception):
    """An ottoqsig that does not verify, or is not one this contract allows."""


# --------------------------------------------------------------------- schemas

def load_schemas() -> dict[str, dict]:
    """Every schema in schemas/, keyed by its $id."""
    out = {}
    for path in sorted(SCHEMA_DIR.glob("*.json")):
        schema = json.loads(path.read_text())
        sid = schema["$id"]
        if sid != BASE + path.name:
            raise ValueError(f"{path.name}: $id {sid!r} does not name the file")
        out[sid] = schema
    return out


def registry(schemas: dict[str, dict] | None = None) -> Registry:
    schemas = schemas or load_schemas()
    return Registry().with_resources((sid, Resource.from_contents(s)) for sid, s in schemas.items())


def envelope_validator(schemas: dict[str, dict] | None = None) -> Draft202012Validator:
    schemas = schemas or load_schemas()
    # No format checker on purpose: `format` is an annotation in 2020-12, and every
    # rule this contract enforces on a string is written as a pattern.
    return Draft202012Validator(schemas[ENVELOPE_ID], registry=registry(schemas))


def keyword(err: ValidationError) -> str:
    """The keyword that failed. A `false` subschema has none in jsonschema, so it is named here."""
    if err.validator is None and err.message.startswith("False schema"):
        return "false schema"
    return str(err.validator)


def problems(event: object, validator: Draft202012Validator | None = None) -> list[str]:
    """Every way the event breaks the contract, as 'path: message [keyword]'; empty when it conforms."""
    validator = validator or envelope_validator()
    out = []
    for err in sorted(validator.iter_errors(event), key=lambda e: list(map(str, e.absolute_path))):
        where = "/".join(map(str, err.absolute_path)) or "(event)"
        out.append(f"{where}: {err.message} [{keyword(err)}]")
    return out


# ------------------------------------------------------------ RFC 8785 (JCS)

def _number(x: int | float) -> str:
    """ECMAScript Number::toString, which RFC 8785 section 3.2.2.3 adopts."""
    if isinstance(x, bool):
        raise TypeError("a boolean is not a number")
    if isinstance(x, int):
        if abs(x) <= 2**53:
            return str(x)
        x = float(x)  # what an ECMAScript parser would hold
    if not math.isfinite(x):
        raise ValueError("NaN and Infinity have no JSON form (RFC 8785 section 3.2.2.3)")
    if x == 0:
        return "0"  # minus zero too
    sign = "-" if x < 0 else ""
    text = repr(abs(x))  # the shortest digits that round-trip, as ECMAScript chooses them
    mantissa, _, exp = text.partition("e")
    whole, _, frac = mantissa.partition(".")
    digits = (whole + frac).lstrip("0")
    e = int(exp or 0) - len(frac)
    stripped = digits.rstrip("0")
    e += len(digits) - len(stripped)
    digits, k = stripped, len(stripped)
    n = e + k  # value = 0.digits x 10^n
    if k <= n <= 21:
        return sign + digits + "0" * (n - k)
    if 0 < n <= 21:
        return sign + digits[:n] + "." + digits[n:]
    if -6 < n <= 0:
        return sign + "0." + "0" * -n + digits
    e10 = n - 1
    mark = "+" if e10 >= 0 else "-"
    head = digits if k == 1 else digits[0] + "." + digits[1:]
    return f"{sign}{head}e{mark}{abs(e10)}"


def _serialize(v: object) -> str:
    if v is None:
        return "null"
    if v is True:
        return "true"
    if v is False:
        return "false"
    if isinstance(v, str):
        # json.dumps escapes exactly what JSON.stringify escapes for well-formed text:
        # quote, backslash, and controls below U+0020 (short forms, else lowercase \u00xx).
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, (int, float)):
        return _number(v)
    if isinstance(v, list):
        return "[" + ",".join(_serialize(x) for x in v) + "]"
    if isinstance(v, dict):
        # Properties sorted by UTF-16 code units (RFC 8785 section 3.2.3); big-endian
        # UTF-16 bytes compare in exactly that order.
        items = sorted(v.items(), key=lambda kv: kv[0].encode("utf-16-be"))
        return "{" + ",".join(_serialize(k) + ":" + _serialize(x) for k, x in items) + "}"
    raise TypeError(f"{type(v).__name__} has no JSON form")


def canonicalize(v: object) -> bytes:
    """The RFC 8785 canonical form of a JSON value, as UTF-8."""
    return _serialize(v).encode("utf-8")


# ------------------------------------------------------------- signatures

def b64u(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode("ascii")


def b64u_decode(s: str) -> bytes:
    if not re.fullmatch(r"[A-Za-z0-9_-]*", s):
        raise SignatureError("not base64url")
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def signing_payload(event: dict) -> bytes:
    """What the signature covers: the whole event, canonical, without ottoqsig itself."""
    return canonicalize({k: v for k, v in event.items() if k != "ottoqsig"})


def sign(event: dict, key: Ed25519PrivateKey, kid: str) -> str:
    header = b64u(canonicalize({"alg": "Ed25519", "kid": kid}))
    signing_input = (header + "." + b64u(signing_payload(event))).encode("ascii")
    return header + ".." + b64u(key.sign(signing_input))


def public_keys(jwks: dict) -> dict[str, Ed25519PublicKey]:
    """kid -> key, from a JWK Set (RFC 7517) of Ed25519 keys (RFC 8037 OKP form)."""
    out = {}
    for jwk in jwks.get("keys", []):
        if jwk.get("kty") != "OKP" or jwk.get("crv") != "Ed25519" or "d" in jwk:
            raise SignatureError(f"key {jwk.get('kid')!r} is not a public Ed25519 key")
        out[jwk["kid"]] = Ed25519PublicKey.from_public_bytes(b64u_decode(jwk["x"]))
    return out


def verify(event: dict, keys: dict[str, Ed25519PublicKey]) -> str:
    """The kid that signed the event; raises SignatureError otherwise."""
    sig = event.get("ottoqsig")
    if not isinstance(sig, str):
        raise SignatureError("no ottoqsig")
    parts = sig.split(".")
    if len(parts) != 3 or parts[1] != "":
        raise SignatureError("ottoqsig is not a detached compact JWS (header..signature)")
    header_b64, _, sig_b64 = parts
    try:
        header = json.loads(b64u_decode(header_b64))
    except ValueError as exc:
        raise SignatureError("protected header is not JSON") from exc
    if not isinstance(header, dict) or set(header) != {"alg", "kid"}:
        raise SignatureError("protected header must hold exactly alg and kid")
    if header["alg"] != "Ed25519":
        raise SignatureError(f"alg {header['alg']!r}: this contract signs with Ed25519 only")
    key = keys.get(header["kid"])
    if key is None:
        raise SignatureError(f"unknown kid {header['kid']!r}")
    signing_input = (header_b64 + "." + b64u(signing_payload(event))).encode("ascii")
    try:
        key.verify(b64u_decode(sig_b64), signing_input)
    except InvalidSignature as exc:
        raise SignatureError("signature does not verify") from exc
    return header["kid"]


def example_key() -> Ed25519PrivateKey:
    return Ed25519PrivateKey.from_private_bytes(bytes.fromhex(_EXAMPLE_PRIVATE_KEY_HEX))


def example_jwks() -> dict:
    return json.loads((EXAMPLES / "example-jwks.json").read_text())


# -------------------------------------------------------------------- CLI

_SIG_LINE = re.compile(r'("ottoqsig":\s*")([^"]*)(")')


def sign_examples(check: bool) -> int:
    key, stale = example_key(), []
    for path in sorted(EXAMPLES.glob("*/*.json")):
        text = path.read_text()
        event = json.loads(text)
        if not isinstance(event, dict) or "ottoqsig" not in event or "specversion" not in event:
            continue
        fresh = sign(event, key, EXAMPLE_KID)
        if event["ottoqsig"] == fresh:
            continue
        stale.append(path.relative_to(HERE))
        if not check:
            new_text, n = _SIG_LINE.subn(lambda m: m.group(1) + fresh + m.group(3), text)
            assert n == 1 and json.loads(new_text)["ottoqsig"] == fresh, path
            path.write_text(new_text)
    for p in stale:
        print(("stale signature: " if check else "re-signed: ") + str(p))
    return 1 if (check and stale) else 0


def check_files(files: list[str], jwks_path: str | None) -> int:
    validator = envelope_validator()
    keys = public_keys(json.loads(Path(jwks_path).read_text())) if jwks_path else None
    failed = 0
    for name in files:
        event = json.loads(Path(name).read_text())
        found = problems(event, validator)
        if keys is not None and isinstance(event, dict) and event.get("type") in OUTBOUND_TYPES:
            try:
                verify(event, keys)
            except SignatureError as exc:
                found.append(f"ottoqsig: {exc}")
        print(f"{name}: {'ok' if not found else 'REFUSED'}")
        for line in found:
            print("  " + line)
        failed += bool(found)
    return 1 if failed else 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check", help="validate events against the contract")
    c.add_argument("files", nargs="+")
    c.add_argument("--jwks", help="a JWK Set to verify outbound signatures against")
    s = sub.add_parser("sign-examples", help="re-sign the examples with the RFC 8037 test key")
    s.add_argument("--check", action="store_true", help="report stale signatures; change nothing")
    args = ap.parse_args(argv)
    if args.cmd == "check":
        return check_files(args.files, args.jwks)
    return sign_examples(args.check)


if __name__ == "__main__":
    sys.exit(main())
