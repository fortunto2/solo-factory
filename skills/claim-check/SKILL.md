---
name: solo-claim-check
description: Fact-check a YouTube video, article or pasted text that makes health, science or "they are hiding it" claims, and write a short, kind, plain-language breakdown for a specific reader (what is true, what does not hold and why, what not to do, what to do instead, the trick used). Verdicts rest only on pages that were fetched and quoted. Use when user says "проверь ролик", "правда ли что", "разбери видео", "мама прислала", "фактчек", "fact-check this video", "is this true", or hands a video link with claims to examine. Do NOT use for general market or competitor research (use /research) or for verifying claims inside our own drafts (use /verify-claims).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "🔎"
allowed-tools: Bash, Read, Write, Edit, WebFetch
argument-hint: "<youtube url | article url | text> [--audience PROFILE]"
---

# claim-check: a gentle fact-check someone can read once and keep

The goal is help, not exposure. The reader cares about their health or the world; the video is what
is wrong, not them. The output is one short message (`short.txt`) the owner forwards himself, a card
for the owner (`card.md`), and the full working file (`work.json`).

`scripts/claim_check.py` does the mechanical part (fetch, evidence cache, render, lint, queue). The
reasoning is yours, in the steps below. Config (audience profiles, output dir) is a private YAML:
`--config`, `$CLAIM_CHECK_CONFIG` or `./claim-check.yaml`; shape in `references/config.example.yaml`.

```bash
S=scripts/claim_check.py            # uv run, deps inline; needs yt-dlp, ffmpeg for the whisper fallback
uv run $S fetch <url>               # -> <out>/<id>/video.json + transcript.txt  (exit 3 on failure)
uv run $S source <id> <url>         # evidence page -> shared cache; PubMed URLs return the abstract text
uv run $S render <id>               # work.json -> short.txt + card.md
uv run $S lint <id>                 # exit 2 on any rule break
uv run $S queue add <url> --from <label> | run [--max N] | list | show <id>
```

## 1. Fetch

`fetch` takes captions first (`yt-dlp`, ru/en), then, if there are none and `whisper_script` is set,
transcribes the audio locally (`solo:transcribe`, mlx-whisper) and deletes the audio. Nothing is
uploaded anywhere. For a non-YouTube link it extracts the article text; `-` reads stdin.
Auto-captions misspell names and numbers: quote the claim as spoken, but never build a verdict on a
garbled number.

## 2. Claims

Read `transcript.txt` whole. Write 3 to 7 claims the video makes or strongly implies, each with the
timestamp, `kind` and `harm`:

| kind | meaning |
|---|---|
| `fact` | a statement about the world ("eugenol is an antiseptic") |
| `promise` | implied result ("kills ALL microbes", "stronger with age") |
| `call_to_action` | do or stop something (drink this, drop the medicine, distrust doctors) |
| `sale` | what is being sold or promoted (a product, a course, a subscription) |

Set `harm: true` when following the claim could hurt: replacing prescribed treatment, taking an
essential oil by mouth, delaying a doctor. Include what the **title and thumbnail** promise, not
only the narration: they are often stronger than the body of the video.

## 3. Check

Per claim: find the best evidence, fetch it with `source`, copy the supporting sentence **verbatim**
into `sources[].quote`. Lint refuses a quote that is not in the fetched text.

Verdict scale (fixed): `верно`, `частично верно`, `не подтверждено`, `неверно`, `опасно`,
`не удалось проверить`.

- Best sources first: Cochrane and systematic reviews, PubMed abstracts, WHO, CDC, national health
  agencies. Wikipedia is a pointer to primary sources, never the proof.
- PubMed: `esearch` through `https://eutils.ncbi.nlm.nih.gov/entrez/eutils/` finds IDs; then
  `source <id> https://pubmed.ncbi.nlm.nih.gov/<pmid>/`.
- **A petri dish, a drop under a microscope or a test tube is not a body.** Say so whenever the video
  moves from "killed it in a dish" to "so it works in you". Killing a worm in a drop proves the
  liquid is harsh to that worm; whether a dose reaches the right place, at a safe level, is a
  different and mostly untested question.
