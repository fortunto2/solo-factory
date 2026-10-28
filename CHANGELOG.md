# Changelog

What changed for the people who install this plugin. Docs describe the current state;
history lives here. One entry per version, newest first; `scripts/check-version`
refuses a `plugin.json` version with no entry.

## 1.92.0 — 2026-10-28

- Stop gate scope: `sensor-edit.sh` records every Edit/Write/MultiEdit/NotebookEdit per session, and `sensor-stop.sh` verifies only the files this session wrote that are still changed. A parallel session's uncommitted files no longer block the turn; the receipt counts them. Shell-only writes are not attributed; a session with no recorded writes keeps the whole-tree behaviour.
- New `scripts/prepush-clean-tree.sh -- <cmd>`: a pre-push check runs on a detached worktree of each pushed sha, not on the working tree; ref-only deletions run nothing; `SOLO_PREPUSH_LINK` links untracked data dirs in.
- Principles: queue scripts call the project's gated tool instead of re-implementing its steps; one writing agent per repository (fetch and retry on a ref race); resume an agent stopped by a transient error instead of relaunching it.

## 1.91.0 — 2026-10-28

- New `hooks/irreversible_guard.py` (PreToolUse on Bash): force-push, remote branch deletes, recursive `rm` outside tmp/scratchpad/build dirs, `gh repo|release delete`, and regex lines from `.claude/irreversible-commands.txt` need a human. `ask` where a prompt is guaranteed, `deny` with a reason in `bypassPermissions`/`dontAsk`; override only from the session environment (`SOLO_ALLOW_DESTRUCTIVE=1`); every match logged to `~/.claude/solo/irreversible-guard.log`.
- `solo-verify` limits: a change over 1500 lines added+deleted (`SOLO_MAX_CHANGE_LINES`) prints SPLIT ADVISED; never fails.
- `build` 2.5.0: every acceptance criterion is mapped to the test that proves it, unproven ones listed by name; three rounds on one review finding, then a human. `review` 1.4.0: the same three-round rule.
- `video-edit` 1.0.5: verify media pipelines on at least one real captured file, not only synthetic sources.

## 1.90.1 — 2026-10-27

- `solo-verify`: the empty-suite message no longer claims the exit code would read green. Measured: pytest exits 5 on an empty suite and 2 on a collection error, `cargo test` and `go test` exit 0, so the receipt says the count decides, not the code. `docs/harness-sensors.md` corrected the same way, and its skill count is 57.

## 1.90.0 — 2026-10-27

- `build` 2.4.0, `setup` 2.2.0, `init` 2.2.0, `dev-principles`: who owns the test decides the cycle. Red-green-refactor stays for tests a human wrote or approved, or that come from a contract or acceptance examples. When the agent owns the test, the default is design first (data model, edge cases, contracts), then code and tests together at agreed seams, then a mutation check on changed business logic per phase (mutmut, Stryker, cargo-mutants; one hand-broken line when none is installed). Böckeler's eval (martinfowler.com, Aug 2026) found agent-run TDD cost 2.96x to 8.5x the tokens with no better mutation scores or design, and agents skipped or faked the red step. "A test that has never been red proves nothing" is gone: a red the agent watched proves only that it ran the test.

## 1.89.0 — 2026-10-27

- `content-gen` 1.3.0: a mode for posts from a published write-up. Each channel is rewritten from its own contract (voice, audience, limits, link placement, mechanics), every number comes from the source post, one UTM-tagged link per channel, and a project's gated contract tool (brief → draft until the gates pass, skip only with a reason) is used when it exists. Triggers: "posts from this article", "repurpose this post", "посты из статьи".

## 1.88.0 — 2026-10-27

- `hackathon` 1.4.0: talks, panels and festivals filmed around an event get a post too, with the recording as its spine: the full video near the top with chapter links, a timestamp on every point, public shorts next to the point they make, claims attributed and predictions marked, misheard names corrected only against a second source and fixed in the uploaded subtitles as well. Drafts written by parallel agents stay unpublished until reviewed, because a build that collects every published page ships a half-written one the moment anything else is published.

