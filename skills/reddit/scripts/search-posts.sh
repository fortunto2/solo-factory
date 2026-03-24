#!/usr/bin/env bash
# Search Reddit posts in a subreddit via public JSON API
# Usage: ./search-posts.sh <subreddit> [query] [sort: new|hot|rising]
set -euo pipefail

SUBREDDIT="${1:?Usage: search-posts.sh <subreddit> [query] [sort]}"
QUERY="${2:-}"
SORT="${3:-new}"

if [ -n "$QUERY" ]; then
    URL="https://www.reddit.com/r/${SUBREDDIT}/search.json?q=${QUERY}&restrict_sr=1&sort=relevance&t=week&limit=10"
else
    URL="https://www.reddit.com/r/${SUBREDDIT}/${SORT}.json?limit=10"
fi

DATA=$(curl -s -H "User-Agent: solo-factory/1.0" "$URL")

echo "$DATA" | python3 -c "
import sys, json
from datetime import datetime

data = json.load(sys.stdin)
posts = data.get('data', {}).get('children', [])

if not posts:
    print('No posts found')
    sys.exit(0)

print(f'Found {len(posts)} posts in r/${SUBREDDIT}:')
print()

for i, post in enumerate(posts, 1):
    d = post['data']
    age_h = (datetime.now().timestamp() - d['created_utc']) / 3600
    age = f'{age_h:.0f}h' if age_h < 48 else f'{age_h/24:.0f}d'

    print(f'{i:2d}. [{d[\"score\"]:4d} pts | {d[\"num_comments\"]:3d} comments | {age}]')
    print(f'    {d[\"title\"]}')
    print(f'    https://www.reddit.com{d[\"permalink\"]}')

    # Flag good candidates for commenting
    if 2 <= d['num_comments'] <= 30 and age_h < 48:
        print(f'    >>> GOOD CANDIDATE')
    print()
"
