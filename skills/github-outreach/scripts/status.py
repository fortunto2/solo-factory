#!/usr/bin/env python3
"""Show outreach pipeline status from JSONL.

Usage: python3 status.py <jsonl_path> [--targets] [--csv]
"""

import json
import sys
from collections import Counter
from pathlib import Path


def show_status(path: str, show_targets: bool = False, csv_mode: bool = False):
    jsonl_path = Path(path)
    if not jsonl_path.exists():
        print(f"Not found: {path}")
        sys.exit(1)

    lines = jsonl_path.read_text().strip().split("\n")
    entries = [json.loads(line) for line in lines if line.strip()]

    # Phase counts
    phases = Counter(e.get("phase", "raw") for e in entries)
    verdicts = Counter(
        e.get("verdict", "") for e in entries if e.get("phase") == "evaluated"
    )

    if csv_mode:
        # CSV output for spreadsheet
        print("repo,stars,phase,verdict,features_used,our_advantages,verdict_reason")
        for e in sorted(entries, key=lambda x: x.get("stars", 0), reverse=True):
            features = ";".join(e.get("features_used", []))
            advantages = ";".join(e.get("our_advantages", []))
            print(
                f"{e['repo']},{e.get('stars', 0)},{e.get('phase', 'raw')},"
                f"{e.get('verdict', '')},{features},{advantages},"
                f"{e.get('verdict_reason', '')}"
            )
        return

    # Summary
    print("\nOutreach Pipeline Status")
    print(f"{'=' * 35}")
    print(f"Total repos:     {len(entries)}")
    print()

    print("Phase            Count")
    print(f"{'-' * 35}")
    for phase in ["raw", "enriched", "evaluated", "drafted", "posted", "skipped"]:
        count = phases.get(phase, 0)
        if count > 0:
            print(f"  {phase:<15} {count:>5}")
            if phase == "evaluated":
                for v in ["target", "maybe", "skip"]:
                    vc = verdicts.get(v, 0)
                    if vc > 0:
                        print(f"    -> {v:<13} {vc:>3}")
    print(f"{'-' * 35}")

    # Top targets
    targets = [
        e
        for e in entries
        if e.get("verdict") == "target" and e.get("phase") in ("evaluated", "drafted")
    ]
    targets.sort(key=lambda x: x.get("stars", 0), reverse=True)

    if targets:
        print(f"\nTop targets ({len(targets)}):")
        for t in targets[:10]:
            advantages = ", ".join(t.get("our_advantages", [])[:3])
            print(f"  {t.get('stars', 0):>6}★  {t['repo']:<40} {advantages}")

    # Top enriched (not yet evaluated)
    if show_targets:
        pending = [e for e in entries if e.get("phase") == "enriched"]
        pending.sort(key=lambda x: x.get("stars", 0), reverse=True)
        if pending:
            print(f"\nNext to evaluate ({len(pending)} pending):")
            for p in pending[:15]:
                desc = (p.get("description") or "")[:50]
                print(f"  {p.get('stars', 0):>6}★  {p['repo']:<40} {desc}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: status.py <jsonl_path> [--targets] [--csv]")
        sys.exit(1)

    show_status(
        sys.argv[1],
        show_targets="--targets" in sys.argv,
        csv_mode="--csv" in sys.argv,
    )
