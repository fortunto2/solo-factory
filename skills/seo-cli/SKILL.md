---
name: solo-seo-cli
description: Manage SEO and agent-readiness for all sites via the `seo` CLI — audit pages for SEO+GEO score, run `agent-audit` to check whether AI agents can discover and read a site (robots rules, Content-Signals, llms.txt, markdown negotiation, MCP cards), check Search Console analytics, submit sitemaps, ping IndexNow, inspect indexing. Covers Google, Bing, Yandex. Also points at superduper-analytics for who actually visited, which AI agents read the site, and what each campaign produced. Covers Bing Webmaster API (a second index, and the one ChatGPT and Copilot read). Use when the user asks about search performance, indexing, SEO/GEO score, agent-readiness, llms.txt, MCP, or wants to fix a site. Do NOT use for writing landing copy (/landing-gen).
license: MIT
metadata:
  author: fortunto2
  version: "1.3.1"
  openclaw:
    emoji: "🔍"
allowed-tools: Read, Grep, Bash, Glob, Edit, Write, WebFetch
argument-hint: "[url]"
---

# SEO CLI Skill

Unified search engine management and SEO/GEO auditing for all configured sites.

## Running it

`seo` is installed globally as a wrapper at `~/.local/bin/seo`. Just call it:

```bash
seo audit https://example.com
```

If the command is missing, recreate the wrapper (the project keeps `cli.py` and `config.yaml` side
by side and is **not** packaged for `uv tool install` — a global install fails with
`ModuleNotFoundError: No module named 'cli'`):

```bash
cat > ~/.local/bin/seo <<'EOF'
#!/bin/sh
SEO_HOME="$HOME/startups/shared/seo-cli"
exec "$SEO_HOME/.venv/bin/python" "$SEO_HOME/cli.py" "$@"
EOF
chmod +x ~/.local/bin/seo
```

Source lives in `~/startups/shared/seo-cli/`. Do **not** build a `SEO=...` shell variable holding
two words — in zsh it is not word-split and the call fails.

## Commands

### Audit — SEO+GEO health check
```bash
# Summary table across ALL sites (fast, no PageSpeed)
seo audit

# Detailed single-site audit with PageSpeed + keywords
seo audit https://superduperai.co
```

### Agent audit — what an AI agent can discover, read and act on
```bash
seo agent-audit                          # every configured site
seo agent-audit https://example.com      # one site, full detail
```

A site now has two audiences, and this checks the second: robots rules naming GPTBot and
friends, Content-Signals, llms.txt, markdown negotiation, MCP and A2A cards.

**It probes a path that cannot exist before anything else.** A great many sites answer 200
with their home page for every URL, and a checker that trusts status codes then reports a
perfect score for a site that has none of it — life2film.com scored 12/12 that way while every
response was the same HTML page. Its real score was 5. When that probe returns 200 the report
says so at the top and verifies content instead: JSON must parse, text must not be HTML.

Markdown negotiation is tested on the home page **and** on a real page from the sitemap. Sites
whose root is an index have no markdown twin for it while every article does, and probing only
`/` calls that "no negotiation" — the same false negative pointing the other way.

Read the score as three tiers, not one number:

| Tier | Checks | Treat as |
|---|---|---|
| Server honesty | Distinct 404s | **Fix first.** Everything else is unreliable until this passes, and Google counts soft 404s as a quality problem |
| Table stakes | robots.txt, sitemap, llms.txt, AI bot rules, Content-Signals | Should all pass on every site |
| Optional | MCP card, A2A card, API catalog, OAuth | Publish **only if real** — an empty catalogue raises the score and tells an agent something untrue |

### Traffic — who actually came, from our own analytics
```bash
seo products              # every registered product, and whether its counter reports
seo traffic --days 7      # people, page views, engagement, bot volume per product
seo agents                # which AI agents read the sites, and why they came
```

