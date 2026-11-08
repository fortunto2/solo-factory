#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# ///
"""Search Gmail through a `gws` wrapper and print `date | sender | subject`.

Usage: GWS_BIN=gws-personal uv run mail.py 'QUERY' [N] [--body]
GWS_BIN picks the mailbox (a wrapper that sets GOOGLE_WORKSPACE_CLI_CONFIG_DIR);
without it the bare `gws` default directory is used.
"""

import base64
import datetime
import json
import os
import subprocess
import sys


def gws(args):
    r = subprocess.run(
        [os.environ.get("GWS_BIN", "gws"), *args], capture_output=True, text=True
    )
    try:
        return json.loads(r.stdout)
    except ValueError:
        sys.stderr.write((r.stderr or r.stdout or "gws returned nothing")[:300] + "\n")
        return {}


def text_parts(p):
    if p.get("body", {}).get("data") and p.get("mimeType", "").startswith("text/"):
        yield base64.urlsafe_b64decode(p["body"]["data"]).decode("utf-8", "ignore")
    for c in p.get("parts") or []:
        yield from text_parts(c)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    q = sys.argv[1]
    n = int(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2].isdigit() else 25
    want_body = "--body" in sys.argv

    lst = gws(
        [
            "gmail",
            "users",
            "messages",
            "list",
            "--params",
            json.dumps({"userId": "me", "q": q, "maxResults": n}),
        ]
    )
    rows = []
    for m in lst.get("messages", []):
        d = gws(
            [
                "gmail",
                "users",
                "messages",
                "get",
                "--params",
                json.dumps(
                    {
                        "userId": "me",
                        "id": m["id"],
                        "format": "full" if want_body else "metadata",
                    }
                ),
            ]
        )
        h = {
            x["name"].lower(): x["value"]
            for x in d.get("payload", {}).get("headers", [])
        }
        ts = int(d.get("internalDate", 0)) // 1000  # internalDate, not the Date header
        date = datetime.datetime.fromtimestamp(ts).strftime("%Y-%m-%d") if ts else "?"
        rows.append(
            (date, h.get("from", "?")[:42], h.get("subject", "?")[:88], d, m["id"])
        )

    if not rows:
        print("no messages (check `auth status`: is this the mailbox you meant?)")
    for date, frm, subj, d, mid in sorted(rows, key=lambda r: r[:3]):
        print(f"{date} | {frm:44} | {subj} | {mid}")
        if want_body:
            body = "\n".join(text_parts(d.get("payload", {})))[:900]
            print("    " + body.replace("\n", "\n    ") + "\n")


if __name__ == "__main__":
    main()
