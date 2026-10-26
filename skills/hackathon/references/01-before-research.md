# 01 · Before the event: research

- **When:** the event is announced, the evening before, or the first hour on site.
- **Inputs:** event URL(s) (the event platform page, Luma, Devpost), the user's products and goals,
  `hackathon-my.md` if the user has one.
- **Output files:** `docs/event.md`, `docs/people.md`, contacts in `docs/people.local.md`
  (gitignored). Raw page copies in `docs/raw/<host>-<YYYYMMDD-HHMM>.md`.

## 1. Fetch the event page

Pages change during the event (rules get edited, judges added), so save what you read with the time.

1. **Ask for markdown first.** Some event platforms serve markdown by content negotiation, which
   is authored text instead of an extraction guess:
   ```bash
   curl -sL -H 'Accept: text/markdown' -D - "$URL" -o docs/raw/event.md | grep -i '^content-type'
   ```
   `text/markdown` in the header means it worked. `text/html` means it did not; go to step 2.
2. **Extract.** MCP `web_extract(url, size="f")` if available (navigation and footers removed,
   tables kept), otherwise WebFetch. Luma pages extract well this way.
3. **JS-only pages.** A browser (Playwright MCP) snapshot.
4. **Logged-in participant dashboard.** Read what it shows to the user (announcements, schedule).
   If the gallery or a list sits behind an API that wants a bearer token, stop there and write
   "not visible to participants". Do not lift tokens from the browser or call private endpoints.

## 2. `docs/event.md`

Fill every heading; a heading you could not fill says so under **Not stated**.

```markdown
# <Event name>: event facts
Sources: <url> (fetched 2026-10-24 18:05 PT), <url2> (...)

## Brief            the theme in the organizer's words, one quote
## Rules            eligibility, team size, what may be pre-built, disclosure, licence/IP
## Required stack   sponsor tools, frameworks, hardware, "must run locally": exact names
## Judging          criteria with weights, rounds (table visits, finals), demo length, who judges what
## Schedule         check-in, hacking starts, submission deadline WITH time zone, demos, awards
## Prizes           per track and sponsor prize, and what each one requires
## Submission       platform, required fields (video length, public repo, deck, track choice)
## Not stated       what you looked for and did not find
```

The exact names under **Required stack** become search keywords in stage 05, so copy them as
written (product names, model families, hardware model).

## 3. Past winners of the same series

Organizers and judges reuse their taste. If the series ran before (same organizer, same title with
a different city or number):

- Devpost: search the API by the series name (stage 02 has the call) and keep the entries with
  `winners_announced: true`.
- Run stage 02 in light mode on one or two of them: winners only, the table and the pattern counts,
  no roll-up. Put the result in `docs/past-winners.md` with links.
- What to take from it: which prize categories exist, what kind of demo won (live hardware, a
  number, a story), whether winners had public repos.

## 4. People: organizers, judges, mentors

Hand this to a background agent with the brief from SKILL.md. Sources in order: the event page,
Luma hosts, sponsor and organizer posts announcing the event, the people's own posts about it,
then profiles (LinkedIn, GitHub, personal site, company page).

`docs/people.md`:

```markdown
| Name | At this event (source) | Best match: role, company | Links | Confidence |
|---|---|---|---|---|
| A. Example | judge (event page) | Senior PM, ExampleCorp (sponsor) | linkedin.com/in/…; company page | confirmed |
```

Confidence, and nothing else:

- **confirmed**: a source ties this person to this event, or the identity is unique and the role
  fits (a sponsor employee listed by the sponsor).
- **probable**: the name matches and the context is strong (works at a sponsor, same city,
  judges hackathons), but nothing ties them to this event.
- **unconfirmed**: a common name, or no reliable profile. Say "not identifiable" rather than
  picking the first namesake.

Write the caveat at the top when the page lists no judges and the names came from the user or the
stage. Never merge two namesakes into one person.

### Top 5 to meet

Below the table, five people with a reason tied to the user's products or goals and an opener
that refers to their work, one line each:

```markdown
1. **A. Example** (confirmed): runs the sponsor's local-inference program; our product ships the
   same model on-device. Opener: "Your team's GB10 benchmark: did the memory limit or the
   tokens per second decide what you shipped?"
```

No flattery, no pitch in the opener. If the user has no product that fits a person, leave them out.

## 5. Guest lists

If `hackathon-my.md` names a guest-list tool, run it. Handles and contacts go only into
`*.local.md` (gitignored). Lists the hosts hid stay hidden.

## 6. Where the user stands (when building)

Five lines at the end of `docs/event.md`: which of the user's products fits which track and
criterion, what is pre-built and must be disclosed, which required tool is missing, and the one
demo that would answer the judging criteria. This feeds stage 03.