These talk to `superduper-analytics` over MCP — the same server Claude and ChatGPT connect to,
so there is one contract rather than a private endpoint alongside it. The server offers eight
tools; the CLI wraps the three above, and the rest are worth calling directly when the question
is sharper:

| tool | answers |
|---|---|
| `search` | where Google shows us and at what rank — the ONLY leading indicator |
| `content` | referrer hosts, top paths, countries |
| `campaigns` | what each `utm_campaign` brought, down to store clicks |
| `goals` | downloads, store links, signups — what the site exists to produce |
| `counter_coverage` | which zones report and which are silent |

Configure once in `config.yaml`:

```yaml
analytics:
  url: "https://analytics.superduperai.co/mcp"
  key: ""   # the Worker's DASHBOARD_KEY secret
```

**Run `seo products` before drawing any conclusion from the other two.** A product with no
counter installed reports zero traffic for reasons that have nothing to do with how it is
doing, and a zero read as a verdict is the easiest mistake here.

Output is printed verbatim, including the sentence that says when sampling made the people
figure a lower bound. That is the point — an evaluation has to tell a small number from an
unreliable one.

### Bing — a second index, and the one AI answers read

Bing is not only Bing: **ChatGPT Search and Copilot read its index**, and its Webmaster Tools
report AI citations, which no other console does. A site invisible there is invisible to those
answers regardless of how it ranks in Google.

```yaml
bing:
  api_key: "..."   # Bing Webmaster Tools > Settings > API Access > Generate
```

Without that key the Bing calls in `seo launch` and `seo reindex` **do nothing and say nothing** —
the config ships with `api_key: ""`, which reads as configured. Check it before believing a
green run:

```bash
curl -s "https://ssl.bing.com/webmaster/api.svc/json/GetUserSites?apikey=$KEY" | head -c 200
```

What the API gives beyond sitemap submission:

| endpoint | use |
|---|---|
| `SubmitUrlBatch` | push up to 500 URLs per call for reindexing |
| `GetUrlSubmissionQuota` | reports the account ceiling, **not today's limit** — see below |
| `GetQueryStats` / `GetPageStats` | impressions, clicks, position — the Search Console equivalent |
| `GetBlockedUrls` / `GetLinkCounts` | what is excluded, and inbound links |

**The quota field lies about what you can actually submit.** `GetUrlSubmissionQuota` returned
`DailyQuota: 10000` on an account whose real per-site limit was **100** — Bing raises it as a site
proves itself, and the API reports the ceiling rather than the current allowance. The refusal
comes as `ErrorCode 2` with the real number in the message, so submit in small batches and read
the reply instead of trusting the quota call.

**Spend the allowance on live URLs.** Check status before submitting: pushing a URL that answers
404 spends quota to confirm the page is gone. And check for `301` separately — a redirect is a
working URL, and treating "not 200" as "broken" overstates the damage badly (on one site: 45 of
100 top pages were 301s doing exactly their job, and only 10 were genuine 404s).

**A freshly added site returns empty rows for days, without an error.** Do not read that as
"no traffic" and do not debug a fetcher against it — wait until `GetUserSites` shows the site
verified AND `GetRankAndTrafficStats` returns something.

### Report — search analytics + opportunities across all sites
```bash
seo report
```

### Analytics — search performance last 28 days
```bash
seo analytics
```

### Inspect URL — check indexing status
```bash
seo inspect https://superduperai.co/blog/veo3
```

### Submit sitemaps — push to Google + Bing + Yandex
```bash
seo submit
```

### Ping IndexNow — instant notify Bing + Yandex + Naver + Seznam
```bash
seo ping
```

### Reindex — instant reindex via Google Indexing API + IndexNow
```bash
seo reindex https://superduperai.co/blog/new-post
```

### Status — overview of all sites and engines
```bash
seo status
```

## Configured Sites

Sites with local paths, framework, and hosting are in `config.yaml`. To find a project path:
```python
import yaml
cfg = yaml.safe_load(open("/Users/rustam/startups/shared/seo-cli/config.yaml"))
for s in cfg["sites"]:
    print(f"{s['name']:15s} {s.get('path', '?'):50s} {s.get('framework', '?'):8s} {s.get('hosting', '?')}")
```

