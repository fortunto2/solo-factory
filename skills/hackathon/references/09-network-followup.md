# 09 · Network follow-up

- **When:** the people log the same evening; the first messages within 48 hours, while everyone
  still remembers your face and project; a second touch a week later.
- **Inputs:** `docs/people.md` (organizers, judges, mentors, sponsors), the guest list if the event
  shows one, your notes from the floor, the organizers' wrap-up mail, and the user's contacts graph
  if there is one (read the `-my` file for the tool: e.g. a `/people` skill or a CRM).
- **Output files:** `docs/followup.local.md` (gitignored: it has names and handles), one entry per
  person in the user's contacts log, calendar reminders for the second touch.

The work ends at the awards; the network is what is left a month later. A hackathon where nobody
heard from you afterwards counts for half.

## 1. The same evening: write down everyone you talked to

One entry per person, while you remember: name as they gave it (surname "?" if unknown), org and
role, where and when you met, what was said, **what you promised and what they offered** (a deck,
an intro, a look at the project, an accelerator invite), and the channel (LinkedIn, email, Slack of
the event). A name without context is worthless in a month. Ask the user for the ones only they
know: who they had coffee with, who asked for the deck.

## 2. Pull the graph: who else is worth a message

- Judges of your track, mentors who saw your project, sponsor reps who asked questions, organizers.
- Guest list and judge list against the contacts graph: who the user already knows, who is one
  intro away, who works on the same thing as one of the user's products.
- Rank by **warmth × usefulness**, not by title: a person who asked to see the project beats a
  partner who never stopped at your table.

## 3. Who gets what (48 hours)

| Who | Message | Ask |
|---|---|---|
| Organizers | Reply to their wrap-up mail: thanks, one concrete line about what you are doing next | The intros they offered; a short participation or judging confirmation if the user needs evidence (visa, awards dossier) |
| A person who asked for something (deck, demo, evaluation) | Deliver it: link to the project page, demo video, deck attached | Their honest feedback; mention their offer (accelerator, pilot) as the reason to keep talking |
| Judges / mentors who evaluated the work | Thanks for the specific question or feedback they gave | Only after they answer: an expert opinion letter, if the user needs one; offer to send a draft |
| Teams with overlap | What you liked in their build, one line | Coffee, a repo star, a joint next step |
| Sponsors | What you built on their stack, with the link | Credits, a feature in their channel |

Rules for the text:
- 2-4 sentences, the user's voice, no formal asks in the first note to someone who did not offer
  anything. Run `/humanize`.
- LinkedIn connection notes have a 300-character limit: name the event and the project, nothing else.
  Links and attachments go in the message after they accept.
- Write in the language you spoke with the person.
- Drafts only: the user sends every message themself. Never send, connect or follow in their name.
- Evidence asks (letters for a visa petition, awards) are honest: "confirm I took part / judged",
  "if you find the work original, would you say so". Never ask anyone to state what did not happen.

## 4. Track it and come back

- `docs/followup.local.md`: who · where met · why · channel · draft · sent date · reply · next touch.
- Calendar: a second touch a week later for everyone who did not answer; deadlines the organizers
  set (feedback forms, prize paperwork, certificates) as all-day events.
- When someone answers, update their entry (what was agreed, by when). The standup reads these dates.
