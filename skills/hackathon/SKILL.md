---
name: solo-hackathon
description: Work a hackathon research-first and write it up. Event rules and judging, who the judges and mentors are, what the other teams built and where their code is (GitHub, Devpost gallery), live notes from the stage, the report afterwards, and the follow-ups to the people you met (who to write, drafts, when); scout mode analyses the winners of hackathons you never attended. Use when user says "хакатон", "ресерч хакатона", "кто судьи на хакатоне", "найди репо команд", "разбери галерею devpost", "отчёт по хакатону", "разбери победителей хакатона", "кому написать после хакатона", "фоллоуап после хакатона", "analyze devpost winners", "what wins hackathons", "hackathon research". Do NOT use for market research on a product idea (use /research), listening to a room with no hackathon in it (use /supervox), or a social post about the event (use /content-gen).
license: MIT
metadata:
  author: fortunto2
  version: "1.1.0"
  openclaw:
    emoji: "🏁"
argument-hint: "[event URL | Devpost URL | scout <theme or URL>]"
---

# hackathon: research the room, then write it up

A hackathon is a day of cheap validation and a room full of people building in your space. This
skill makes sure you walk in knowing the rules, the judges and the field, keep honest notes while
it happens, and leave with a report, a list of ideas worth copying and the follow-ups to the people
you met: the network is what is left a month later. Scout mode does the same
for events you did not attend: what won, with which stack, and what the winning repos show.

## Setup

- **Where files go.** `HACKATHONS_DIR` (default `./hackathons`). One folder per event, one per
  scout run. If the user's knowledge base has a personal variant `hackathon-my.md` (the `-my`
  convention, e.g. in `1-methodology/`), read it first: it can set the directory, a guest-list
  tool and the products to target.
- **"Your products".** Every "copy into" and "who to meet" line names one of the user's products.
  Read them from the user's CLAUDE.md, the projects registry or the `-my` file; never guess.

```
$HACKATHONS_DIR/
  README.md                          one row per event: date, name, folder, project, result
  YYYY-MM-DD-<short-name>/
    docs/event.md                    rules, criteria, stack, schedule, prizes; source URL + fetch time
    docs/people.md                   organizers, judges, mentors with confidence; top 5 to meet
    docs/repos.md                    team → repo, confidence, stack bits worth stealing
    docs/gallery.md, projects.json   gallery survey
    docs/live/                       panel summaries and slide frames (or a link to the supervox session)
    docs/report.md                   draft of the write-up
    docs/followup.local.md           who to write after the event, drafts, sent/reply dates (gitignored)
    *.local.md                       anything with other people's handles or contacts (gitignored)
  scout/YYYY-MM-DD-<name>/           gallery.md, projects.json, rollup.md
```

## Stages

Load only the reference for the stage you are in. Each one opens with When / Inputs / Output.

| # | Stage | One line | Read |
|---|---|---|---|
| 01 | Before: research | event page → rules, criteria, stack, schedule, prizes; judges/mentors/organizers with confidence; past winners of the series | `references/01-before-research.md` |
| 02 | Scout (not attending) | Devpost search → winners only (`scripts/devpost.py`) → every winner page + public repo → gallery + cross-hackathon roll-up | `references/02-scout-devpost.md` |
| 03 | Build | required-stack check, demo first, submission checklist; then `/plan`, `/build` | `references/03-build.md` |
| 04 | Live capture | supervox on the room, one block per team, camera on the slides | `references/04-live-capture.md` |
| 05 | GitHub hunt | repos created since the day before, keyed on stack and domain words; confirm from the README | `references/05-github-hunt.md` |
| 06 | Gallery survey | every project page read → all-projects table, copy-into, left-out, pattern counts | `references/06-gallery-survey.md` |
| 07 | Pitch | deck, demo video, Q&A cheat sheet via `/supervox` pitch coach | `references/07-pitch.md` |
| 08 | Report and publish | insights first, team table, hub page with backlinks, privacy pass | `references/08-report-publish.md` |
| 09 | Network follow-up | people log the same evening; contacts graph → who else to write; drafts within 48 h; second touch a week later | `references/09-network-followup.md` |

Research (01, 02, 05, 06) is where this skill does most of its work. Typical order on the day:
01 the evening before, 05 in the first hours and again after the demos, 04 during the pitches,
06 once the gallery fills, 08 the same night, 09 the same night and the next two days.

## The rule: nothing from thin air

- Every claim comes from a source you opened, and its URL goes next to it. Unknown is written
  "not stated", never filled in.
- A winner is a winner only when the page or the announcement says so. Before that the column
  says "not stated".
- Numbers said on stage are "as claimed". Nothing is "measured" unless you measured it.
- A person's identity is labelled confirmed / probable / unconfirmed. Two namesakes are never
  merged, and a role is never invented to fill a table.
- Private conversations never enter notes. First names heard by speech recognition stay out of
  anything published unless the person put them in a public repo or project page.

## Orchestration

The main thread stays with the user: it listens (the supervox loop must run in the main session,
see `/supervox`) and relays. Research, repo hunting, gallery reading and writing go to background
agents. A brief that works fits in six lines:

1. Goal and the one output file (absolute path) with its format, copied from the stage reference.
2. Sources to start from (event URL, gallery URL, keyword list) and what was already ruled out.
3. Confidence labels to use and the rule above, verbatim.
4. The user's products and goals, when the output has a "copy into" or "who to meet" part.
5. What not to do: no logins, no bearer tokens, no guessing names.
6. When to stop: a page count, a repo count or a time budget.

Agents report a summary; the main thread posts the 3-6 lines that matter and the file path.

## Gotchas

- Devpost answers 403 to WebFetch and to Python's urllib; curl with a browser User-Agent works.
  `scripts/devpost.py` wraps it: gallery walk, winners, Built With, links, story.
- A participant dashboard whose API wants a bearer token is a stop sign: note "not visible".
- Galleries fill late and change: re-read after the deadline and after the awards, and log the
  difference (projects added, withdrawn).
- Speech recognition mangles team names, and finalists are often read twice: keep both hearings.

## Don't

- Don't write a winner, a prize or a role you did not read.
- Don't run the live loop in a subagent: its mailbox lags minutes behind the room.
- Don't publish other people's handles; they go to `*.local.md`.