Or just read `config.yaml` — each site has `path`, `framework`, `hosting` fields.

## Three traps that look like "no data"

Each of these cost a day of chasing the wrong thing. All three present identically — an empty
table — and none raises an error.

**1. Search Console properties are registered two ways.** Some as a URL (`https://life2film.com/`),
some as a domain (`sc-domain:miralinka.com`), some as both. A query against a property that does
not exist returns **empty rows, not an error**. Never construct the property string from the
domain — ask for the list and match:

```python
svc.sites().list().execute()   # then prefer the exact URL, fall back to sc-domain:
```

Getting this wrong hid five of eight sites, including the largest one at 368k impressions.

**2. A domain property covers every subdomain at once.** Page rows must be filtered by host or
the apex swallows its subdomains' numbers. Query rows cannot be fixed this way — Google does not
say which subdomain a query impression belongs to — so state that limit rather than implying
precision.

**3. `LIMIT` applies before your filter, not after.** Any "top N across all sites" query filtered
down to one site afterwards returns whatever slice of the global top N happens to be that site's —
frequently zero. Push the site filter into SQL. This bit twice in one file.

## Launching a new site: everything hangs on one step

`seo launch <site>` adds the site to Google and Bing, then submits sitemaps and pings IndexNow.
On a brand-new domain the adds succeed and **everything after them fails**, with three unrelated-
looking errors that all have one cause: adding a site is not verifying it.

| symptom | actual cause |
|---|---|
| Sitemap → Google `HttpError 403` | property is `siteUnverifiedUser` |
| Sitemap → Bing `400 Bad Request` | `GetUserSites` shows `IsVerified: False` |
| IndexNow `403 UserForbiddedToAccessSite` | **not verification — see below** |

Check ownership first — `sites().list()` for Google, `GetUserSites` for Bing. Both sitemap errors
clear the moment it goes green. The IndexNow one does not, and assuming it will costs an hour.

**Settle an IndexNow 403 with a differential test, not with reasoning.** The message — "User is
unauthorized to access the site. Please verify the site using the key" — names the site and the
key in one sentence, and both readings are plausible. Three calls separate them:

| call | result | what it proves |
|---|---|---|
| the key, on the new site | 403 | nothing on its own |
| **the same key, on a long-verified site** | 403 | the site is not the variable |
| **a made-up key with no file anywhere** | 202 | Bing accepts unknown keys, so it is refusing *this* key |

That last line is the one that settles it: an invented 32-char key with no `.txt` published
anywhere is queued happily, while the real one — correct length, matching filename, `text/plain`,
HTTP 200, reachable to bingbot — is refused. The key file being perfect is not evidence that the
key is good.

A rejected key is rejected for **every** site sharing it, so instant indexing is silently off
everywhere at once while sitemaps and everything else look healthy. The fix is to rotate: mint a
new key, publish `<key>.txt` at the root of each site, update `config.yaml`. Verify the new key
with the same three calls before believing it.

**IndexNow is not one service.** `api.indexnow.org` fronts Bing, so Bing's refusal looks total.
The same payload posted to `yandex.com/indexnow` (202), `search.seznam.cz/indexnow` and
`searchadvisor.naver.com/indexnow` (200) is accepted. A single "IndexNow: failed" line in a launch
report hides that three of four engines took it — though note those endpoints queue without
validating, so a 202 there is not proof the key is good either.

**Verification cannot be automated with the default setup.** A DNS-TXT token needs the Site
Verification API enabled in the Google Cloud project (it is off by default, and a service account
cannot enable it — `serviceusage.services.enable` is denied). Writing the record then needs a
Cloudflare token with **DNS\:Edit**; a token scoped to read zones returns `10000 Authentication
error` on write, which reads like a bad token rather than a missing scope. Enabling the API and
widening the token once makes every later launch fully automatic — worth doing before the next
site, not during it.

