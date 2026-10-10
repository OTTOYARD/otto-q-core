"""The live bridge: read the twin's charger frames through ottoq-csms-relay, have each charger say them to the back end,
and report what the back end did with them. Runs beside csms_server.py on the back end's machine (csms/README.md).

    python3 csms/relay.py --relay https://<project>.supabase.co/functions/v1/ottoq-csms-relay \\
                          --csms ws://127.0.0.1:9000 --state /var/lib/ottoq-csms/relay.json

The key is read from the environment (OTTOQ_CSMS_KEY) or a file (--key-file), never from the command line, and is
never printed or logged. It is a charger_backend source key made on this machine; only its SHA-256 was registered
(db/migrations/0697).

Each round: read up to 500 frames after the cursor, deliver them in order (bridge.ChargerBridge), then write the new
cursor and the batch's report to the state file before sending the report, and clear it once the relay has kept it. A
crash between the two re-sends the report and never re-delivers the frames, so the back end hears each frame once. One
case does repeat frames: the back end going away in the middle of a batch, after which the batch is said again from its
first frame. The first round, with no state, starts at the head: what the chargers send from now on.
"""
from __future__ import annotations

import argparse
import asyncio
import json
import logging
import os
import sys
import urllib.error
import urllib.request
from collections import Counter
from importlib import metadata
from typing import Any, Callable

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bridge import ChargerBridge, Delivery, StationFacts, TwinFrame  # noqa: E402

log = logging.getLogger("ottoq.csms.relay")
KEY_HEADER = "x-otto-q-api-key"


def _version(pkg: str) -> str | None:
    try:
        return metadata.version(pkg)
    except metadata.PackageNotFoundError:
        return None


BRIDGE_INFO = {"bridge": "csms/relay.py", "ocpp": _version("ocpp"), "websockets": _version("websockets")}


class RelayError(Exception):
    def __init__(self, status: int, body: Any):
        super().__init__(f"relay answered {status}: {body}")
        self.status, self.body = status, body


def http_json(method: str, url: str, key: str, body: Any | None = None, timeout: float = 30.0) -> Any:
    """One request to the relay with the key in its header. Raises RelayError on any status but 200."""
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method, headers={KEY_HEADER: key, "Accept": "application/json",
                                                                         **({"Content-Type": "application/json"} if data else {})})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as res:
            return json.loads(res.read().decode() or "null")
    except urllib.error.HTTPError as e:
        try:
            payload = json.loads(e.read().decode() or "null")
        except ValueError:
            payload = None
        raise RelayError(e.code, payload) from None


def transactions_seen(frames: list[TwinFrame], deliveries: list[Delivery]) -> dict[str, Any]:
    """The transactions this batch's accepted TransactionEvents opened, continued and closed, from the frames themselves."""
    ok = {d.seq for d in deliveries if d.outcome == "accepted" and d.action == "TransactionEvent"}
    tx: dict[str, list[tuple[int, str]]] = {}
    for f in frames:
        if f.seq in ok:
            info = f.payload.get("transactionInfo") or {}
            tx.setdefault(f"{f.station_id}/{info.get('transactionId')}", []).append((int(f.payload.get("seqNo", -1)), f.payload.get("eventType")))
    in_order = sum(1 for evs in tx.values() if [s for s, _ in evs] == sorted({s for s, _ in evs}))
    return {"transactions": len(tx), "started": sum(1 for evs in tx.values() if evs[0][1] == "Started"),
            "ended": sum(1 for evs in tx.values() if evs[-1][1] == "Ended"), "seq_in_order": in_order}


def batch_report(frames: list[TwinFrame], deliveries: list[Delivery], after: int, next_after: int) -> dict[str, Any]:
    out = Counter(d.outcome for d in deliveries)
    return {
        "from_seq": after + 1 if frames else next_after, "to_seq": next_after, "frames": len(deliveries),
        "outcomes": {k: out.get(k, 0) for k in ("accepted", "not_2_0_1", "csms_error", "not_a_station_frame")},
        "by_action": {f"{a}:{o}": n for (a, o), n in sorted(Counter((d.action, d.outcome) for d in deliveries).items())},
        "transactions": transactions_seen(frames, deliveries),
        "first_refusals": [{"seq": d.seq, "station": d.station_id, "action": d.action, "outcome": d.outcome,
                            "error": (d.error or "")[:300]} for d in deliveries if d.outcome != "accepted"][:10],
        "bridge": BRIDGE_INFO,
    }


