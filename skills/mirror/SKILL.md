---
name: solo-mirror
description: Weekly reflection that compares what a person says they focus on with what the data shows they did, names at most three repeating patterns with counts and dates, sets one experiment, and shrinks the load (cut list, three items for this week). Read-only; returns a report and ledger entries, the caller applies them. Use when user says "weekly mirror", "reflect on my week", "what do I keep doing without noticing", "am I working on what I said", "lower my load", "зеркало", "разбор недели". Do NOT use for a pipeline retrospective (use /retro), for checking memory notes (use the dream workflow), or for anything personal that belongs in a private journal.
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "🪞"
allowed-tools: Read, Bash, Glob, Grep
argument-hint: "[--config path/to/mirror.yaml] [--days 14]"
---

# mirror: a weekly reflection with numbers

Reads files, git and past prompts, returns a short report. It lowers mental load:
every open item either has a reason, is on a cut list, or is explicitly "not this week".
It never writes, sends or edits anything; the caller saves the report and runs
`ledger-append`.

## Inputs (all paths in one config file)

| Input | Config key | What it is |
|---|---|---|
| Stated goals | `goals_files` | markdown the person wrote: the plan, the focus rule (for example one product plus one keystone goal). The model reads these; the script only lists them |
| Task registry | `registry_dir` | `open/*.json` topics with `parents`, `updated`, `items` |
| Todo lists | `todo_lists` | yaml lists with `status`, `due`, optional `purpose: "<goal slug or ?>: <reason>"`, dated `due_reason*` keys |
| Projects | `projects_registry` | yaml `projects: [{name, path}]`; git logs are read per project |
| Past prompts | `sessions.dir` | Claude Code transcripts; user turns only, never assistant text; `exclude_dir_substrings` are never opened; `automation_regex` drops headless jobs |
| Drafts | `drafts_cmd` | optional command printing JSON `[{ref, title, drafted_at, reschedule_dates}]` |
| Focus | `focus`, `project_goal`, `goal_priority` | which projects/goals are the declared focus, which goal each project serves |
| Ledger | `ledger` | jsonl of patterns and experiments |

Template: `references/mirror.example.yaml`.

## Workflow

1. Collect. This is the only step that touches data, and it is deterministic:
   ```bash
   uv run ${CLAUDE_PLUGIN_ROOT}/skills/mirror/scripts/mirror_collect.py collect --config <mirror.yaml> --days 14 --json
   ```
   (`--end YYYY-MM-DD` to reproduce a past week.) Read the stated goals files once, for the
   words of the focus rule; do not search anywhere else.
2. Write the report from the numbers, nothing else. Three questions, same every week:
   - **Said vs did.** `said_vs_did`: share of sessions and commits per project and per goal against the stated focus. One sentence with the two numbers.
   - **What repeats.** Only entries in `patterns` (the script already applied the rule: at least 3 dated occurrences and a number). At most 3, the largest `count` or longest `weeks_in_a_row` first. Each: what, the count, the dates, where the evidence is (`refs`). If `weeks_in_a_row` is 2 or more, say "N weeks in a row". If `patterns` is empty, write "повторов с тремя датами нет" and stop; do not invent one from `below_threshold`.
   - **One experiment.** Verdict on last week's from `experiment_last_week.result` (met / missed / unknown, with the actual number), then one new experiment for next week: one behaviour, checkable from the same data, as `{metric, op, value}` using a key in `metrics` (for example `share_focus_sessions >= 0.4`).
3. Load reduction, part of the report, not advice:
   - **Cut list** from `cut_list`: open items with no goal behind them or silent for the configured days. One line each: ref, why, proposal (drop, park until a date, or delegate to an agent). Keep the script's proposal unless the title shows it is wrong.
   - **This week only**: at most 3 items from `this_week_candidates`, each with its reason. Everything else is named in one line as "не на этой неделе".
4. End with ONE question the person may take to a private journal or therapy context. A question about the pattern, not a diagnosis. This skill never reads such a place and never asks for it.
5. Check the form: `mirror_collect.py lint <report.md>` (length, em dashes, at most 3 numbered observations).
6. Return: the report, and a JSON list of ledger entries for the caller to append:
   `{"type":"pattern","id","week","count","refs"}` per reported pattern and
   `{"type":"experiment","week","text","metric","op","value"}` for the new experiment.
   The caller runs `ledger-append`.

## Rules the collector supports