## Sitemaps: fewer URLs, better indexing

A large sitemap is not a strong sitemap. Search Console's **"Discovered — currently not indexed"**
counts pages Google found and declined to crawl; **"Crawled — currently not indexed"** counts
pages it read and declined to index. Both are verdicts about the site, not about the page.

On one blog, 282 of 746 sitemap URLs were tag archives — thin near-duplicate lists, half with a
single post. 125 pages sat in "Discovered, not indexed" and 49 in "Crawled, not indexed". The fix
was not more content: it was **dropping tags with fewer than three posts from the sitemap**,
which cut it to 510. Tags stay reachable and internally linked; they simply stop asking to be
indexed.

Check the composition before assuming the site is fine:

```bash
curl -s https://SITE/sitemap.xml | grep -oE '<loc>[^<]+' | sed 's|.*//[^/]*||' \
  | awk -F/ '{print $2}' | sort | uniq -c | sort -rn
```

If tag or category pages outnumber articles, that is the finding.

## The four fixes that move the score most

Field-tested on a fresh Astro site: **90% → 96%** in one pass. Check these before anything else.

**1. Internal links causing 308 redirects.** Most static hosts serve `/about/` and 308-redirect
`/about`. If the markup links to the unslashed form, every internal link costs a redirect hop and
the audit reports broken links. Make the path helper emit a trailing slash, and check the URLs
inside JSON-LD too — they are easy to miss:

```bash
for u in /about /studio /privacy; do
  printf "%-12s %s\n" "$u" "$(curl -s -o /dev/null -w '%{http_code}' "https://example.com$u")"
done   # anything other than 200 means the link in your markup is wrong
```

**2. `robots.txt` and `sitemap.xml` that return 200 but are not files.** SPA-style hosts answer
every unknown path with the home page, so a naive check passes while crawlers get HTML. Verify the
body, not the status code:

```bash
curl -s --compressed https://example.com/robots.txt | head -3
```

For Astro use `@astrojs/sitemap` with the `i18n` option — it emits hreflang alternates for free.

**3. `hreflang="x-default"`.** Multi-language sites almost always ship the per-language tags and
forget the fallback for everyone else.

**4. `og:url` and `og:site_name`.** Usually missing when og:title/description were added by hand.

⚠️ Cloudflare caches a missing file's fallback. After adding `robots.txt` or `llms.txt` to a site
that previously 200'd them as HTML, the old body can persist — verify with a cache-buster
(`?v=1`) before believing the deploy failed.

## Audit Categories & How to Fix

When the audit shows failures, here's what to do for each category:

### SEO Basics (title, desc, h1, canonical, viewport, hreflang)
- **Missing title/description**: Edit the page's `<head>` or metadata export. In Next.js → `export const metadata` or `generateMetadata()`. In Astro → `<head>` in layout.
- **Missing H1**: Add `<h1>` tag to the page content (exactly one per page).
- **Missing canonical**: Add `<link rel="canonical">` or set in framework metadata config.
- **Missing hreflang**: Add `<link rel="alternate" hreflang="...">` tags for each language version. Only needed for multi-language sites.

### Open Graph (og:title, og:description, og:image, twitter:card)
- **Missing og:image**: Create 1200x630 social preview image, place in `public/images/og/`. Set via `openGraph.images` in metadata (Next.js) or `<meta property="og:image">` (Astro).
- **Missing og:tags**: Set in page metadata. Most frameworks auto-generate from page metadata config.

### Structured Data (JSON-LD)
- **No JSON-LD**: Add `<script type="application/ld+json">` to the page. Minimum: `WebSite` + `Organization` schema on homepage.
- **Fix template** (Next.js):
  ```jsx
  <script type="application/ld+json" dangerouslySetInnerHTML={{__html: JSON.stringify({
    "@context": "https://schema.org",
    "@type": "WebSite",
    "name": "Site Name",
    "url": "https://example.com"
  })}} />
  ```
