#!/usr/bin/env python3
"""Convert raw repo list (one per line) to JSONL.

Usage: python3 init_jsonl.py <repos_file> <output_jsonl>
       cat repos.txt | python3 init_jsonl.py - output.jsonl
"""

import json
import sys
from pathlib import Path


def main():
    if len(sys.argv) < 3:
        print("Usage: init_jsonl.py <repos_file_or_-> <output.jsonl>")
        sys.exit(1)

    src = sys.argv[1]
    out = Path(sys.argv[2])

    if src == "-":
        lines = sys.stdin.read().strip().split("\n")
    else:
        lines = Path(src).read_text().strip().split("\n")

    repos = [line.strip() for line in lines if line.strip() and "/" in line]

    with open(out, "w") as f:
        for repo in repos:
            entry = {
                "repo": repo,
                "url": f"https://github.com/{repo}",
                "phase": "raw",
                "stars": 0,
                "description": "",
                "language": "",
                "last_push": "",
                "archived": False,
                "score": 0,
                "features_used": [],
                "our_advantages": [],
                "verdict": "",
                "verdict_reason": "",
                "draft_title": "",
                "draft_body": "",
                "issue_url": "",
                "evaluated_at": "",
                "notes": "",
            }
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")

    print(f"Created {out} with {len(repos)} entries")


if __name__ == "__main__":
    main()
