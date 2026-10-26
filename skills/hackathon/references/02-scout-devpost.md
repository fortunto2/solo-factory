# 02 · Scout: what wins hackathons you did not attend

- **When:** the user asks what won somewhere, wants to study a series before entering it, or wants
  the pattern across several events ("разбери победителей", "what wins hackathons").
- **Inputs:** one or more Devpost hackathon URLs, or a search ("ended in the last 30 days,
  theme X"); the user's products, for the "copy into" part.
- **Output files:** `$HACKATHONS_DIR/scout/YYYY-MM-DD-<name>/gallery.md` and `projects.json` per
  hackathon (format: stage 06), plus `rollup.md` when there is more than one hackathon.

## Mechanics (checked 2026-10-26)

- **Fetch with curl and a browser User-Agent.** Devpost answers HTTP 403 to WebFetch and to
  Python's urllib even with that User-Agent; curl gets 200. One request per second.
- **Find hackathons:** a public JSON endpoint, 9 per page.
  ```bash
  UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36'
  curl -s -A "$UA" "https://devpost.com/api/hackathons?status[]=ended&search=climate&page=1" \
    | jq '.meta.total_count, (.hackathons[] | {title, url, submission_period_dates, winners_announced,
          registrations_count, prize_amount, themes: [.themes[].name], submission_gallery_url})'
  ```
  The order is not strictly by date: filter `submission_period_dates` yourself and keep
  `winners_announced: true`. A hackathon without announced winners has nothing to scout yet.
- **Gallery:** `https://<slug>.devpost.com/project-gallery?page=N`, 24 projects per page. Once
  winners are announced the default order lists them first, and each winning card carries
  `<img alt="Winner" class="winner">`. A page with no winner card ends the walk (Cal Hacks 12.0:
  102 winners over five pages, the sixth had none).
- **Project page** `https://devpost.com/software/<slug>`:
  - `#submissions`: each hackathon the project was submitted to, and per prize
    `<span class="winner …">Winner</span> <prize name>`. A project can win several prizes, or win
    at a different hackathon than the one you are scouting: check the hackathon link next to it.
  - `#built-with .cp-tag`: the "Built With" tags, as typed by the team.
  - `[data-role="software-urls"]`: "Try it out" links: repo, demo, slides.
  - `#app-team`: Devpost profiles of the team.
  - `#app-details-left`: video embed, then the story (Inspiration, What it does, How we built it,
    Challenges, Accomplishments, What we learned, What's next).

`scripts/devpost.py` in this skill does the walk and the parsing (stdlib, calls curl):

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/hackathon/scripts/devpost.py" \
  https://<slug>.devpost.com/project-gallery > projects.raw.json        # winners only
python3 .../devpost.py https://<slug>.devpost.com/project-gallery --all  # every project (stage 06)
python3 .../devpost.py https://devpost.com/software/<slug>              # one page
```

It prints url, name, prizes (verbatim), built_with, links, team, video and the first 6000
characters of the story. It reads; the judgement is yours.

## Per winner

1. Read the story in full. Note what was built versus what is described as next.
2. If a repo link is public, open it:
   ```bash
   gh repo view owner/repo --json createdAt,pushedAt,stargazerCount,description,licenseInfo
   gh api repos/owner/repo/languages
   gh api "repos/owner/repo/commits?per_page=100" --jq '.[].commit.author.date' | sort | sed -n '1p;$p'
   ```
   The first and last commit against the hackathon dates tell you whether it was built there or
   brought in. Read the README for what it shows: a demo GIF or video, an architecture diagram,
   setup steps that work, a results table, an honest "limitations" section.
3. A dead or private repo is a finding, not a gap to fill: write "repo private" or "link dead".

## `rollup.md` (across hackathons)

Every count carries its denominator ("12 of 31 winners").

```markdown
# What wins: <scope>, <N> hackathons, <M> winning projects (read YYYY-MM-DD)
Sources: one line per hackathon: URL, date, projects, winners, how many pages read.

## Categories that win        idea clusters, with counts and two examples each
## Stacks                     Built With tags among winners vs among all projects, top 15
## Models and APIs            which model families and paid APIs appear, with counts
## Demo patterns              live link / video only / hardware on the table; video length
## Repos                      public share; built during the event vs brought in; README traits
## Prize → project type       which prize categories went to which kind of project
## Copy into <your product>   source, mechanism, data, build estimate (as in stage 06)
## Not stated / unknown       what the pages did not say
```

## Rules

- A winner is whatever the page marks as one, with the prize name verbatim. Not from a news post
  you did not open, not from the gallery order alone.
- Team members are profile links in `projects.json`, never names in `rollup.md`.
- Built With tags are self-reported: "tagged openai" is not "uses GPT-5".