- **Fix template** (Astro):
  ```astro
  <script type="application/ld+json" set:html={JSON.stringify({
    "@context": "https://schema.org",
    "@type": "WebSite",
    "name": "Site Name",
    "url": "https://example.com"
  })} />
  ```
- Add `FAQPage`, `Article`, `Product`, or `SoftwareApplication` schema where relevant for AI citations.

### Files (robots.txt, sitemap.xml, favicon)
- **Missing robots.txt**: Create `public/robots.txt`. Minimum: `User-agent: *\nAllow: /\nSitemap: https://domain/sitemap.xml`
- **Missing sitemap**: Next.js → create `app/sitemap.ts`. Astro → `@astrojs/sitemap` integration.
- **Missing favicon**: Place `favicon.ico` in `public/`.

### GEO — AI/LLM Optimization
- **Missing llms.txt**: Create `public/llms.txt` — plain text describing what the site/product does, for AI agents. See llmstxt.org.
- **Missing llms-full.txt**: Optional detailed version with full docs/features.
- **AI bots blocked**: Check `robots.txt` for `Disallow` rules targeting GPTBot, ChatGPT-User, Claude-Web, etc. Remove blocks to allow AI indexing.
- **Missing markdown content**: Serve content as `.md` endpoints for LLM consumption.
- **Missing rich schema**: Add FAQ, Article, Product, SoftwareApplication schema — AI engines use structured data for citations.

## Fixing agent-readiness

Ordered by what actually moves the needle, from the sites fixed so far.

**Soft 404s** — a static host with no `404.html` in the build output serves `index.html` with
200 for everything. Astro: add `src/pages/404.astro`. The built `404.html` makes Cloudflare
Pages return a real 404 by itself.

**robots.txt naming AI crawlers.** Silence lets whoever wrote the crawler decide for you. Name
GPTBot, OAI-SearchBot, ChatGPT-User, ClaudeBot, Claude-User, Claude-SearchBot, PerplexityBot,
Perplexity-User, Google-Extended, Applebot-Extended explicitly, and state Content-Signals
inside the `User-agent: *` group — that is where the policy defines it:

```
User-agent: *
Content-Signal: search=yes, ai-input=yes, ai-train=no
Allow: /
```

**Markdown twins.** Generate `/section/slug.md` beside every page from the same source, and
negotiate on `Accept: text/markdown` with a Pages Function. Three traps, all hit for real:
`next()` is single-use and a second call returns a stale 404; fetching the twin from inside the
same zone is unreliable; and a route pattern that matches `.md` as readily as the page loops
forever, because clients resend `Accept` while following redirects. A 302 to the twin with a
dot-free slug pattern avoids all three. Working example: `solopreneur/blog/functions/`.

**MCP server, not WebMCP.** WebMCP is Chrome-only behind an origin trial, and `provideContext()`
— which every guide still recommends — was removed from the spec in March 2026. A remote MCP
server over Streamable HTTP works in Claude and ChatGPT today. Stateless JSON is spec-legal:
no SSE needed. Working example: `solopreneur/blog/functions/mcp.ts`.

**Check that robots.txt is yours before editing it.** Cloudflare's *Managed robots.txt*
(domain → AI Crawl Control → Overview) prepends its own block to whatever the site serves, with
`Disallow: /` for ClaudeBot, GPTBot, Amazonbot, CCBot, Google-Extended, meta-externalagent,
Bytespider and Applebot-Extended. The site's own file lands underneath, allowing the same bots,
and the result contradicts itself: blocked at the top, "quote me" at the bottom.

Editing the repo does nothing — it is a dashboard toggle. Symptom:

```sh
curl -s https://example.com/robots.txt | grep -c "Disallow: /"
```

Nonzero on a site whose own robots.txt has no Disallow means the toggle is on. Found on
miralinka.com, which was telling ClaudeBot not to read a blog written to be found.

**Publish nothing that is not real.** API catalogue, OAuth metadata and MCP cards for a site
with no API are box-ticking that misleads agents. rustman.org publishes an agent-skills index
because the 35 skills exist, and omits the rest.

