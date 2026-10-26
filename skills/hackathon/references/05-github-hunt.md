# 05 · GitHub hunt: where the teams' code is

- **When:** in the first hours (repos appear as teams push), again after the demos with the names
  heard on stage, and once more the next day.
- **Inputs:** `docs/event.md` (required stack, hardware, event and platform name, dates), the team
  names and domain words from stage 04 or the gallery.
- **Output file:** `docs/repos.md`.

Give it to a background agent: it is many small searches and many READMEs.

## Search

Public repos only; `gh` needs to be logged in. Start the window one day before the event, since
teams create the repo the night before.

```bash
SINCE=2026-10-24   # event start minus one day
for kw in "<required framework>" "<hardware model>" "<event name>" "<platform>" "<sponsor tool>"; do
  gh search repos "$kw" --created ">=$SINCE" --limit 100 \
    --json fullName,description,createdAt,pushedAt,url
  gh search repos "$kw" --match readme --created ">=$SINCE" --limit 100 \
    --json fullName,description,createdAt,url
done | jq -s 'add | unique_by(.fullName)'
```

- **Keywords that find the most:** the required stack by exact name, the hardware, the event and
  platform name, the venue. Then, per team heard on stage, two or three domain words from their
  pitch ("invoice audit", "sonar", "substation").
- Repo descriptions written that day often name the hardware and the event outright.
- Models and datasets published the same day: search Hugging Face too
  (`https://huggingface.co/api/models?search=<kw>&sort=createdAt&direction=-1`). Gated cards
  show only tags and file names; say so.

## Confirm

A repo belongs to the event when at least two of these hold:

- the README or description names the event, the platform, the hardware or the date;
- it was created inside the window and most commits fall in the hacking hours
  (`gh api "repos/o/r/commits?per_page=100" --jq '.[].commit.author.date'`);
- what it does matches what the team showed on stage or on their project page;
- a contributor matches a team member listed on the project page.

Labels: **confirmed** (README or page ties it to the event and the content matches),
**probable** (domain and timing match, the team name is a guess from speech recognition),
**weak guess**, **not found**. Never upgrade a label because the table looks emptier without it.

## `docs/repos.md`

```markdown
# <Event>: team repos
Method: gh search repos <keywords> --created ">=<date>" (+ --match readme), README and
contributors checked per repo. Searched YYYY-MM-DD HH:MM.

## Teams heard on stage
| # | Team (as heard) | Repo | Confidence | Worth stealing |
|---|---|---|---|---|
| 1 | <name> | github.com/o/r | confirmed | model + serving, the one trick, the file it is in |

## Other repos from the same event (not tied to a heard name)
owner/repo (one-line what), ...

## Cross-team patterns
3-5 bullets: model of choice, the shared design move, the common pain and its fixes

## Still not found
<name heard>: what was searched; best next step
```

"Worth stealing" is concrete: the model and how it was served, the design move (approval held by
a policy, a check that runs before the model), the file or doc where it lives. Not "nice
architecture".

## When the repo is private

Measured once at a ~150-person event: about 35 public repos created that day, 10 of 12 names
heard on stage mapped (8 confirmed, 2 probable). The rest were private or never mentioned the
event. For those: ask the team after the demos, scan the QR code on their last slide (stage 04
frames), or wait for the gallery (stage 06).
