#!/usr/bin/env bash
# Recent posts in a subreddit, optionally only those that say a phrase.
# Usage: ./search-posts.sh <subreddit> [query] [hours, default 168]
#
# Reddit's own JSON refuses anonymous clients (403 on www, a login redirect on old.reddit,
# 429 on RSS; seen Nov 2026), so this reads the Arctic Shift mirror
# (arctic-shift.photon-reddit.com: keyless, posts within seconds, scores refreshed).
# Its server-side keyword search times out on busy subreddits, so the phrase is matched
# here over the newest posts (up to 300).
set -euo pipefail

SUBREDDIT="${1:?Usage: search-posts.sh <subreddit> [query] [hours]}"
QUERY="${2:-}"
HOURS="${3:-168}"

python3 - "$SUBREDDIT" "$QUERY" "$HOURS" <<'PY'
import json, re, sys, time, urllib.parse, urllib.request

sub, query, hours = sys.argv[1], sys.argv[2], float(sys.argv[3])
now = int(time.time())
after, before, posts = int(now - hours * 3600), now, []
for _ in range(3):
    params = {"subreddit": sub, "after": after, "before": before, "limit": 100, "sort": "desc",
              "fields": "id,subreddit,title,selftext,score,num_comments,created_utc"}
    url = "https://arctic-shift.photon-reddit.com/api/posts/search?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": "solo-factory-reddit/1.0"})
    page, err = None, None
    for wait in (0, 5):  # a 422 there means "Timeout. Maybe slow down a bit": one retry answers
        time.sleep(wait)
        try:
            page = json.load(urllib.request.urlopen(req, timeout=30)).get("data") or []
            break
        except Exception as e:  # noqa: BLE001
            err = e
    if page is None:
        if not posts:
            sys.exit(f"Arctic Shift did not answer for r/{sub}: {err}")
        break
    posts += page
    if len(page) < 100:
        break
    before = min(p["created_utc"] for p in page)
    time.sleep(2)

if query:  # words in order, joined by nothing, a space, - or _; whole words only
    parts = [re.escape(w) for w in re.findall(r"[a-z]+|[0-9]+|[^a-z0-9\s_-]+", query.lower())]
    pat = re.compile(r"(?<![a-z0-9])" + r"[\s_-]?".join(parts) + r"(?![a-z0-9])", re.I)
    posts = [p for p in posts if pat.search(f"{p.get('title') or ''} {p.get('selftext') or ''}")]

if not posts:
    print("No posts found")
    sys.exit(0)

posts.sort(key=lambda p: -(p.get("score") or 0))
print(f"Found {len(posts)} posts in r/{sub} (last {hours:.0f} h{', matching ' + repr(query) if query else ''}):\n")
for i, p in enumerate(posts[:15], 1):
    age_h = (now - p["created_utc"]) / 3600
    age = f"{age_h:.0f}h" if age_h < 48 else f"{age_h / 24:.0f}d"
    print(f"{i:2d}. [{p.get('score') or 0:4d} pts | {p.get('num_comments') or 0:3d} comments | {age}]")
    print(f"    {p.get('title')}")
    print(f"    https://www.reddit.com/r/{p['subreddit']}/comments/{p['id']}/")
    if 2 <= (p.get("num_comments") or 0) <= 30 and age_h < 48:  # small, live thread: room to add something
        print("    >>> GOOD CANDIDATE")
    print()
PY
