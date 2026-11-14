---
name: solo-kindle
description: Make, convert, find and e-mail books to a Kindle (Send to Kindle by e-mail). Use when user says "на киндл", "отправь на Kindle", "сконвертируй книгу", "epub", "сделай книгу", "найди книгу", "send to Kindle", "make an ebook", "convert to epub", or hands a file, URL or outline that should end up as a book on a Kindle. Do NOT use for printable PDFs (use /pdf-print) or for audio and video transcripts (use /transcribe).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "📚"
allowed-tools: Bash, Read, Write, Edit
argument-hint: "[convert <file|url> | make <folder> | find <query> | send <file> --to <slug>]"
---

# kindle: build a book, find a book, mail it to a Kindle

One CLI, four verbs. `uv run scripts/kindle.py <verb>` (deps are inline; needs `pandoc`).

| Verb | Does |
|---|---|
| `convert <file\|url>` | md, txt, html, docx, fb2, epub, a URL → Kindle-ready EPUB. PDF passes through untouched. Prints a JSON check (title, author, lang, TOC, size) |
| `make <folder\|outline.md>` | chapters → one EPUB with title page, TOC, chapter breaks, optional cover; images resized and greyscaled for e-ink |
| `send <file> --to <slug>` | mails the file to that recipient's Send-to-Kindle address |
| `find <query>` / `find --get N` | searches legal free catalogs, downloads result N |

## Generating a book (the agent writes the text, the script assembles)

1. Outline first: title, reader, language, 5-15 chapters with one line each.
2. Write one file per chapter: `book/01-name.md`, `02-...`, each starting with `# Chapter title`. Keep one language, one voice, and write the chapters one at a time so each stays coherent with the outline.
3. `book/book.yaml`: `title`, `author`, `lang` (ru/en), optional `cover: cover.jpg`, `publisher`. Metadata lives here once, not per chapter.
4. `kindle.py make book/` → read the JSON: `chapters` matches your count, `problems` is empty.
5. Images: reference them relatively (`![caption](fig/a.png)`); they are resized to 1200x1600 and greyscaled. `--color` keeps colour.
6. Then `send`, after a `--dry-run`.

## Sending: the one setup step per Kindle owner

Amazon accepts mail only from addresses on the owner's **Approved Personal Document E-mail List**. Each Kindle owner adds the sender address once: amazon.com → **Manage Your Content and Devices → Preferences → Personal Document Settings** (the same page shows their `…@kindle.com` address). Without it Amazon drops the mail silently. Limits and sources: `references/amazon-limits.md`.

```bash
export KINDLE_CONFIG=path/to/config.yaml      # or --config; shape: references/config.example.yaml
kindle.py send book.epub --to reader --dry-run # To/From/file/size, sends nothing
kindle.py send book.epub --to reader
```

Guards, all enforced by the script: recipient must exist and be `enabled` with a real address; one file per mail; only types Amazon accepts (epub, pdf, docx, txt, html, rtf, images; **not** mobi/azw3/fb2: convert first); size under the limit; the same file to the same slug is refused for 24 h unless `--again`; per-recipient daily cap (default 10); every send is a line in `~/.config/kindle/sends.jsonl` (time, slug, file, bytes, sha256, result). The subject is empty: Amazon says none is needed.

Sender is a Gmail CLI wrapper named `gws-*` on PATH (`messages.send` through its upload path), or SMTP via `KINDLE_SMTP_HOST/USER/PASS[/PORT/FROM]`. Never a wrapper that is read-only, and never a bare `gws` that points at another account.

Exit codes: 0 ok, 1 error, 2 config or recipient, 3 file refused (type, size), 4 duplicate, 5 daily cap, 6 send failed.

## Finding books (legal sources only)

`find` queries Project Gutenberg (Gutendex), Standard Ebooks (OPDS), Internet Archive (only items marked public domain) and Wikisource (ru/en, exported to EPUB). One request per second. Output: title, author, language, source, licence note, page link. `find --get N` saves to the work dir; then `convert`/`send`.

No shadow libraries, no DRM removal, no paywalled content. If the book is not in these catalogs: the user supplies a file they own, or buys it in the Kindle store.

## Gotchas

- Russian: `lang` is guessed from the text, or set `--lang ru`; hyphenation comes from that. docx input has no language signal, pass `--lang`.
- PDF: Kindle shows it fixed-layout; reflow is poor. Convert from the source text when there is one.
- mobi, azw3, djvu input needs Calibre's `ebook-convert` (not required otherwise; the script uses it only when present).
- Gutendex answers 503 now and then; the script retries once, then reports the source and still shows the others.
- Wikisource EPUB comes from the Wikimedia export service and can be slow; it can include a whole multi-page work.
- Test hooks: `KINDLE_STATE_DIR` (audit log, default `~/.config/kindle`), `KINDLE_WORK` (work dir).

## Don't

- Send without `--dry-run` first on a new recipient or a new file kind.
- Put recipient addresses in the repo; they live in the private config.
- Pull books from sources not listed above.

More: `references/sources.md`.
