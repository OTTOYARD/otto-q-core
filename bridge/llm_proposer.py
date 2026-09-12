"""The LLM proposer -- a language model in the SAME seat as cuOpt and CP-SAT, and no other.

WHY THIS EXISTS (V1_DEMO_PLAN D3, approved by Chase 2026-09-12): "an LLM proposes,
the shield refuses the unsafe parts, each refusal is a ledger row with a reason
code." The existing Nemotron agent (edge-functions/ottoq-orchestrator-agent) writes
POLICY DIALS and ops actions -- and, as the 2026-07-30 audit recorded, "the 52-rule
L1 shield is NOT in that path", because a dial change is not a physical effect.
This module puts a model's PHYSICAL proposals (stall assignments) through the one
door every proposer uses, so the shield disposes them exactly as it disposes
cuOpt's and CP-SAT's, and a refusal is a row in ottoq_decisions with rule codes.

THE THREE LAWS, one more time, because a language model is the proposer most
likely to be trusted by accident:

  1. THE MODEL NEVER WRITES. It answers a question with JSON; this module turns
     the answer into door-shaped rows; the door's caller submits them; the decide
     path disposes. Nothing here touches a vehicle, a stall, or a dial.
  2. THE HARNESS CHECKS SHAPE, NOT SAFETY. A stall id must be one the digest
     showed the model (a made-up uuid would blow up the selector's cast INSIDE
     the tick); a vehicle may get one row; a stall may be named once per batch;
     requested_kw is COMPUTED here from the plug and the stall, never trusted
     from the model. Everything else -- an occupied stall, the wrong connector,
     the power cap, an SLA -- is deliberately left for the L1 shield, because
     the shield refusing it with a reason code IS the demonstration. Pre-filtering
     it here would show nothing and prove nothing.
  3. EVERY FIRE IS PRICED AND CAPPED. usage x the price table -> usd on the fire
     record; a per-run cap refuses to fire (status refused_cap) before the model
     is called; a model with no priced row cannot run without --allow-unpriced,
     because "the cap could not be enforced" must be a decision, not a default.

COST AND LATENCY, answered as Chase asked. The model is never inside the tick: it
runs between ticks under the same one-tick right-of-first-refusal as cuOpt (0259
seats llm_advisor at rank 20, holds_tick and greedy_yields true), so a slow answer
costs nothing but that proposal's chance -- the local path assigns as it always
has. Price per fire is usage x the table below; a digest of 24 vehicles + 40
stalls is on the order of 3-6K input tokens and the answer under 1K, i.e. cents,
and the cap turns "cents per fire" into a hard dollar ceiling per run.

PROVIDERS. AnthropicClient uses the official SDK with structured output
(output_config.format json_schema) so the answer is schema-valid by construction;
OpenAICompatibleClient reaches the NVIDIA-hosted endpoint the existing agent uses
(chat/completions with response_format json_object) so Nemotron can sit in the
same seat for comparison. Both import their client lazily: CI has neither package
and runs every test here through FakeClient.

SOURCE NAME: llm_advisor. Registered in ottoq_proposer_precedence by 0259; NOT a
certified proposer (0241) -- it reaches a certification only by record-and-replay
(0237/0239), which is what makes a nondeterministic proposer safe to consume.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from bridge.proposer_bridge import (  # noqa: E402
    ACTION_CONTEXT, ENTITY_TYPE, BridgeError, content_hash, emit_sql,
    _require_uuid,
)
from proposer.forward_proposer import (  # noqa: E402
    DEFAULT_SERVICEABLE_STATES, NON_CHARGING_TYPES,
)

SOURCE = "llm_advisor"
DEFAULT_MODEL = "claude-opus-5"
DEFAULT_MAX_TOKENS = 4096
DEFAULT_CAP_USD = 2.00

#: USD per million tokens. Source: the claude-api skill's model table, cached
#: 2026-06-24, mirroring https://platform.claude.com/docs/en/pricing.md . Cache
#: reads are billed at 0.1x and 5-minute cache writes at 1.25x the input price
#: (same source). A model absent here has NO price and cannot run unless the
#: caller passes allow_unpriced -- the cap is only as real as this table.
PRICES_USD_PER_MTOK: dict[str, dict[str, float]] = {
    "claude-opus-5":    {"input": 5.00, "output": 25.00},
    "claude-sonnet-5":  {"input": 2.00, "output": 10.00},
    "claude-haiku-4-5": {"input": 1.00, "output": 5.00},
}
PRICE_SOURCE = ("claude-api skill model table, cached 2026-06-24; "
                "https://platform.claude.com/docs/en/pricing.md")
CACHE_READ_MULTIPLIER = 0.10
CACHE_WRITE_MULTIPLIER = 1.25

#: The answer contract. Structured output holds the Anthropic client to it;
#: rows_from_answer() re-checks every field anyway, because the NVIDIA route
#: has no schema enforcement and because a contract enforced in one place is
#: a contract.
ANSWER_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "proposals": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "vehicle_id": {"type": "string"},
                    "stall_id": {"type": ["string", "null"]},
                    "abstain": {"type": "boolean"},
                    "reason": {"type": "string"},
                },
                "required": ["vehicle_id", "stall_id", "abstain", "reason"],
                "additionalProperties": False,
            },
        },
        "rationale": {"type": "string"},
    },
    "required": ["proposals", "rationale"],
    "additionalProperties": False,
}

#: Byte-stable on purpose: no clock, no run id, no digest here, so the prefix
#: caches across fires (shared/prompt-caching.md). Everything that varies is in
#: the user turn.
SYSTEM_PROMPT = """You are an advisory scheduler for an autonomous-vehicle depot. You will be shown a DIGEST of the depot right now: vehicles that need charging and the charging stalls on site, with their plugs, power, and status. Propose, for each vehicle, at most one stall, or abstain.

