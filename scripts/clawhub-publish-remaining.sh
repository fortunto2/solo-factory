#!/bin/bash
# Publish remaining skills to ClawHub with rate-limit awareness
# Runs unattended — waits between batches to avoid 5/hour limit

cd "$(dirname "$0")/.." || exit 1
LOG="/tmp/clawhub-publish-$(date +%Y%m%d-%H%M).log"

echo "=== ClawHub batch publish started $(date) ===" | tee "$LOG"

SKILLS=(
  metrics-track pipeline plan retro review
  scaffold seo-audit setup stream swarm
  validate video-promo you2idea-extract
)

published=0
failed=0

for skill in "${SKILLS[@]}"; do
  version=$(grep -A3 'metadata:' "skills/$skill/SKILL.md" | grep 'version:' | sed 's/.*version: *"\(.*\)"/\1/' | head -1)
  [ -z "$version" ] && version="1.0.0"

  echo -n "[$(date +%H:%M:%S)] solo-$skill@$version... " | tee -a "$LOG"

  result=$(pnpm dlx clawhub@latest publish "$(pwd)/skills/$skill" --slug "solo-$skill" --version "$version" --changelog "Initial publish" 2>&1)

  if echo "$result" | grep -q "OK. Published"; then
    echo "OK" | tee -a "$LOG"
    ((published++))
    sleep 4
  elif echo "$result" | grep -q "Rate limit"; then
    echo "RATE LIMITED — waiting 15 min..." | tee -a "$LOG"
    sleep 900
    # retry
    result=$(pnpm dlx clawhub@latest publish "$(pwd)/skills/$skill" --slug "solo-$skill" --version "$version" --changelog "Initial publish" 2>&1)
    if echo "$result" | grep -q "OK. Published"; then
      echo "[$(date +%H:%M:%S)] solo-$skill RETRY OK" | tee -a "$LOG"
      ((published++))
      sleep 4
    else
      echo "[$(date +%H:%M:%S)] solo-$skill RETRY FAILED: $(echo "$result" | tail -1)" | tee -a "$LOG"
      ((failed++))
    fi
  elif echo "$result" | grep -q "already exists"; then
    echo "SKIP (already exists)" | tee -a "$LOG"
  else
    echo "FAILED: $(echo "$result" | tail -1)" | tee -a "$LOG"
    ((failed++))
  fi
done

echo "" | tee -a "$LOG"
echo "=== Done $(date) ===" | tee -a "$LOG"
echo "Published: $published | Failed: $failed | Log: $LOG" | tee -a "$LOG"
