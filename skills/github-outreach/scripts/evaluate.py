#!/usr/bin/env python3
"""Evaluate a single repo from JSONL — read README + Cargo.toml via gh api.

Usage: python3 evaluate.py <jsonl_path> <owner/repo>
       python3 evaluate.py <jsonl_path> --next       # Pick next enriched by stars
"""

import base64
import json
import subprocess
import sys
from datetime import datetime
from pathlib import Path


def gh_api(endpoint: str, jq: str = ".") -> str | None:
    try:
        result = subprocess.run(
            ["gh", "api", endpoint, "--jq", jq],
            capture_output=True,
            text=True,
            timeout=15,
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception:
        pass
    return None


def gh_content(repo: str, path: str) -> str | None:
    """Fetch file content from repo via gh api."""
    raw = gh_api(f"repos/{repo}/contents/{path}", ".content")
    if raw:
        try:
            return base64.b64decode(raw).decode("utf-8", errors="replace")
        except Exception:
            pass
    return None


def evaluate_repo(entry: dict) -> dict:
    """Evaluate a single repo and return updated entry."""
    repo = entry["repo"]
    stars = entry.get("stars", 0)

    print(f"\nEvaluating: {repo} ({stars}★)")
    print("=" * 50)

    # Read README
    readme = gh_content(repo, "README.md")
    if readme:
        print(f"README: {len(readme)} chars")
        print(f"  Preview: {readme[:200]}...")
    else:
        print("README: not found")

    # Read Cargo.toml
    cargo = gh_content(repo, "Cargo.toml")
    if cargo:
        print("Cargo.toml: found")
        # Extract async-openai usage
        for line in cargo.split("\n"):
            if "async-openai" in line.lower() or "openai" in line.lower():
                print(f"  {line.strip()}")
    else:
        print("Cargo.toml: not found (maybe workspace?)")
        # Try common paths
        for alt in ["crates/core/Cargo.toml", "src/Cargo.toml", "backend/Cargo.toml"]:
            cargo = gh_content(repo, alt)
            if cargo:
                print(f"  Found at {alt}")
                break

    # Detect features
    features = []
    all_text = (readme or "") + (cargo or "")
    lower_text = all_text.lower()

    feature_signals = {
        "streaming": ["stream", "sse", "event-stream", "create_stream"],
        "tools": ["tool_call", "function_call", "tool_choice", "function_calling"],
        "structured": ["json_schema", "response_format", "structured", "schemars"],
        "embeddings": ["embedding", "vector", "similarity"],
        "agent_loop": ["agent", "loop", "iteration", "multi-turn", "conversation"],
        "audio": ["audio", "transcription", "speech", "whisper", "tts"],
        "images": ["image", "dall-e", "generate.*image"],
        "realtime": ["realtime", "websocket", "wss://"],
        "wasm": ["wasm", "cloudflare", "worker", "edge"],
    }

    for feature, signals in feature_signals.items():
        if any(s in lower_text for s in signals):
            features.append(feature)

    print(f"Features detected: {features}")

    # Determine our advantages for this repo
    advantage_map = {
        "streaming": "stream_helpers",
        "tools": "structured_outputs",
        "structured": "structured_outputs",
        "agent_loop": "persistent_websockets",
        "realtime": "persistent_websockets",
        "wasm": "wasm_builtin",
    }
    our_advantages = list(set(advantage_map[f] for f in features if f in advantage_map))
    print(f"Our advantages: {our_advantages}")

    # Score
    score = 0
    # Stars component (0-30)
    if stars >= 1000:
        score += 30
    elif stars >= 100:
        score += 25
    elif stars >= 20:
        score += 15
    elif stars >= 5:
        score += 10

    # Activity (0-20)
    last_push = entry.get("last_push", "")
    if last_push:
        try:
            pushed = datetime.fromisoformat(last_push.replace("Z", "+00:00"))
            days = (datetime.now(pushed.tzinfo) - pushed).days
            if days < 30:
                score += 20
            elif days < 90:
                score += 15
            elif days < 180:
                score += 10
        except Exception:
            score += 5

    # Feature fit (0-30)
    score += min(len(our_advantages) * 10, 30)

    # Approachability (0-20)
    if entry.get("has_issues", True):
        score += 10
    if not entry.get("fork", False):
        score += 10

    # Verdict
    if score >= 60:
        verdict = "target"
    elif score >= 30:
        verdict = "maybe"
    else:
        verdict = "skip"

    print(f"Score: {score}/100 → {verdict}")

    entry.update(
        {
            "phase": "evaluated",
            "score": score,
            "features_used": features,
            "our_advantages": our_advantages,
            "verdict": verdict,
            "evaluated_at": datetime.now().isoformat(),
        }
    )

    return entry


def main():
    if len(sys.argv) < 2:
        print("Usage: evaluate.py <jsonl_path> <owner/repo>")
        print("       evaluate.py <jsonl_path> --next")
        sys.exit(1)

    jsonl_path = Path(sys.argv[1])
    lines = jsonl_path.read_text().strip().split("\n")
    entries = [json.loads(line) for line in lines if line.strip()]

    if len(sys.argv) >= 3 and sys.argv[2] == "--next":
        # Pick next enriched by stars
        enriched = [e for e in entries if e.get("phase") == "enriched"]
        enriched.sort(key=lambda x: x.get("stars", 0), reverse=True)
        if not enriched:
            print("No enriched repos to evaluate")
            sys.exit(0)
        target_repo = enriched[0]["repo"]
    else:
        target_repo = sys.argv[2]

    # Find and evaluate
    for i, entry in enumerate(entries):
        if entry["repo"] == target_repo:
            entries[i] = evaluate_repo(entry)
            break
    else:
        print(f"Repo not found: {target_repo}")
        sys.exit(1)

    # Save
    with open(jsonl_path, "w") as f:
        for e in entries:
            f.write(json.dumps(e, ensure_ascii=False) + "\n")

    print(f"\nSaved to {jsonl_path}")


if __name__ == "__main__":
    main()
