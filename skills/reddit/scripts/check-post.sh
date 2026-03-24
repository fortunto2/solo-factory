#!/usr/bin/env bash
# Read a Reddit post and its comments via public JSON API
# Usage: ./check-post.sh <post-url-or-id> [subreddit]
set -euo pipefail

INPUT="${1:?Usage: check-post.sh <url-or-post-id> [subreddit]}"

# Extract post path from URL or construct from ID
if [[ "$INPUT" == http* ]]; then
    # Extract path: /r/sub/comments/id/title/
    PATH_PART=$(echo "$INPUT" | sed 's|https\?://[^/]*/||; s|\.json.*||; s|/$||')
    URL="https://www.reddit.com/${PATH_PART}.json?limit=20"
else
    SUBREDDIT="${2:?Need subreddit for post ID}"
    URL="https://www.reddit.com/r/${SUBREDDIT}/comments/${INPUT}.json?limit=20"
fi

DATA=$(curl -s -H "User-Agent: solo-factory/1.0" "$URL")

echo "$DATA" | python3 -c "
import sys, json
from datetime import datetime

data = json.load(sys.stdin)

# Post data
post = data[0]['data']['children'][0]['data']
age_h = (datetime.now().timestamp() - post['created_utc']) / 3600

print('=' * 60)
print(f'Title: {post[\"title\"]}')
print(f'Author: u/{post[\"author\"]}')
print(f'Score: {post[\"score\"]} | Comments: {post[\"num_comments\"]} | Age: {age_h:.0f}h')
print(f'Flair: {post.get(\"link_flair_text\", \"none\")}')
print(f'URL: https://www.reddit.com{post[\"permalink\"]}')
print('=' * 60)

if post.get('selftext'):
    text = post['selftext'][:500]
    print(f'\n{text}')
    if len(post['selftext']) > 500:
        print(f'... ({len(post[\"selftext\"])} chars total)')
print()

# Comments
comments = data[1]['data']['children']
print(f'--- Top {len(comments)} comments ---')
print()

for c in comments:
    if c['kind'] != 't1':
        continue
    d = c['data']
    body = d.get('body', '')[:200]
    print(f'[{d.get(\"score\", 0):+d}] u/{d.get(\"author\", \"[deleted]\")}:')
    print(f'  {body}')
    if len(d.get('body', '')) > 200:
        print(f'  ... ({len(d[\"body\"])} chars)')
    print()
"