- **Absence of evidence is reported as absence**, `не подтверждено`, never as "false".
- `опасно` is for a call to action that can hurt a person, not for a wrong fact.
- Never invent a study, an author, a number. No source fetched within the budget means
  `не удалось проверить`, and say it in the reason.
- Search budget: at most 10 web queries per video, paced, never bursts. The local SearXNG
  (`localhost:8013`) is fine for finding pages; PubMed eutils for papers.
- Credit what is honest: a disclaimer in the video ("I am not a doctor", "do not try this on
  yourself") goes in the card and softens the message, because the fault then lies in the title and
  in what viewers infer, not in the author.

## 4. Write the message for the audience profile

Fields of `work.json -> message` (lint demands the first, second, fourth, fifth):

1. `true_part`: **start with what is true or right**: the kernel of truth, or the reader's good
   instinct. Never begin with "это ложь" or "нет".
2. `doesnt_hold`: 2-4 short sentences: what does not hold and why, with an everyday comparison
   (soap kills germs on a plate; that does not make it safe to eat). No term without a plain word.
3. `dont`: one clear line on what NOT to do, only if any claim has `harm` (lint requires it then).
   Calm, no fright.
4. `help`: what does help, or the concrete question to ask the doctor. Medical matters always end
   in "спросите врача" plus the question. Never a diagnosis, never a dose.
5. `technique`: the trick in one line, as a skill to reuse: shock title, "doctors hide it",
   something being sold, an experiment that proves nothing about the body, a vivid war metaphor.
6. `links`: 1-2, named (`{"name": "Cochrane", "url": ...}`), each fetched.

Hard limits (lint-enforced): `short.txt` ≤ 900 characters including links; no sarcasm; none of
«конспирология», «фейк», «бред», «опять», «глупости»; no dosing amounts; no "ты опять". Use the
audience profile's address form (`ты`/`вы`) and the name the owner uses for them. Plain words, short
sentences, a larger font is assumed, so no tables or lists in `short.txt`.

Why this shape: lead with the fact, name the kernel of truth, explain the technique, give an
alternative (Lewandowsky and Cook, Debunking Handbook 2020; inoculation: Cook et al. 2017, Roozenbeek
et al. 2022). Sources and what was and was not verified: `references/research.md`.

## 5. Output files

`work.json` schema (the agent writes it; keep the quotes):

```json
{"video": {"id": "…", "title": "…"}, "audience": "elder_ru", "sold": "nothing | what",
 "claims": [{"id": "c1", "ts": "05:36", "text": "…", "kind": "promise", "harm": false,
             "verdict": "не подтверждено", "reason": "one sentence",
             "sources": [{"url": "…", "title": "…", "quote": "verbatim sentence from the page"}]}],
 "message": {"true_part": "…", "doesnt_hold": "…", "dont": "", "help": "…", "technique": "…",
             "links": [{"name": "…", "url": "…"}]}}
```

Then `render <id>`, `lint <id>`; fix until lint says `ok`. Show a member only `short.txt`.

## Batch and bots

`queue add` is idempotent per video id (a checked video returns its stored result). `queue run`
fetches, calls the agent (`agent_cmd` in the config, default headless `claude -p` under the local
login) with the prompt that points at this file, renders and lints. Statuses: `pending`, `done`,
`needs-review` (lint failed: a person looks), `failed`. Exit 4 when any item is not done.

## Gotchas

- `I` (capital i) and `l` look alike in a typed video id; try both, one will resolve.
- yt-dlp captions can hit HTTP 429: the script asks for ru and en only; wait and retry.
- Auto-captions repeat lines (rolling captions); the parser drops consecutive duplicates.
- PubMed HTML pages block plain clients; `source` uses the efetch abstract endpoint for them.
- Some sites (the Debunking Handbook's own host) fail TLS from here; use the short link `sks.to/db2020`.

## Don't

- Send anything anywhere: no Telegram, no e-mail. The owner forwards the text.
- Put names, family details or private paths into this skill (it is public); they live in the
  private config.
- Call the author a liar when the fault is the title; judge the claim and the technique, not the person.
- Treat a green lint as "the message is right". Lint checks the rules and that quotes exist; a
  person still reads the verdicts.