## 1.87.2 — 2026-10-27

- `hackathon` 1.3.2: post, repo and video link to each other. The post shows repo, demo and video at the top (a repo only when public); the README gets a `Write-up:` line under its tagline and the homepage field; the video description gets one after its first paragraph. Every link is checked for HTTP 200 before it goes into a copy nobody re-reads.

## 1.87.1 — 2026-10-26

- `hackathon` 1.3.1: photos get their EXIF orientation applied before metadata is stripped. Saving without EXIF also drops the rotation tag, so an iPhone HEIC (orientation 4 on a front-camera selfie) went live upside down. Open the final file and look at it before publishing.

## 1.87.0 — 2026-10-26

- `hackathon` 1.3.0: stage 08 starts with "one home for the event". Every event gets one post on the user's own site as the canonical record, and the photos (metadata stripped, selfies un-mirrored), the demo video (uploaded to the user's channel and embedded), the deck PDF, stage slide frames and the live/repo/Devpost/store links are put in place before writing. Social posts are derived from the published post later, as a separate step. Event-date field set to the event's first day where the site has one.

## 1.86.0 — 2026-10-26

- `hackathon` 1.2.0: the report format opens with a hook (lede with the sharpest finding, "The short version") and a per-project scorecard (strong / unproven), and moves the method note to the end. The old template put a paragraph on sources second, so every report opened with how it was recorded. Scorecard rules: critique the work, not people; cite something checkable; judges never publish scores or deliberation.

## 1.85.0 — 2026-10-26

