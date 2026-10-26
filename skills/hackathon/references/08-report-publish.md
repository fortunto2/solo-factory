# 08 · Report and publish

- **When:** the same night or the next morning, while the transcript and the repos are fresh.
- **Inputs:** everything in `docs/`: `event.md`, `live/finalists.md` and the panel versions,
  `repos.md`, `gallery.md`; the scout `rollup.md` for a scout report.
- **Output files:** `docs/report.md` (draft), then the published page in the user's wiki or blog
  (read the user's CLAUDE.md for where and how), the hub page, a row in `$HACKATHONS_DIR/README.md`.

## One home for the event: assemble first, then write

Every event, built at, judged or watched, gets one post on the user's own site, and that post is
the canonical record. Everything else points to it: social posts, the hub, a CV line, a follow-up
email. So before writing, put every asset where the post can show it:

| Asset | Where it goes | Check before it goes in |
|---|---|---|
| Photos (venue, stage, team, slides) | the post's own media folder, resized (~1600 px) | EXIF orientation applied before the metadata is stripped (stripping it drops the rotation too, and a phone photo comes out upside down), then location metadata gone; a front-camera selfie mirrored back so signs read; open the final file and look at it; strangers' faces only as a crowd; the hero image at the top |
| Demo or pitch video | uploaded to the user's video channel, embedded in the post | it is the video the judges saw, or it says what changed after |
| Deck | a PDF in the site's files folder, linked | no private notes, keys or contact details on any slide |
| Slide frames from the stage | the media folder, only where a slide makes the point | other teams' slides only small and credited |
| Links | in the "ours" section, near the top | live demo, repo, Devpost or event page, store listing; a link that is not live yet says so, with a note to add it |

Then write the post. Social posts (a channel, LinkedIn, X) are derived from the published post
afterwards, in a separate step; they link back to it instead of carrying their own version of the
story.

If the site supports an event-date field next to the written date, set it to the event's first day,
so a write-up done days later still sorts with the event.

## Post format

Hook first, inventory second, method last. A reader who stops after the first screen should leave
with the sharpest findings and a verdict on the projects, not with a list of team names or a note
on how you recorded the room. Nobody reads past an opening paragraph about cameras and
transcription.

```markdown
# <Claim-shaped title: what the room showed, not "My notes from X">

<Lede, 2-4 sentences: the single sharpest finding, with a number or a project as evidence. Then the
event in one clause: name, date, place, size, your role (builder / observer / judge).>

## The short version               3-5 bullets, each an insight with a number or a named team
## Scorecard                       one line per project: Strong (what to copy) · Unproven or Weak
                                   (simulated data, nothing live, stage number > page number,
                                   claim not visible in the code). Your own project gets the same
                                   treatment, at least as harsh
## <Pattern 1 as a sentence>       cross-team patterns, each with 2-4 teams as evidence
## Small tricks worth copying      concrete: the threshold, the formula, the file path to read
## Hard numbers                    what fits, how fast, how much, each with its source
## The teams                       compact table: team · what it does · stack · repo (confirmed only)
## Claims to read as claims        stage numbers, "as claimed", grouped
## What I'd steal                  3-5 lines, tied to your own work
## How this was put together       last: what was recorded and read, which numbers are the teams'
                                   own, awards status; links to the hub and sibling events
```

Rules for the scorecard:

- Critique the work, never the people. "The 200 sites are synthetic" is a verdict; "they faked
  it" is an accusation, and commit-timing forensics on named teams stay in private notes.
- Every verdict cites something checkable: the project page, the README, a file, the stage.
  Re-read the source before calling something weak; a finding in a team's favour misread as a
  gap is the easy mistake.
- A judge never publishes scores, pairwise votes or what was said in deliberation. "These are mine,
  not the panel's scores" when you judged.

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