- **Goals disagree.** If `goal_conflicts` is non-empty (a goals file says a decision is pending) or two goals files contradict each other, the FIRST line of the report asks which goal is current. Do not measure against the older one.
- **Protected items are never cut.** An item whose text matches `protected_regex` (compliance, verification, legal, tax, penalty) is in `protected_not_cut`, not in `cut_list`. It may be parked with a date or sized; the report never proposes dropping it.
- **Effort is stated, never guessed.** Every "this week only" item and every parked protected item carries `effort` (the item's own `time` field, or minutes quoted from its notes). When it says "объём неизвестен", sizing the item is the first step.
- **Noise.** `noise_waiting_already_answered` lists topics waiting on a person while one of their own items records that the person answered. Report them under one line "Шум: ждём ответа, который уже записан".
- **Buckets.** A pattern may carry `bucket`: `finish` (a complete artefact that was not sent) or `middle` (work stopped partway). State the bucket the data puts it in; do not decide for the person.
- **Done log.** `done_log` is what was closed, sent or published in the window. A `voice` block in the config may ask to open the report with it.
- **Portfolio goal.** `said_vs_did` carries two numbers when `focus.top` is set: the share of attention on the whole earning portfolio (`focus.projects`) and the concentration inside it (`focus.top` over the portfolio), plus `share_defocus_*` for projects listed in `focus.defocus` (neither earning nor required by a deadline). Report them as plain numbers.
- **Releases first.** `releases` (from `releases_cmd`, an adapter that prints `[{ref,title,version,date}]`; the script never calls a store API) opens the done log: versions shipped, then sends, then the rest. `known: false` means the source is unavailable (say «источник недоступен»), never «релизов нет»; a known source carries `measured`, the date to print beside the line. Commits and sessions are never presented as progress.
- **Journal.** `collect` first brings an append-only journal of typed prompts up to date (`journal` in the config; `mirror_collect.py journal`). One line per prompt: time, local day, project, session, message uuid, character count, label, confidence, who labelled it, label-set version. Never text. A cursor file keeps the byte offset per transcript, so a run reads only new bytes and a run with nothing new makes no model call. A truncated or replaced transcript is re-read and the uuid key prevents duplicates. Labels (one per prompt): `task` sets new work, `steer` corrects or adds to work in progress, `decide` answers or approves, `kick` nudges without new information, `watch` asks to look at something running, `think` thinks aloud, `other` a bare paste. A bare "continue" is labelled by rule; the rest by a headless model call in batches (prompt text is truncated and goes only to that call; excluded directories are never read). Labels change only when the label-set version changes, and then only on demand (`journal --relabel`).
- **Second profile as time only.** `work_profiles` may name a separate profile whose transcripts are counted for time: only timestamp, message uuid and character count are read; its rows are `project: work`, `mode: work`, `by: none`, and no text, directory name or session id reaches the journal, the cursor, a model call or a log.
- **Local time follows the person.** `energy.timezones` is a dated timeline (`from`, `tz`, optional `place`). Build it from evidence such as the committer offsets in git history and trip records; list approximate boundaries as uncertain. Zone-change days and the day after are marked as travel days, not judged.
- **Energy is reported in blocks, not hours.** Hours stay as the raw layer (`own_h`, `work_h`, `overlap_h`, `total_h` by 15-minute bucket, overlap counted once). Three derived numbers lead: (1) *creative blocks*, runs of at least 45 minutes on one own project where the top label is task, think or steer and nothing of another project, of the work profile or of a routine label interrupts (one silent bucket is tolerated, config `block_gap_buckets`); the budget is `blocks_per_day` (default 3), and a day over capacity lowers the next days' suggestion (`debt_blocks`, `suggested_blocks_today`); (2) *leak*, the share of own active time whose top label is decide, kick or watch, plus project switches per active hour; (3) *open loops*, open items whose ball is on the person and that have no dated next step. A plan closes a loop, not the completion, so the cut list and the this-week list are presented as loop-closing. Background, not a claim about the user: demanding work is limited per day to about four hours in sessions (Ericsson et al. 1993); fatigue after a day of hard cognitive control has a metabolic account (Wiehler et al. 2022, Current Biology); switching leaves attention residue (Leroy 2009); making a concrete plan removes the intrusion of an unfinished goal (Masicampo and Baumeister 2011). Do not cite ego depletion or decision-fatigue studies. `energy.json` carries the same numbers, a per-day table and a per-week history (hours, hours per label, blocks, place). The `energy` subcommand recomputes from the journal in about a second; `--ingest` also reads new transcript bytes.
- **Fit to capacity.** Each "this week only" candidate has `cost_h` (from its stated effort) and an optional `kind` (`deep` or `light`). The listed items must fit the week's remaining blocks; an item that does not fit is named as not fitting instead of being listed. Unknown cost stays "volume unknown".
- **Week template.** Optional `week_template: {blocks_by_weekday, autopilot_weekdays, work_expected_h, sunday_flag_h, balance}` lets the person state their rhythm. Capacity per weekday replaces the flat blocks-per-day in the budget and the debt. Own `kick`/`watch` time on an autopilot weekday (plans set, an agent kicked) is counted separately as `autopilot_h` and excluded from the leak share. `rhythm` reports the balance of work and own hours, the last Saturday's work hours and the last Sunday's own blocks and kicks, flagging only above `work_expected_h` / `sunday_flag_h`; protected days, rest mode (`exempt_days`, from `audit_cmd`) and travel days never flag.
- **Work band.** Optional `work_week: {target_h, band_h, uncounted, midweek_template, work_extra_h}`: hours of a second profile per ISO week by sessions only (a conditional measure; calls, reading and thinking are not in it), the last four weeks, state `в полосе` / `ниже` / `выше` with the gap to the band edge, `нет данных` for a week with no rows (never zero), manual `work_extra_h` added and shown separately. On Thursday and Friday the `energy` subcommand sets `midweek_line` only when the projection to Friday evening leaves the band; inside the band it is null.
- **Do the tools serve you?** `tools` in the config reads three generic, read-only sources: `items_cmd` (JSON list of cards an assistant or bot put in front of the person: kind, state, first_seen, closed_at, shown_at, optional closed_by and close_reason), a `checkins` JSONL (energy taps `{date, level}`, drop reasons `{date, reason}`, effort answers `{date, effort_min}`), and `audit_cmd` (JSON counters: `work_origin_leaks`, `mutes_added`, `rest_days`, `protected_days`). Per week it reports cards created, done, dropped, expired, reaped (closed because the source died), median minutes from shown to closed, the busiest day against `cards_per_day_cap`, cards that arrived on protected days, and one noise ratio: the share of closed cards that were dropped with a noise reason (`noise_reasons`) or expired unseen. A non-zero `work_origin_leaks` is the first line of the section. A missing source is "unknown", never zero. `directions` is an optional checklist (`id, title, sign, state: done|live-unverified|not-started, since`); the report gives state counts and asks at most ONE live check per week, the oldest first. A proposal never covers a direction whose state is not `not-started` (it is already built or queued). At most three proposed changes, each one line with the number behind it and its effort; no proposal without a number. Week-over-week arrows (`arrows`) link focus and energy to the tools number, for example leak share against cards per day. Counts and dates only; anything deeper is a question the person takes elsewhere.
- **Optional `voice` block** in the config: a list of extra rules the caller wants applied to the wording and layout (for example: done-log first, counts and dates only with no blame wording, finish-vs-middle question on one live item, a one-line definition of done and a first step for every this-week item, no "not now" state). The skill applies them literally and never invents them.

## Report form (short, in the person's language)

Total at most 2400 characters (the card is one message; details live in the collector output and `energy.json`). Lead with the finding. Layout:

```
Зеркало <week>
Сделано: <releases, then sends, then the rest; "no data" when unknown>
Блоков за неделю: <X> из <Y> возможных, самый длинный <N> ч. На рутину: <P>% времени, <K> переключений в час. Открытых петель: <L> (было <M>).
Всего <X> ч: свои <Y>, работа <Z>, параллельно <W>.
Сказал / сделал: <focus share of sessions> и <of commits> против плана. <one line>
Повторы:
1. <what>: <N> раз, <dates>. <where to look>
Эксперимент прошлой недели: <met|missed|unknown>, <actual> при цели <target>.
Эксперимент на эту неделю: <one behaviour>, проверим по <metric>.
Срезать: <ref> (<proposal>), ...
Инструменты: <leaks line if non-zero>; карточек <N> (максимум <M> в день при лимите <cap>), закрыто <done>/<dropped>/<expired>, шум <P>%; предложения (до 3, с числом и объёмом)
Только на этой неделе (закрывает петли): 1) <deep|light>, <cost>: <item>, зачем: <reason>  2) ... 3) ...
Не на этой неделе: все остальное.
Вопрос для дневника: <one question>
```

## Hard limits

- At most 3 observations; each has a count, dates and a place to verify.
- No adjectives about the person, no diagnosis, no psychology, no motives. Behaviour and numbers only.
- A pattern with fewer than 3 dated occurrences is not reported, however vivid.
- Never print identifiers (passport, tax, account numbers), dates of birth or health data; the collector redacts long digit runs in prompt excerpts, but check anyway.
- Never read paths the config does not list. Sessions from private areas are excluded by `exclude_dir_substrings`; do not work around it.
- Read-only: no sends, no edits, no task changes. Proposals only.

## Gotchas

- Share of sessions counts sessions with a typed user turn in the window, so a long session and a one-line session weigh the same; commits are the corrective. Report both.
- A project outside the projects registry shows as `(none)`; say so instead of guessing its goal.
- Reschedules are read from dated `due_reason*` keys; an item moved without a dated note is invisible. Say "по датированным заметкам".
- The first week has no ledger: `weeks_in_a_row` is 1 and there is no experiment verdict. Say that.

## Don't

- Don't turn the report into advice about how to live. The experiment is the only suggestion.
- Don't add a fourth observation because the third was weak. Fewer is the right answer.
- Don't count assistant-written commits as attention without saying that agents commit too.