class StateFile:
    """The cursor, and a report not yet kept by the relay. Written whole and renamed into place."""

    def __init__(self, path: str):
        self.path = path

    def load(self) -> dict[str, Any]:
        try:
            with open(self.path, encoding="utf-8") as f:
                return json.load(f)
        except FileNotFoundError:
            return {}

    def save(self, state: dict[str, Any]) -> None:
        tmp = self.path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(state, f)
        os.replace(tmp, self.path)


class Relay:
    """One relay loop. ``request`` is http_json by default; tests give it a fake."""

    def __init__(self, relay_url: str, key: str, csms_url: str, state: StateFile, *, limit: int = 500,
                 request: Callable[..., Any] = http_json):
        self.relay_url, self.key, self.csms_url, self.state, self.limit = relay_url.rstrip("/"), key, csms_url, state, limit
        self.request = request
        self.bridge: ChargerBridge | None = None

    async def _call(self, method: str, path: str, body: Any | None = None) -> Any:
        return await asyncio.to_thread(self.request, method, f"{self.relay_url}{path}", self.key, body)

    async def _flush_pending(self, st: dict[str, Any]) -> None:
        if st.get("pending_report"):
            res = await self._call("POST", "/report", st["pending_report"])
            st["pending_report"] = None
            st["last_report_id"] = res.get("report_id")
            self.state.save(st)

    async def round(self) -> dict[str, Any]:
        """Deliver one batch. Returns {frames, more, report_id}."""
        st = self.state.load()
        await self._flush_pending(st)
        if self.bridge is None or "cursor" not in st:
            head = await self._call("GET", f"/frames?after={st.get('cursor', -1)}&limit={self.limit}&chargers=true")
            facts = {c["ocpp_identifier"]: StationFacts(c["ocpp_identifier"], c.get("vendor") or "OTTOYARD twin",
                                                        c.get("model") or "sim", c.get("serial_number"),
                                                        c.get("firmware_version"))
                     for c in head.get("chargers") or []}
            self.bridge = ChargerBridge(self.csms_url, facts=facts)
            if "cursor" not in st:   # the first round: start at the head
                st["cursor"] = int(head["next_after"])
                self.state.save(st)
                return {"frames": 0, "more": False, "report_id": None}
            page = head
        else:
            page = await self._call("GET", f"/frames?after={st['cursor']}&limit={self.limit}")
        frames = [TwinFrame.from_row(r) for r in page.get("rows") or []]
        if not frames:
            return {"frames": 0, "more": False, "report_id": None}
        deliveries = await self.bridge.deliver(frames)
        after, next_after = int(st["cursor"]), int(page["next_after"])
        st["cursor"], st["pending_report"] = next_after, batch_report(frames, deliveries, after, next_after)
        self.state.save(st)   # the frames are said: never say them again, and the report survives a crash
        await self._flush_pending(st)
        return {"frames": len(frames), "more": bool(page.get("more")), "report_id": st.get("last_report_id")}

    async def run(self, poll_s: float = 5.0, stop: asyncio.Event | None = None) -> None:  # pragma: no cover - the service
        while stop is None or not stop.is_set():
            try:
                r = await self.round()
                if r["frames"]:
                    log.info("delivered %s frames, report %s", r["frames"], r["report_id"])
                if r["more"]:
                    continue
            except RelayError as e:
                log.warning("%s", e)
            except Exception as e:   # the back end or the relay went away mid-batch; reconnect every station next round
                log.warning("round failed, reconnecting: %s: %s", type(e).__name__, e)
                if self.bridge is not None:
                    try:
                        await self.bridge.close()
                    except Exception:
                        pass
                    self.bridge = None
            await asyncio.sleep(poll_s)


def main(argv: list[str] | None = None) -> int:  # pragma: no cover - the command line
    ap = argparse.ArgumentParser(description="The twin's chargers, live, through OTTO-Q's OCPP 2.0.1 back end.")
    ap.add_argument("--relay", required=True, help="the ottoq-csms-relay function's URL")
    ap.add_argument("--csms", default="ws://127.0.0.1:9000", help="the back end's WebSocket URL")
    ap.add_argument("--state", required=True, help="where the cursor and an unsent report are kept")
    ap.add_argument("--key-file", help="a file holding the key (else OTTOQ_CSMS_KEY)")
    ap.add_argument("--poll", type=float, default=5.0)
    a = ap.parse_args(argv)
    key = (open(a.key_file, encoding="utf-8").read() if a.key_file else os.environ.get("OTTOQ_CSMS_KEY", "")).strip()
    if not key.startswith("ottow_"):
        print("no key: set OTTOQ_CSMS_KEY or --key-file", file=sys.stderr)
        return 2
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    asyncio.run(Relay(a.relay, key, a.csms, StateFile(a.state)).run(a.poll))
    return 0


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main())
