#!/usr/bin/env python3
"""Read-only SQL against production (otto-q-core) through the Supabase Management API.

Every query goes to POST /v1/projects/{ref}/database/query/read-only, which runs it as
`supabase_read_only_user` with `transaction_read_only = on` (read 2026-11-04: current_user
supabase_read_only_user, transaction_read_only on, statement_timeout 2min). The endpoint and
its body schema are from the Management API's OpenAPI document,
https://api.supabase.com/api/v1-json (operationId v1-read-only-query, "Beta", read 2026-11-04).

So production refuses any write from this module, whatever SQL it is handed. It reads one
project only, and the token is read from the environment and never printed or stored:
SUPABASE_ACCESS_TOKEN, or Supabase_Key (the name the session environment uses).

    python -I prod_read.py 'select 1'            # prints the JSON rows
    python -I prod_read.py -f q.sql -o out.json  # query from a file, rows to a file
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

PROJECT_REF = "gxdrcyphqjzjsuhxuqtg"  # otto-q-core, the engine; the only project read here
ENDPOINT = f"https://api.supabase.com/v1/projects/{PROJECT_REF}/database/query/read-only"


class ProdReadError(RuntimeError):
    pass


def _token() -> str:
    for name in ("SUPABASE_ACCESS_TOKEN", "Supabase_Key"):
        value = os.environ.get(name, "").strip()
        if value:
            return value
    raise ProdReadError("no Supabase access token: set SUPABASE_ACCESS_TOKEN (or Supabase_Key)")


def query(sql: str, *, retries: int = 6, timeout: int = 300) -> list[dict]:
    """Run one read-only statement on production and return its rows."""
    body = json.dumps({"query": sql}).encode()
    delay = 2.0
    for attempt in range(retries + 1):
        req = urllib.request.Request(
            ENDPOINT,
            data=body,
            method="POST",
            headers={"Authorization": "Bearer " + _token(), "Content-Type": "application/json",
                     "User-Agent": "ottoq-lab-prod-read"},
        )
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return json.loads(resp.read().decode())
        except urllib.error.HTTPError as e:
            text = e.read().decode(errors="replace")[:2000]
            if e.code in (429, 500, 502, 503, 504) and attempt < retries and "error" not in text.lower():
                time.sleep(delay)
                delay *= 2
                continue
            if e.code in (429, 502, 503, 504) and attempt < retries:
                time.sleep(delay)
                delay *= 2
                continue
            raise ProdReadError(f"HTTP {e.code}: {text}") from None
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            if attempt < retries:
                time.sleep(delay)
                delay *= 2
                continue
            raise ProdReadError(f"network: {e}") from None
    raise ProdReadError("unreachable")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("sql", nargs="?")
    ap.add_argument("-f", "--file")
    ap.add_argument("-o", "--out")
    a = ap.parse_args()
    sql = open(a.file).read() if a.file else a.sql
    if not sql:
        ap.error("give SQL or -f FILE")
    rows = query(sql)
    text = json.dumps(rows, indent=None, separators=(",", ":"), ensure_ascii=False)
    if a.out:
        with open(a.out, "w") as fh:
            fh.write(text)
        print(f"{len(rows)} rows -> {a.out}", file=sys.stderr)
    else:
        print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