You are an ADVISOR. Nothing you say moves a vehicle. A deterministic safety layer reviews every proposal and refuses any that violate a rule, recording the rule code; the local scheduler assigns anything you abstain on. So: propose what you judge best, say why in one short sentence, and abstain rather than guess when the digest does not support a placement.

Consider: the vehicle's inlet must match a plug the stall accepts (a 'Multi' stall lists its supported_inlet_types); prefer fast (dcfc) stalls for the lowest state of charge; do not name a stall for two vehicles; a stall with a vehicle_id is occupied; respect the site power cap when many fast charges would coincide.

Answer with JSON only, matching the schema you were given: one entry per vehicle in the digest, each with vehicle_id, stall_id (or null), abstain (true if you are not proposing a stall), and reason."""


# ---------------------------------------------------------------------------
# Digest: what the model is allowed to see (and therefore to name)
# ---------------------------------------------------------------------------


def _num(v: Any) -> float | None:
    try:
        return None if v is None else float(v)
    except (TypeError, ValueError):
        return None


def frame_digest(frame: dict, *, max_vehicles: int = 24, max_stalls: int = 40) -> dict:
    """The compact, bounded view of the frame the model reasons over.

    Vehicles: serviceable state with a readable soc, lowest soc first. Stalls:
    every charge-capable stall INCLUDING occupied and reserved ones, with status
    shown -- an unsafe-but-well-formed proposal must remain possible (law 2).
    Omissions are counted, never silent.
    """
    vs = []
    for v in frame.get("vehicles") or []:
        if v.get("state") not in DEFAULT_SERVICEABLE_STATES:
            continue
        soc = _num(v.get("soc"))
        if soc is None:
            continue
        vs.append({"id": v["id"], "soc": soc, "target_soc": _num(v.get("target_soc")),
                   "state": v.get("state"), "inlet_type": v.get("inlet_type"),
                   "inlet_max_kw": _num(v.get("inlet_max_kw")),
                   "vehicle_class_code": v.get("vehicle_class_code")})
    vs.sort(key=lambda x: (x["soc"], x["id"]))
    ss = []
    for s in frame.get("stalls") or []:
        if s.get("type") in NON_CHARGING_TYPES:
            continue
        kw = _num(s.get("connector_max_kw")) or 0.0
        if kw <= 0:
            continue
        ss.append({"id": s["id"], "type": s.get("type"), "status": s.get("status"),
                   "vehicle_id": s.get("vehicle_id"), "connector_type": s.get("connector_type"),
                   "connector_max_kw": kw,
                   "supported_inlet_types": s.get("supported_inlet_types")})
    ss.sort(key=lambda x: (0 if x["type"] == "dcfc" else 1, -x["connector_max_kw"], x["id"]))
    return {
        "vehicles": vs[:max_vehicles],
        "stalls": ss[:max_stalls],
        "energy": frame.get("energy"),
        "bess": frame.get("bess"),
        "omitted": {"vehicles": max(0, len(vs) - max_vehicles),
                    "stalls": max(0, len(ss) - max_stalls)},
    }


def user_prompt(digest: dict) -> str:
    return ("DIGEST:\n" + json.dumps(digest, sort_keys=True, separators=(",", ":"), default=str)
            + "\n\nReturn the JSON object only.")


# ---------------------------------------------------------------------------
# Answer -> door-shaped rows (law 2: shape and referential integrity only)
# ---------------------------------------------------------------------------


def _abstain_row(vehicle_id: str, reason: str, *, model: str, by: str) -> dict:
    return {
        "action_context": ACTION_CONTEXT, "entity_type": ENTITY_TYPE,
        "entity_id": vehicle_id, "source": SOURCE,
        "proposal": {"verb": "assign_stall", "abstain": True, "vehicle_id": vehicle_id,
                     "rationale": {"optimizer": SOURCE, "model": model, "reason": reason,
                                   "abstained_by": by},
                     "resolved_action_context": ACTION_CONTEXT},
    }


def rows_from_answer(answer: Any, digest: dict, *, model: str) -> tuple[list[dict], list[dict]]:
    """Returns (rows, harness_rejections). One row per digest vehicle, always."""
    rejections: list[dict] = []
    vehicles = {v["id"]: v for v in digest["vehicles"]}
    stalls = {s["id"]: s for s in digest["stalls"]}
    by_vehicle: dict[str, dict] = {}
    if not isinstance(answer, dict) or not isinstance(answer.get("proposals"), list):
        rejections.append({"kind": "malformed_answer", "detail": type(answer).__name__})
        return ([_abstain_row(vid, "llm answer malformed; no proposal", model=model, by="harness")
                 for vid in vehicles], rejections)
    for p in answer["proposals"]:
        if not isinstance(p, dict):
            rejections.append({"kind": "malformed_proposal", "detail": repr(p)[:80]})
            continue
        vid = p.get("vehicle_id")
        if vid not in vehicles:
            rejections.append({"kind": "unknown_vehicle", "detail": str(vid)[:80]})
            continue
        if vid in by_vehicle:
            rejections.append({"kind": "duplicate_vehicle", "detail": vid})
            continue
        by_vehicle[vid] = p

    rows: list[dict] = []
    used: set[str] = set()
    for vid, v in vehicles.items():
        p = by_vehicle.get(vid)
        if p is None:
            rows.append(_abstain_row(vid, "llm gave no answer for this vehicle", model=model, by="harness"))
            continue
        reason = str(p.get("reason") or "")[:400]
        if p.get("abstain") is True or p.get("stall_id") in (None, ""):
            rows.append(_abstain_row(vid, reason or "llm abstained", model=model, by="model"))
            continue
        sid = p.get("stall_id")
        if sid not in stalls:
            rejections.append({"kind": "unknown_stall", "detail": f"{vid}->{str(sid)[:60]}"})
            rows.append(_abstain_row(vid, f"llm named a stall not in the digest ({str(sid)[:36]})",
                                     model=model, by="harness"))
            continue
        if sid in used:
            rejections.append({"kind": "duplicate_stall", "detail": f"{vid}->{sid}"})
            rows.append(_abstain_row(vid, f"llm named stall {sid} for a second vehicle",
                                     model=model, by="harness"))
            continue
        used.add(sid)
        s = stalls[sid]
        kw = s["connector_max_kw"]
        if v.get("inlet_max_kw"):
            kw = min(kw, v["inlet_max_kw"])
        rows.append({
            "action_context": ACTION_CONTEXT, "entity_type": ENTITY_TYPE,
            "entity_id": vid, "source": SOURCE,
            "proposal": {
                "verb": "assign_stall", "abstain": False,
                "stall_id": sid, "stall_type": s["type"], "vehicle_id": vid,
                "requested_kw": round(float(kw), 1),
                "rationale": {"optimizer": SOURCE, "model": model, "reason": reason,
                              "harness": "referential integrity and shape only; "
                                         "safety is the shield's"},
                "resolved_action_context": ACTION_CONTEXT,
            },
        })
    return rows, rejections


# ---------------------------------------------------------------------------
# Cost and the cap
# ---------------------------------------------------------------------------


def cost_usd(model: str, usage: dict | None) -> float | None:
    """usage x price table. None when the model has no priced row."""
    price = PRICES_USD_PER_MTOK.get(model)
    if price is None or not usage:
        return None
    inp = float(usage.get("input_tokens") or 0)
    out = float(usage.get("output_tokens") or 0)
    cr = float(usage.get("cache_read_input_tokens") or 0)
    cw = float(usage.get("cache_creation_input_tokens") or 0)
    usd = (inp * price["input"] + out * price["output"]
           + cr * price["input"] * CACHE_READ_MULTIPLIER
           + cw * price["input"] * CACHE_WRITE_MULTIPLIER) / 1_000_000.0
    return round(usd, 6)


class SpendLedger:
    """Per-run cumulative spend, file-backed so a loop across processes still
    honours the cap. The database ledger (0260, fire->>'usd') is the record of
    truth once applied; this is the client-side guard that runs BEFORE a call."""

    def __init__(self, path: str | Path | None):
        self.path = Path(path) if path else None
        self.data: dict[str, float] = {}
        if self.path and self.path.exists():
            try:
                self.data = {k: float(v) for k, v in json.loads(self.path.read_text()).items()}
            except (ValueError, OSError):
                self.data = {}

    def spent(self, run: str) -> float:
        return float(self.data.get(run, 0.0))

    def add(self, run: str, usd: float | None) -> None:
        if usd:
            self.data[run] = self.spent(run) + float(usd)
            if self.path:
                self.path.write_text(json.dumps(self.data, sort_keys=True, indent=1))


# ---------------------------------------------------------------------------
# Clients. Each is a callable: (system, user, schema) -> answer dict
#   {"text": str, "usage": {...}, "model": str, "latency_ms": int, "stop_reason": str}
# ---------------------------------------------------------------------------


class FakeClient:
    """Deterministic stand-in for tests and for --answer offline runs."""

    def __init__(self, answer: Any, *, model: str = "fake-model",
                 usage: dict | None = None, stop_reason: str = "end_turn"):
        self.answer, self.model = answer, model
        self.usage = usage or {"input_tokens": 1000, "output_tokens": 200}
        self.stop_reason = stop_reason
        self.calls = 0

    def __call__(self, system: str, user: str, schema: dict) -> dict:
        self.calls += 1
        text = self.answer if isinstance(self.answer, str) else json.dumps(self.answer)
        return {"text": text, "usage": dict(self.usage), "model": self.model,
                "latency_ms": 1, "stop_reason": self.stop_reason}


class AnthropicClient:
    """The official SDK with structured output. Imported lazily: CI has no SDK."""

    def __init__(self, model: str = DEFAULT_MODEL, *, max_tokens: int = DEFAULT_MAX_TOKENS,
                 effort: str = "medium"):
        try:
            import anthropic  # type: ignore
        except ImportError as exc:
            raise BridgeError("the anthropic SDK is not installed (pip install anthropic); "
                              "use --answer for an offline run") from exc
        self._anthropic = anthropic
        self._client = anthropic.Anthropic()   # ANTHROPIC_API_KEY / profile from the env
        self.model, self.max_tokens, self.effort = model, max_tokens, effort

    def __call__(self, system: str, user: str, schema: dict) -> dict:
        t0 = time.monotonic()
        response = self._client.messages.create(
            model=self.model,
            max_tokens=self.max_tokens,
            system=[{"type": "text", "text": system, "cache_control": {"type": "ephemeral"}}],
            messages=[{"role": "user", "content": user}],
            output_config={"effort": self.effort,
                           "format": {"type": "json_schema", "schema": schema}},
        )
        latency_ms = int((time.monotonic() - t0) * 1000)
        if response.stop_reason == "refusal":
            return {"text": "", "usage": response.usage.to_dict(), "model": response.model,
                    "latency_ms": latency_ms, "stop_reason": "refusal"}
        text = next((b.text for b in response.content if b.type == "text"), "")
        return {"text": text, "usage": response.usage.to_dict(), "model": response.model,
                "latency_ms": latency_ms, "stop_reason": response.stop_reason}


class OpenAICompatibleClient:
    """chat/completions over raw HTTP -- the NVIDIA-hosted endpoint the existing
    Nemotron agent already uses. No price row unless the caller adds one."""

    DEFAULT_URL = "https://integrate.api.nvidia.com/v1/chat/completions"

    def __init__(self, model: str, *, url: str = DEFAULT_URL, key_env: str = "NVIDIA_API_KEY_NEMOTRON",
                 max_tokens: int = DEFAULT_MAX_TOKENS, timeout_s: float = 60.0):
        key = os.environ.get(key_env)
        if not key:
            raise BridgeError(f"{key_env} is not set; the NVIDIA route needs it")
        self.model, self.url, self.key = model, url, key
        self.max_tokens, self.timeout_s = max_tokens, timeout_s

    def __call__(self, system: str, user: str, schema: dict) -> dict:
        import urllib.request
        body = json.dumps({
            "model": self.model, "temperature": 0.1, "max_tokens": self.max_tokens,
            "chat_template_kwargs": {"enable_thinking": False},
            "response_format": {"type": "json_object"},
            "messages": [{"role": "system", "content": system + "\n\nJSON schema:\n"
                          + json.dumps(schema, sort_keys=True)},
                         {"role": "user", "content": user}],
        }).encode("utf-8")
        req = urllib.request.Request(self.url, data=body, method="POST", headers={
            "Content-Type": "application/json", "Authorization": f"Bearer {self.key}"})
        t0 = time.monotonic()
        with urllib.request.urlopen(req, timeout=self.timeout_s) as r:
            j = json.loads(r.read().decode("utf-8"))
        latency_ms = int((time.monotonic() - t0) * 1000)
        text = (j.get("choices") or [{}])[0].get("message", {}).get("content", "") or ""
        u = j.get("usage") or {}
        return {"text": text, "model": j.get("model", self.model), "latency_ms": latency_ms,
                "usage": {"input_tokens": u.get("prompt_tokens", 0),
                          "output_tokens": u.get("completion_tokens", 0)},
                "stop_reason": (j.get("choices") or [{}])[0].get("finish_reason", "")}


# ---------------------------------------------------------------------------
# One fire
# ---------------------------------------------------------------------------


def _parse_json(text: str) -> Any:
    try:
        return json.loads(text)
    except (TypeError, ValueError):
        pass
    #: Tolerate prose around a single JSON object (the NVIDIA route has no
    #: structured output). First '{' to last '}' only; anything cleverer is a
    #: guess, and a guess is an error here.
    if isinstance(text, str) and "{" in text and "}" in text:
        try:
            return json.loads(text[text.index("{"): text.rindex("}") + 1])
        except ValueError:
            return None
    return None


def fire_llm(frame: dict, *, client: Callable[[str, str, dict], dict], model: str,
             sim_run_id: str, depot_id: str, cap_usd: float = DEFAULT_CAP_USD,
             ledger: SpendLedger | None = None, allow_unpriced: bool = False,
             max_vehicles: int = 24, max_stalls: int = 40,
             fired_at: str | None = None) -> dict:
    """Digest -> model -> rows, with the cap checked BEFORE the call. Pure apart
    from the client call and the ledger write; never raises for a bad answer."""
    sim_run_id = _require_uuid(sim_run_id, "sim_run_id")
    depot_id = _require_uuid(depot_id, "depot_id")
    ledger = ledger or SpendLedger(None)
    digest = frame_digest(frame, max_vehicles=max_vehicles, max_stalls=max_stalls)
    record: dict[str, Any] = {
        "source": SOURCE, "action_context": ACTION_CONTEXT,
        "sim_run_id": sim_run_id, "depot_id": depot_id,
        "fired_at": fired_at or datetime.now(timezone.utc).isoformat(),
        "frame_hash": content_hash(frame), "digest_hash": content_hash(digest),
        "system_prompt_hash": content_hash(SYSTEM_PROMPT),
        "model_requested": model, "n_vehicles": len(frame.get("vehicles") or []),
        "n_in_digest": len(digest["vehicles"]), "n_stalls_in_digest": len(digest["stalls"]),
        "omitted": digest["omitted"], "cap_usd": cap_usd,
        "spent_before_usd": round(ledger.spent(sim_run_id), 6),
        "price_source": PRICE_SOURCE,
    }
    if not digest["vehicles"]:
        record.update(status="empty", n_rows=0, n_planned=0, n_abstained=0, usd=0.0,
                      note="no serviceable vehicle with a readable soc in the frame")
        return {"rows": [], "fire": record}
    if model not in PRICES_USD_PER_MTOK and not allow_unpriced:
        record.update(status="refused_unpriced", n_rows=0, n_planned=0, n_abstained=0, usd=None,
                      error=f"model {model!r} has no price row; the cap cannot be enforced "
                            f"(pass allow_unpriced to run anyway)")
        return {"rows": [], "fire": record}
    if ledger.spent(sim_run_id) >= cap_usd:
        record.update(status="refused_cap", n_rows=0, n_planned=0, n_abstained=0, usd=0.0,
                      error=f"run has spent {ledger.spent(sim_run_id):.4f} USD of a "
                            f"{cap_usd:.2f} USD cap; not calling the model")
        return {"rows": [], "fire": record}

    try:
        reply = client(SYSTEM_PROMPT, user_prompt(digest), ANSWER_SCHEMA)
    except Exception as exc:  # the model is an external service; a failure is a ledger fact
        record.update(status="error", n_rows=0, n_planned=0, n_abstained=0, usd=None,
                      error=f"{type(exc).__name__}: {exc}"[:400])
        return {"rows": [], "fire": record}

    usage = reply.get("usage") or {}
    usd = cost_usd(model, usage)
    ledger.add(sim_run_id, usd)
    record.update(model=reply.get("model", model), usage=usage, usd=usd,
                  latency_ms=reply.get("latency_ms"), stop_reason=reply.get("stop_reason"),
                  spent_after_usd=round(ledger.spent(sim_run_id), 6))
    if reply.get("stop_reason") == "refusal":
        record.update(status="error", n_rows=0, n_planned=0, n_abstained=0,
                      error="model refused the request (stop_reason=refusal)")
        return {"rows": [], "fire": record}

    answer = _parse_json(reply.get("text", ""))
    rows, rejections = rows_from_answer(answer, digest, model=record["model"])
    planned = sum(1 for r in rows if not r["proposal"]["abstain"])
    record.update(
        status="proposed" if planned else "empty",
        n_rows=len(rows), n_planned=planned, n_abstained=len(rows) - planned,
        harness_rejections=rejections, n_harness_rejected=len(rejections),
        rationale=(str(answer.get("rationale", ""))[:600] if isinstance(answer, dict) else None),
        answer_hash=content_hash(reply.get("text", "")),
    )
    if answer is None:
        record["error"] = "model returned no parseable JSON; every vehicle abstained"
    return {"rows": rows, "fire": record}


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        prog="python3 -m bridge.llm_proposer",
        description="LLM advisor -> door-shaped rows. Offline: --frame + (--answer | a provider).")
    ap.add_argument("--run", required=True)
    ap.add_argument("--depot", required=True)
    ap.add_argument("--frame", required=True, help="decision frame JSON")
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--provider", choices=("anthropic", "nvidia", "fake"), default="anthropic")
    ap.add_argument("--answer", help="canned answer JSON (provider=fake); no model is called")
    ap.add_argument("--cap-usd", type=float, default=DEFAULT_CAP_USD)
    ap.add_argument("--spend-file", help="per-run spend ledger JSON (client-side cap guard)")
    ap.add_argument("--allow-unpriced", action="store_true")
    ap.add_argument("--effort", default="medium")
    ap.add_argument("--max-vehicles", type=int, default=24)
    ap.add_argument("--max-stalls", type=int, default=40)
    ap.add_argument("--ttl", type=int, default=60)
    ap.add_argument("--via", choices=("door", "batch"), default="door")
    ap.add_argument("--emit-sql")
    ap.add_argument("--json-out")
    args = ap.parse_args(argv)
    try:
        frame = json.loads(Path(args.frame).read_text())
        if args.provider == "fake" or args.answer:
            if not args.answer:
                ap.error("provider=fake needs --answer")
            client: Callable = FakeClient(json.loads(Path(args.answer).read_text()), model=args.model)
        elif args.provider == "anthropic":
            client = AnthropicClient(args.model, effort=args.effort)
        else:
            client = OpenAICompatibleClient(args.model)
        result = fire_llm(frame, client=client, model=args.model, sim_run_id=args.run,
                          depot_id=args.depot, cap_usd=args.cap_usd,
                          ledger=SpendLedger(args.spend_file), allow_unpriced=args.allow_unpriced,
                          max_vehicles=args.max_vehicles, max_stalls=args.max_stalls)
        sql = emit_sql(result, sim_run_id=args.run, depot_id=args.depot,
                       ttl_seconds=args.ttl, via=args.via)
        if args.emit_sql:
            Path(args.emit_sql).write_text(sql)
        else:
            sys.stdout.write(sql)
        if args.json_out:
            Path(args.json_out).write_text(json.dumps(result, indent=1, default=str))
        print(json.dumps(result["fire"], sort_keys=True, default=str), file=sys.stderr)
        return 0 if result["fire"]["status"] in ("proposed", "empty") else 3
    except BridgeError as exc:
        print(f"llm_proposer: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main())
