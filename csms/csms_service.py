"""OTTO-Q's charger back end as one service: the OCPP 2.0.1 back end listening on 127.0.0.1 only, and the live bridge
that has the twin's chargers speak to it (csms/README.md). This is what runs on the AWS box, in its own container.

    OTTOQ_CSMS_KEY_FILE=/run/secrets/ottoq_csms_key OTTOQ_CSMS_RELAY=https://<project>.supabase.co/functions/v1/ottoq-csms-relay \\
    OTTOQ_CSMS_STATE=/var/lib/ottoq-csms/relay.json python3 csms/csms_service.py

The back end listens on loopback because its only stations are the bridge's; a real charger needs a wss:// port with
TLS and OCPP security profile 2 or 3, which is a later step. The key is read from a file and never printed.
"""
from __future__ import annotations

import asyncio
import logging
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from csms_server import CSMS  # noqa: E402
from csms_relay import Relay, StateFile  # noqa: E402

log = logging.getLogger("ottoq.csms.service")


async def serve(relay_url: str, key: str, state_path: str, port: int, poll_s: float) -> None:
    csms = CSMS(log_frames=20000)
    bound = await csms.start("127.0.0.1", port)
    log.info("back end listening on ws://127.0.0.1:%s/<station id> (ocpp2.0.1)", bound)
    try:
        await Relay(relay_url, key, f"ws://127.0.0.1:{bound}", StateFile(state_path)).run(poll_s)
    finally:
        await csms.stop()


def main() -> int:  # pragma: no cover - the service entry point
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
    key_file = os.environ.get("OTTOQ_CSMS_KEY_FILE", "")
    relay_url = os.environ.get("OTTOQ_CSMS_RELAY", "")
    state = os.environ.get("OTTOQ_CSMS_STATE", "/var/lib/ottoq-csms/relay.json")
    if not key_file or not relay_url:
        print("set OTTOQ_CSMS_KEY_FILE and OTTOQ_CSMS_RELAY", file=sys.stderr)
        return 2
    with open(key_file, encoding="utf-8") as f:
        key = f.read().strip()
    if not key.startswith("ottow_"):
        print("the key file does not hold a source key", file=sys.stderr)
        return 2
    asyncio.run(serve(relay_url, key, state, int(os.environ.get("OTTOQ_CSMS_PORT", "9000")),
                      float(os.environ.get("OTTOQ_CSMS_POLL_S", "5"))))
    return 0


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main())