## Auto-Fix Workflow

When user asks to fix SEO/GEO issues:

1. Run `seo audit` to get current scores across all sites
2. For each failing check, navigate to the project directory (see table above)
3. Apply fixes directly in the source code:
   - Read the relevant layout/page file first
   - Make minimal targeted edits
   - Prefer framework-native metadata APIs over raw HTML
4. After fixes, commit with message like "Improve SEO: add JSON-LD schema, og:image"
5. Re-run `seo audit` to verify improvement

Priority order for fixes:
1. **Title, description, H1** — basic SEO, biggest impact
2. **JSON-LD schema** — critical for both Google rich results and AI citations
3. **og:image** — social sharing and link previews
4. **llms.txt** — AI agent discovery
5. **hreflang** — only for multi-language sites

## Engine Coverage

| Action | Google | Bing | Yandex | Naver/Seznam |
|--------|--------|------|--------|--------------|
| `audit` | - | - | - | - |
| `report` | via SA | - | - | - |
| `analytics` | via SA | - | via OAuth | - |
| `inspect` | via SA | - | - | - |
| `submit` | via SA | via API key | via OAuth | - |
| `ping` | **not supported** | via IndexNow | via IndexNow | via IndexNow |
| `reindex` | via Indexing API | via IndexNow | via IndexNow | via IndexNow |

**Important:** Google does NOT support IndexNow. Use `submit` for Google, `ping` for the rest.

## Credentials

- **Google:** Service account at `~/.config/seo-cli/service-account.json`
- **IndexNow:** Key in config.yaml, verification files in each site's `public/` directory
- **Bing/Yandex:** Not yet configured (keys go in config.yaml)

## Our own analytics, and where it fits

`superduper-analytics` (`~/startups/active/superduper-analytics`, live at
`https://analytics.superduperai.co`) is the ingest for every site and app — one event schema
for web and iOS, so a landing visit and an app launch are comparable without a join.

It answers what `seo` cannot: `seo` measures whether a page **can** be found, analytics measures
whether anyone **came**. Use them together.

| Question | Tool |
|---|---|
| Can crawlers and agents read this site? | `seo agent-audit` |
| Is the page technically sound for search? | `seo audit` |
| Which queries bring people in? | `seo report` |
| Did anyone actually visit, and were they human? | `seo traffic` |
| Which AI agents read the site, and why? | `seo agents` |
| Is the counter even installed? | `seo products` |

Two things it knows that nothing else does:

- **Bot share.** Its counter runs only in browsers, and it classifies what it does see. On
  life2film 96% of received events were bots; the naive "people" number was 45× too high.
- **Named AI agents.** Cloudflare's verified-bot data, per agent and per intent — an `AI
  Assistant` fetch means somebody asked a question right now; an `AI Crawler` is building an
  index. The dashboard separates them.

Counter install is one line per site, documented in that repo's `docs/install.md`:

```html
<script defer src="https://analytics.superduperai.co/sda.js" data-source="<registry-id>"></script>
```

The `data-source` must exist in `registry/sources.yaml` — unregistered sources are refused with
403, and that registry is the whole access-control model.

## When to Use

- User asks "how is SEO doing" / "check scores" / "audit sites" → run `audit`
- User asks "check search traffic" / "analytics" → run `analytics` or `report`
- User asks "is this page indexed" → run `inspect <url>`
- User deployed new content → run `submit` + `ping`
- User asks "fix SEO" / "improve scores" → run `audit`, then fix issues in project source
- User asks "SEO status" → run `status`
- User asks "is the site ready for AI agents" / "agent ready" / "MCP" / "llms.txt" → run `agent-audit`
- User asks "did anyone visit" / "how many people" → run `seo traffic`
- User asks "which AI reads us" / "агенты" → run `seo agents`
- User compares products or asks "how is X doing" → run `seo products` first, then `seo traffic`
- After adding new pages/sitemap → run `ping` for instant indexing
