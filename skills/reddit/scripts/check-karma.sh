#!/usr/bin/env bash
# Check Reddit user karma and account age via public JSON API
# Usage: ./check-karma.sh <username>
set -euo pipefail

USERNAME="${1:?Usage: check-karma.sh <username>}"
URL="https://www.reddit.com/user/${USERNAME}/about.json"

DATA=$(curl -s -H "User-Agent: solo-factory/1.0" "$URL")

if echo "$DATA" | grep -q '"error"'; then
    echo "Error: account not found or banned"
    echo "$DATA" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin), indent=2))" 2>/dev/null || echo "$DATA"
    exit 1
fi

echo "$DATA" | python3 -c "
import sys, json
from datetime import datetime

d = json.load(sys.stdin)['data']
created = datetime.fromtimestamp(d['created_utc'])
age_days = (datetime.now() - created).days

print(f\"Username:       {d['name']}\")
print(f\"Comment karma:  {d.get('comment_karma', 0)}\")
print(f\"Post karma:     {d.get('link_karma', 0)}\")
print(f\"Total karma:    {d.get('total_karma', 0)}\")
print(f\"Account age:    {age_days} days ({age_days // 365}y {age_days % 365}d)\")
print(f\"Verified email: {d.get('has_verified_email', False)}\")
print(f\"Suspended:      {d.get('is_suspended', False)}\")
print()

total = d.get('total_karma', 0)
if total < 50:
    print('Status: LOW KARMA — comment only, no links, no self-promo')
elif total < 200:
    print('Status: BUILDING — can post in promo-friendly subs (r/SideProject)')
elif total < 1000:
    print('Status: ESTABLISHED — can post in most subs with context')
else:
    print('Status: TRUSTED — full posting privileges')
"
