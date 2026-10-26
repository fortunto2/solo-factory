# 08 · Report and publish

- **When:** the same night or the next morning, while the transcript and the repos are fresh.
- **Inputs:** everything in `docs/`: `event.md`, `live/finalists.md` and the panel versions,
  `repos.md`, `gallery.md`; the scout `rollup.md` for a scout report.
- **Output files:** `docs/report.md` (draft), then the published page in the user's wiki or blog
  (read the user's CLAUDE.md for where and how), the hub page, a row in `$HACKATHONS_DIR/README.md`.

## Post format

Insights first, inventory second. A reader who stops after the first screen should leave with the
patterns, not with a list of team names.

```markdown
# <Claim-shaped title: what the room showed, not "My notes from X">

<One paragraph: event, date, place, size, the brief, the judging criteria, your role
(builder / observer / judge). Awards: announced or "not announced when this was written".>

<One paragraph on sources: numbers from the stage are the teams' claims; where a public repo backs
a detail it says so; nothing was re-measured unless stated.>

## <Pattern 1 as a sentence>       cross-team patterns, each with 2-4 teams as evidence
## <Pattern 2 as a sentence>
## Small tricks worth copying      concrete, one line each, with the repo or page they came from
## Hard numbers                    what fits, how fast, how much, each with its source
## Which arguments held up         ranked: the strongest arguments for the brief's premise
## The teams                       compact table: team · what it does · stack · repo (confirmed only)
## Claims to read as claims        stage numbers, "as claimed", grouped
## What I'd steal                  3-5 lines, tied to your own work
## How these notes were taken      tools and method in two sentences; links to sibling events
```

## Privacy and accuracy pass (before publishing)

- Stage numbers say "as claimed" or sit in the claims section.
- No awards unless announced or on the event page.
- Repos in the team table are **confirmed** ones; "probable" stays in your working files.
- First names heard by speech recognition, of people who are not public speakers, are not
  published unless the person put them in a public repo or project page. Team and product names
  are fine.
- Nothing from private conversations: mentor talks become lessons without names.
- No handles, emails or contact details; those live in `*.local.md`.
- Run `/humanize` on the text.

## Hub page and links

Keep one hub page of every hackathon (zettelkasten style: the hub links out, every event page
links back).

- Hub: a table row per event (date, event, role, what you built, result, links) and a "patterns
  across hackathons" section where each pattern cites the event pages it came from. Update the
  patterns when a new event confirms or breaks one.
- Each event page ends with a link to the hub and to sibling events of the same week or series.
- `$HACKATHONS_DIR/README.md` gets the row too: date, name, folder, project, result.
- If the knowledge base generates its index from frontmatter, set the page's summary fields and
  regenerate instead of hand-editing the index.
