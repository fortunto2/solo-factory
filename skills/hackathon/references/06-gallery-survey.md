# 06 · Gallery survey: every project, read in full

- **When:** once the gallery fills (usually after the submission deadline), again after the
  awards. For a scout run (stage 02), on the winners only.
- **Inputs:** the gallery URL (Devpost or the event platform's project list), `docs/live/` and
  `docs/repos.md` if you were there, the user's products.
- **Output files:** `docs/gallery.md` and `docs/projects.json` (scout: in the scout folder).

## Collect

- **Devpost:** `scripts/devpost.py <gallery-url> --all` (mechanics in stage 02). Read every
  project page in full, not the gallery cards: the cards carry a tagline, the page carries the
  data sources, the models and the admissions.
- **Other platforms:** the project list page plus each project's page; if the list only renders in
  a browser, a Playwright snapshot. Save the raw list as JSON first (`projects.json`), then write.
- **The gallery changes.** Projects are added late and withdrawn. Re-read after the awards and
  note the difference at the top ("refresh at 19:40: +6, 1 withdrawn").

`projects.json`, one object per project:

```json
{"name": "", "url": "", "track": "stated | ~inferred | not stated", "idea": "",
 "data": [], "models": [], "built_with": [], "repo": "", "live": "", "video": "",
 "finalist": "yes | no | not stated", "winner": "<prize verbatim> | not stated",
 "on_stage_differs": "", "source_read": "2026-10-24T19:32-07:00"}
```

## `docs/gallery.md`

Sections in this order. Skip a section only if it would be empty, and say so.

**Header.** Where the data came from (URL, date, how many projects, how they were fetched), what
is missing (pages that would not load, winners not yet announced), and the conventions: `~T2`
means a track inferred from the organizer's list, "(match inferred)" means a stage name was
matched to a page by you.

**1. All projects.** One row each.

| Project | Track | Idea (one line) | Data / models | Live / repo | Finalist | Winner |
|---|---|---|---|---|---|---|

"Synthetic" or "simulated" goes in the data column when the page says so; it is the most
important word in a hackathon table.

**2. Copy into <your product>.** Three to six items, each one:
source project → the concrete mechanism (what it computes, from what) → the data and where it
comes from → build estimate in days. Their numbers stay theirs ("their numbers, from three
weekdays").

**3. Worth a standalone app.** Up to three, each with: moat (often "none, and that is fine"),
what is actually built, what is claimed beyond that, what it costs to operate.

**4. Considered and left out.** Grouped by reason: needs a business or a paying institution,
needs hardware, needs a partner or field access, vapor or off-theme. One line each. Saying why
something was left out is what makes the picks credible.

**5. On stage vs on the page** (if you were there). Per finalist: what was said, what the judges
asked, and **Differs:** where the stage claim and the page disagree or the page is silent. Stage
numbers tend to grow between the page and the pitch.

**6. Pattern counts.** Tool and stack tags with counts (`ClickHouse 65, Semgrep 54, ...`), idea
clusters with counts, how many projects use synthetic data, how many have a public repo. Always
with the denominator.

## When you are building too: where you stand

Add `docs/assessment.md` (or a closing section): the field in one paragraph (the clusters and
their sizes), the strongest ideas ranked with a reason each, where the user's project is unique,
where its sponsor story is weakest (and what to say if a judge asks), ideas worth stealing for the
user's roadmap.

## Rules

- Winner: "not stated" until the page or the announcement says otherwise.
- A claim is attributed to the page that makes it. If you checked it yourself, say how.
- Authors shown on a public project page may appear in these working files. What gets published
  follows the name rule in stage 08.
