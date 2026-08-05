---
name: solo-domain
description: Check whether a product name is actually free — across domain zones (RDAP + whois), the App Store, Google Play, GitHub and trademarks — before buying anything. Use when the user says "проверь домен", "свободно ли имя", "check this domain", "нужно название", "придумай имя проекту", is picking a brand, or is about to buy a domain. Do NOT use for DNS records, hosting or redirects on a domain already owned (that is /deploy).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "🔤"
allowed-tools: Bash, WebSearch, WebFetch, Read, Write
argument-hint: "[name or list of names]"
---

# domain — is this name actually free?

A name is not available because a domain is free. It has to be clear on **every surface the
product will live on**: the zones you will buy, the App Store (where names are unique and a
collision blocks release), Google Play, the code host, and the trademark register. Checking only
the domain is how people buy a domain for a name the App Store will later refuse.

Output: a table of candidates against those surfaces, and a recommendation that says what the
runner-up trades away.

## Workflow

1. **List candidates.** 6–12 names, including the user's own suggestions verbatim — they know
   their brand voice, and the job here is verification, not taste.
2. **Zones.** RDAP first, whois for ccTLDs — RDAP lies about them, see Gotchas.
3. **App Store.** Exact-name search. Do this *before* pricing domains: a blocked store name
   makes the domain worthless.
4. **Code host.** GitHub is a reliable signal; most social sites are not.
5. **Whatever sits on a taken `.com`.** Fetch its title. Parked junk, "Coming Soon" and a live
   business in the same category are three different risks, not one.
6. **Trademark.** Search the exact name plus "trademark". Flag holders who defend aggressively
   in that category.
7. **Recommend one**, with the trade-off stated.

### Zones

```sh
# RDAP: 404 = free, 200 = registered. -L is required — rdap.org answers 302 first.
avail() { [ "$(curl -sL -o /dev/null -w '%{http_code}' --max-time 20 \
  "https://rdap.org/domain/$1")" = "404" ] && echo FREE || echo taken; }

# ccTLDs (.co .io .me .ai …) — RDAP usually has no server for them, so whois is the source.
avail_cc() { whois "$1" 2>/dev/null | grep -qiE "no match|not found|no data found" \
  && echo FREE || echo taken; }
```

**Run the check against a domain known to be registered** (`google.com`, `google.co`) before
trusting a batch. That one control call is what separates a report from a guess.

### App Store

```sh
curl -s "https://itunes.apple.com/search?term=NAME&entity=software&limit=25&country=us" \
  | python3 -c "
import json,sys,re
n='NAME'.lower()
r=json.load(sys.stdin)['results']
hit=[a['trackName'] for a in r if n==re.sub(r'[^a-z0-9]','',a['trackName'].lower().split(':')[0])]
print('TAKEN: '+hit[0] if hit else 'free')"
```

Match the part **before the colon** — store names are `Brand: Subtitle` and the subtitle is
marketing, not identity. On a hit, follow up with
`https://itunes.apple.com/lookup?id=<trackId>`: an app with zero ratings and an untouched 1.0 is
a name collision, not a market leader, and that difference changes the advice you give.

### Code host

`curl -s -o /dev/null -w "%{http_code}" https://github.com/NAME` — 404 means free.

## Gotchas

- **RDAP returns 404 for entire ccTLD zones it has no server for.** `google.co` reports 404, i.e.
  "free". Every `.co`, `.io` or `.me` checked that way reads as available, and every one of those
  answers is worthless. Use whois there, and prove the method on a domain you know is taken.
- **`curl` without `-L` against rdap.org** returns 302 for everything, so free and taken look
  identical.
- **whois for `.app` and other Google Registry zones** often returns nothing at all — and empty
  output reads as "no match" to a careless grep, i.e. "free". RDAP works there; whois does not.
- **A taken `.com` is three different situations.** Fetch the `<title>`: a live business in the
  same category kills the name in every zone; a parking page costs only that zone; "Coming Soon"
  means someone is building right now, which is the worst case — they will look like a copy of
  you, or you of them.
- **Google Play's search page echoes the query string,** so grepping its HTML for the name
  matches the query itself and reports a collision that does not exist. Look for app cards.
- **X and Instagram return 200 for handles that do not exist** — they serve an app shell before
  resolving the name. As availability checks they are noise. GitHub's 404 is honest.
- **App Store names are unique per store.** A free domain plus a taken store name means the
  product cannot ship under that name. The store is the constraint that cannot be negotiated;
  check it first.

## Don't

- **Don't buy before the store check.** The domain is the cheap, reversible part.
- **Don't trust one method or one source.** Two independent signals (RDAP + DNS `NS`, or whois +
  the live site) cost seconds and catch every zone-wide false positive above.
- **Don't put the mechanism in the name** — `*AI`, `*GPT`, `*Chain`. It dates the brand to a
  single year, and in trust-sensitive categories (health, legal, immigration, finance) it
  advertises that a machine decides, which is the opposite of what those buyers are looking for.
- **Don't take a name whose `.com` runs a competitor**, even when your zone is free. You will
  feed their typo traffic forever and lose every trademark argument.
- **Don't promise the outcome in the name** in a regulated category — a brand that sounds like a
  guarantee ("approved", "granted") invites both the regulator and the disappointed customer.
  Optimism is fine; a promise is not.
- **Don't optimise only for English.** Check how the word lands in the languages the product
  actually sells in. A name that is a real word in each travels for free, and casual slang that
  reads as addressed to one gender quietly excludes half the market.
