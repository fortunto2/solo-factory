#!/usr/bin/env python3
"""Enrich JSONL dependents with GitHub metadata via gh api.

Usage: python3 enrich.py <jsonl_path> [--batch 30]
"""

import json
import subprocess
import sys
import time
from pathlib import Path


def gh_api(endpoint: str) -> dict | None:
    """Call gh api and return parsed JSON."""
    try:
        result = subprocess.run(
            ["gh", "api", endpoint, "--jq", "."],
            capture_output=True,
            text=True,
            timeout=15,
        )
        if result.returncode == 0:
            return json.loads(result.stdout)
    except Exception:
        pass
    return None


def enrich_jsonl(path: str, batch_size: int = 30):
    jsonl_path = Path(path)
    lines = jsonl_path.read_text().strip().split("\n")
    entries = [json.loads(line) for line in lines if line.strip()]

    enriched_count = 0
    skipped_count = 0

    for i, entry in enumerate(entries):
        if entry.get("phase") != "raw":
            continue

        repo = entry["repo"]
        print(f"[{i + 1}/{len(entries)}] {repo}...", end=" ", flush=True)

        data = gh_api(f"repos/{repo}")

        if data is None:
            entry["phase"] = "skipped"
            entry["verdict_reason"] = "404 or private"
            skipped_count += 1
            print("SKIP (404)")
        elif data.get("archived"):
            entry.update(
                {
                    "stars": data.get("stargazers_count", 0),
                    "description": data.get("description", ""),
                    "archived": True,
                    "phase": "skipped",
                    "verdict_reason": "archived",
                }
            )
            skipped_count += 1
            print(f"SKIP (archived, {data.get('stargazers_count', 0)}★)")
        elif data.get("fork") and data.get("stargazers_count", 0) < 5:
            entry.update(
                {
                    "stars": data.get("stargazers_count", 0),
                    "description": data.get("description", ""),
                    "archived": False,
                    "phase": "skipped",
                    "verdict_reason": "low-star fork",
                }
            )
            skipped_count += 1
            print(f"SKIP (fork, {data.get('stargazers_count', 0)}★)")
        else:
            entry.update(
                {
                    "stars": data.get("stargazers_count", 0),
                    "description": data.get("description", ""),
                    "language": data.get("language", ""),
                    "last_push": data.get("pushed_at", ""),
                    "archived": False,
                    "fork": data.get("fork", False),
                    "has_issues": data.get("has_issues", True),
                    "topics": data.get("topics", []),
                    "phase": "enriched",
                }
            )
            enriched_count += 1
            print(f"OK ({data.get('stargazers_count', 0)}★)")

        # Save after each batch
        if (enriched_count + skipped_count) % batch_size == 0:
            with open(jsonl_path, "w") as f:
                for e in entries:
                    f.write(json.dumps(e, ensure_ascii=False) + "\n")
            print(f"  [saved, {enriched_count} enriched, {skipped_count} skipped]")
            time.sleep(2)  # Rate limit pause between batches

    # Final save
    with open(jsonl_path, "w") as f:
        for e in entries:
            f.write(json.dumps(e, ensure_ascii=False) + "\n")

    print(f"\nDone: {enriched_count} enriched, {skipped_count} skipped")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: enrich.py <jsonl_path> [--batch N]")
        sys.exit(1)

    batch = 30
    if "--batch" in sys.argv:
        idx = sys.argv.index("--batch")
        batch = int(sys.argv[idx + 1])

    enrich_jsonl(sys.argv[1], batch_size=batch)