- Analytics default is now [superduper-analytics](https://github.com/fortunto2/superduper-analytics) (self-hosted, cookieless, on Cloudflare) instead of PostHog, in all 10 stack templates, `dev-principles.md` and the README. Stacks get a separate `errors:` field with what each platform really offers and no third-party SDK: App Store Connect crashes + MetricKit, Play Console Android vitals, Workers Logs / `wrangler tail`, Vercel/Supabase/Docker logs. iOS stacks name the SuperDuperAnalytics SPM package; Android, KMP and Python have no client, so they say "POST events to the ingest endpoint" instead of an invented SDK.
- `metrics-track` 1.3.0: funnel and snippets rewritten for `sda.js`, the Swift package and the raw ingest POST; no `identify()` (the funnel is aggregate: counter for visits and store clicks, store campaign reports for installs and purchases); reading via `seo traffic`, `seo conversion`, `seo retention`; legacy Google Analytics only through `seo ga`.
- `deploy` 1.2.2, `legal` 1.0.1, `launch` 1.0.1, `ios-dev` 2.0.3: the PostHog lines point at superduper-analytics (legal: cookieless counter on Cloudflare, App Privacy answers, no ATT).

## 1.84.1 — 2026-10-26

- `video-edit`: check the link before a long upload. A phone hotspot (macOS gateway `172.20.10.1` for iOS, `192.168.43.1` for Android) is metered: hold large uploads and cloud archiving until the user allows them, and make the upload script refuse. Upload sockets need a timeout, or a connection that died during sleep hangs at 0 B/s with retries never firing.

## 1.84.0 — 2026-10-26

- `landing-gen` 1.2.0: SKILL.md is now a router over five stage references. `intake.md` asks the gaps in one batch and picks a layout type (A-E, E = app page); `copy-sections.md` gives the section order, A/B headlines and a sample-vs-shipped rule (`[SAMPLE]` on invented content, never on a live page); `layout-type-spacing.md` holds one tokens block (Tailwind 4 `@theme`), five-step type scale, one spacing scale, nested radius, motion with a reveal that does not hide content when JS is off; `ship.md` covers JSON-LD with sourced Offers only, robots Content-Signals, llms.txt, a real 404, the cookieless superduper-analytics counter with CTA events, forms and legal; `anti-patterns.md` adds a grep gate checked on planted bad and clean fixtures. Structure and visual rules adapted from elayadesign/ai-design-skills `landing-page-design` (MIT, see THIRD-PARTY.md). New triggers: "сделай лендинг", "landing page design", "сверстай лендинг", "лендинг для приложения".

## 1.83.3 — 2026-10-26

- `video-edit`: an outro on a camera's 10-bit HEVC film without re-encoding it: card in the film's bit depth, and a join through MPEG-TS (concat demuxer, `hev1`) when the mp4 seam fails. Measured on a 48-min DJI talk: clean seam, bit-identical film frames, where the old fallback re-encoded to 1.4 Mbit/s. Also: a seam check that parses PSNR under `-v error` can never pass.

## 1.83.2 — 2026-10-26

- `video-edit`: the copy-first recipe ends its audio chain with `asetpts=N/SR/TB`; without it `loudnorm` left a 0.075 s timestamp drift that platforms play as silence.

## 1.83.1 — 2026-10-26

- `ios-dev`: XcodeBuildMCP as one local plugin enabled per project, replacing "keep one `.mcp.json`". Per-repo copies drifted (five without the `mcp` subcommand, exiting on start; three pending approval) and a user-scope entry put 44 iOS tools into every session.

## 1.83.0 — 2026-10-26

- New `hackathon`: one skill for working a hackathon and writing it up, research first. SKILL.md is a router; one reference per stage (01 event rules, judges and mentors with confirmed/probable/unconfirmed labels · 02 scout mode: winners of Devpost hackathons you did not attend, plus a cross-hackathon roll-up · 03 build · 04 live capture with supervox and a PTZ camera on the slides · 05 GitHub hunt by creation date and stack keywords · 06 gallery survey format · 07 pitch · 08 report, hub page, privacy pass). `scripts/devpost.py` walks a Devpost gallery through curl (WebFetch and urllib get 403): winners first, prizes verbatim, Built With, links, story; checked live on Cal Hacks 12.0 (102 winners) and on a gallery with no winners announced (0), plus 6 offline parser tests on copied markup. Rule throughout: no claim without an opened source, "not stated" otherwise.

## 1.82.1 — 2026-10-26

- `video-edit`: "Copy first, encode only what changed" in `references/delivery.md`. A full recording, a trim, a muted line, loudness and an outro need no picture re-encode: copy the video stream, process only the audio, concat the outro. Measured on the same SD card: stream copy 4.4x realtime against 1.2x for an HEVC 1440p re-encode. Upload each file as soon as it is ready.

## 1.82.0 — 2026-10-25

- `secret_guard` hook (new): credentials stay out of the conversation. PostToolUse on every tool masks keys in the output as `[REDACTED:<rule> len=N id=<sha8>]` before the model sees them (Read, Bash, Grep, MCP alike; the output keeps its structure). PreToolUse refuses a Write/Edit that would write a marker over the real secret. UserPromptSubmit blocks a prompt with a pasted key and moves the value to `~/.claude/secrets/<project>.env` (0600). `audit` lists secrets already in transcripts without values; `scrub` rewrites old transcripts, needed because Claude Code echoes a blocked prompt into the transcript as "Original prompt". Verified end to end with `claude -p`: the key was in neither the answer nor the transcript. 20 ms per tool call, 90 ms on 1 MB. Off: `SECRET_GUARD=off`.
- Stop gate: a session that changed nothing is not blocked on a tree that was already dirty or red (`sensor-baseline.sh` at SessionStart).

## 1.81.1 — 2026-10-25

- `transcribe`: both scripts pin `av<19`. PyAV 19 removed `metadata_errors`, which faster-whisper 1.2.1 still passes, so a clean `uv run` failed on the first real file while `--help` worked. Checked from an empty uv cache on both paths.

## 1.81.0 — 2026-10-25

- New `video-edit`: footage to a film with the agent as editor. Editorial rules (cutaways that match
  the words, never over moving lips, hand-picked hook, scenes not best phrases), an eyes-before-render
  pass, and `references/sound.md` + `references/delivery.md` with ffmpeg recipes each re-run on a
  test clip. Found while checking them: Homebrew's default `ffmpeg` has neither `ass` nor `drawtext`;
  a concat-copy outro with a 48 vs 44.1 kHz card came out 8.71 s instead of 8.0 with no error.
- New `transcribe` (was a personal skill): mlx-whisper large-v3 on the Apple GPU as the default on a
  Mac (38-min talk in 8.7 min), language per silence-split chunk, `--words` writes word timings for
  editing. PEP 723 headers, so `uv run` needs no venv; Python pinned `<3.14`.
- New `stem-split` (was a personal skill): Demucs with `-d mps`. Measured 60 s of music in 8.3 s vs
  15.7 s on CPU, stems equal to 0.1 dB. The old text said the Mac was CPU-only.

## 1.80.0 — 2026-10-24

- Stop gate: whole-suite sensors (`pytest`, `cargo test`, `clippy`, `tsc`) run only
  when the change has a file or manifest of their language; otherwise they are
  not-applicable with that reason. Measured on a repo with Cargo.toml and
  pyproject.toml: a `.jpg`/`.yml` change ran cargo test (138 s) and pytest (96 s)
  every turn against the 120 s gate, 325 timeouts in three weeks, no verdict. Now
  0.36 s. Published promises in `rules/harness-sensors.md` changed accordingly.

## 1.79.2 — 2026-10-24

- `swiftui-design-system/references/apple-xcode-skills.md`: install Apple's skills
  and Xcode's MCP server as the plugin Xcode 27.1 exports
  (`xcrun agent plugin path --plugin-format claude`), scoped per project.

## 1.79.1 — 2026-10-24

- `swiftui-design-system` hands SwiftUI correctness to Apple's `swiftui-specialist`
  (bundled with Xcode 27, supersedes training) instead of a third-party skill.

## 1.79.0 — 2026-10-24

- New skill `skill-shelf`: usage per skill from session transcripts, shelve the
  unused to `~/.claude/skills-archive/` with origin and reason, `list` and `restore`
  on demand. Documents the switches for skills that are not files:
  `enabledPlugins`, `syncClaudeAiPlugins`, `syncClaudeAiSkills`. Measured on one
  machine: 198 visible skills → 92 after a pruning pass.
- `make plugin-publish` works again: it expanded `${CLAUDE_CONFIG_DIR:-…}` in make
  instead of the shell, and its `install` was a no-op on an installed plugin.

## 1.78.0 — 2026-10-24

- `idea-validator` agent removed: it preloaded two skills that do not exist
  (`validate-idea`, `apply-stream`) and duplicated `/validate`. Use `/solo:validate`.
- `researcher` agent now preloads `solo:solo-research` (was the missing
  `deep-research`, so it started with no procedure at all).
- Ships 1.77.0's changes, which were pushed without a version bump.

## 1.77.0 — 2026-10-22

- One version number: `plugin.json` is the source, `marketplace.json` and
  `pyproject.toml` follow it, `scripts/check-version` (run by `make doctor`) refuses
  drift. Before this the repo carried 1.77.0 / 1.25.0 / 1.20.0 / 1.22.0 at once.
- `rules/routing.md` no longer carries the Signal → Route table. Prompt-shape routing
  is done by the profile's `UserPromptSubmit` hook (harness-core); the rule keeps the
  directory markers and the pipeline order.
- `rules/skills.md` keeps only the current rules; the incident history moved to
  `docs/harness-case-log.md`.
- The SessionStart echo no longer claims a version or a hand-picked skill list.
- New skills since 1.71: `creator-growth`, `paper`, `open-dataset`, `youtube-channel`.
- Stop gate: an UNKNOWN on unchanged files blocks once, not every turn.
- `ios-release`: face data triggers an App Review 2.1 information request.
