---
name: solo-secrets
description: Keep API keys, tokens and passwords out of repos, configs, argv and chat logs — store them in the OS keystore (macOS Keychain, Linux libsecret), track rotation, scan for plaintext and migrate it. Use when user says "куда положить токен", "где хранить ключ", "секрет", "пароль в конфиге", "api key", "store this token", ".env", "rotate the key", "ротация", "токен утёк", "scan for secrets", or a credential shows up in a file, a prompt or a tool output. Do NOT use for auth flows inside an app (use /deploy or the stack template) or for redacting transcripts (the secret_guard hook does that).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "🔐"
allowed-tools: Read, Bash, Grep, Glob, Edit
argument-hint: "[scan <path> | set <name> | migrate <file> <key> <name> | due]"
---

# /secrets — credentials in the keystore, never in plain text

One CLI, `scripts/secret` (stdlib Python 3.10+, no install), and one registry of
**metadata only**. Values live in the OS keystore; everything a human or an agent sees
is masked to the first 4 characters and the length: `cfut…(45)`.

```bash
S=${CLAUDE_PLUGIN_ROOT:-.}/skills/secrets/scripts/secret   # or copy the path; alias it
```

## When a secret appears — do this, in order

1. **Never echo it back.** Do not repeat, quote or "confirm" the value in a reply, a
   commit, a file or a command line. Refer to it by name.
2. **Was it seen anywhere that keeps logs?** A chat, an agent transcript, a screenshot,
   CI output, a ticket, a commit (even one later amended): it is **leaked**. Run
   `secret leak <name> --where "<where>"` and tell the user to rotate it now.
   Claude Code writes prompts to `~/.claude/projects/*/*.jsonl`; a blocked prompt is
   still echoed there.
3. **Store it** from stdin, never argv: `pbpaste | secret set example-api-token --class api-scoped --used-in "<tool>"`
   (or run `secret set <name>` for a hidden prompt). Shell history and `ps` both see argv.
4. **Point the code at the keystore** (`secret migrate` prints the snippet), then blank
   the plaintext. Keep the old value until the new one works; never delete the only copy.
5. **Rotate** when it is leaked or due: `secret rotate <name>` shows where to issue a new
   value, stores it, and resets the clock. Revoke the old value at the provider.

## Commands

| Command | Does |
|---|---|
| `secret set <name> [--class C --scope S --used-in P --rotate-url U --note T]` | value from stdin or a hidden prompt → keystore; metadata → registry |
| `secret add <name> [same flags]` | metadata only: an item already in the keystore, or one tracked for rotation |
| `secret get <name>` | value to stdout, for piping: `TOKEN="$(secret get x)"` |
| `secret exec A=ENV [B=ENV2] -- cmd` | runs one command with the values in its environment, nothing exported |
| `secret list` | metadata + whether the keystore holds the item |
| `secret due` | overdue / due in 30 days; exit 1 when overdue |
| `secret rotate <name> [--revoked]` | guided rotation; `--revoked` = old value killed, no replacement |
| `secret leak <name> --where W` | class → `leaked`, due today |
| `secret scan [paths] [--json] [--min high] [--gh]` | plaintext secrets, masked; `--gh` asks GitHub if a remote is PUBLIC |
| `secret migrate <file> <key> <name> [--remove]` | `a.b.c` in YAML or `KEY` in env/toml/ini → keystore, read back, then (optionally) blanked |
| `secret check [paths]` | one counted line for a recurring health check; exit 1 on critical/high/overdue |

Registry: `$SECRETS_REGISTRY`, default `~/.config/secrets/registry.json`. It holds no
values, so it can be committed to a **private** repo. Its `scan` block takes `paths`
(default scan roots), `exclude` (globs) and `owners` (remote substrings that are yours;
a tracked hit in a clone of someone else's repo is reported `low`).

## Policies

| Class | Rotate every | For |
|---|---|---|
| `prod-admin` | 90 days | account-wide or write access to production: cloud admin, DNS, payments, DB owner |
| `api-scoped` | 180 days | a token limited to one API and one project (the default) |
| `personal-low` | 365 days | read-only or low-blast-radius personal tokens |
| `leaked` | now | anything seen in a chat, log, screenshot, commit or public place |

Rules that do not bend:

- **Never in git**, not even a private repo, not even "for a minute". History keeps it.
- **Never in argv or shell history.** Pipe from stdin or use the hidden prompt.
- **Never in a plain config** that a tool reads; configs hold the keystore *name*.
- **Least privilege, one token per tool.** A token shared by three tools cannot be
  rotated without breaking two of them, and its leak has three blast radii.
- **Leak → rotate now**, not at the next due date. Removing it from the file does not
  un-leak it.
- **Files that must exist as files** (`.p8`, `.pem`, service-account JSON): keep them in
  `~/.secrets/` with `chmod 600` (directory `700`), outside every repo, and register
  them with `secret add <name> --note "file: ~/.secrets/…"`. If a tool can take the
  content instead of a path, store it base64: `base64 < key.p8 | secret set example-p8-key`
  and decode at use: `secret get example-p8-key | base64 -d`.

## Scan

`secret scan` walks the paths (skipping `node_modules`, venvs, build output, lockfiles,
files over 1 MB) and reports three kinds of evidence:

- **prefixed tokens** — `sk-`, `sk-ant-`, `ghp_`, `github_pat_`, `glpat-`, `xox?-`,
  `AKIA`, `AIza`, `cfut_`, `hf_`, `npm_`, `whsec_`, Telegram bot tokens, JWTs, private key
  blocks, DSN passwords. Counted anywhere, docs and tests included.
- **name = value** — a secret-sounding name (`*_TOKEN`, `api_key`, `clientSecret`…)
  with a value that is not a reference (`${X}`, `os.environ`, `config.x`), a placeholder,
  a URL, a path or an identifier, and has the entropy of a key. In code files only quoted
  literals count; in tests, docs, examples and translations only long high-entropy ones.
- **key files by name** — `AuthKey_*.p8`, `*.pem`, `*.p12`, service-account JSON,
  `*token*.txt`.

Severity is about **where it sits**, not what it is: `critical` = tracked in git (strong
rule, or any rule in a PUBLIC repo); `high` = untracked but not gitignored, one `git add -A`
from a commit; `medium` = gitignored or outside git, plaintext still to move; `low` = a
Supabase anon JWT (public by design) or a third-party clone. A bare hash or UUID is never
flagged on its own. A line can opt out with `secret-scan: ignore`.

**A tracked secret is not fixed by deleting the file.** It is in history and in every
clone: rotate first, then decide whether to rewrite history (`git filter-repo`) — that is
the owner's call, it breaks every clone and fork.

## Other keystores

The CLI picks the backend: macOS `security` (Keychain, generic password,
service=`<name>`, account=`$USER`), else Linux `secret-tool` (libsecret, needs a running
Secret Service such as GNOME Keyring). For 1Password, store with
`op item create --category "API Credential" --title example-api-token` and read with
`op read "op://Private/example-api-token/credential"`; `op run --env-file` is the
equivalent of `secret exec`. Keep the registry either way: rotation dates are the part no
keystore tracks for you.

## Gotchas

- `security add-generic-password -w <value>` puts the value in argv. The CLI writes
  through `security -i` on stdin with a hex value instead.
- `security find-generic-password -w` prints hex for values with non-printable bytes;
  store binary as base64.
- The first read of a Keychain item from a new binary may raise a macOS prompt; "Always
  Allow" binds it to that binary path.
- A gitignored `.env` is still plaintext on disk and in every backup; it is `medium`, not fine.

## Don't

- Don't paste the value into the chat to "check it". Use `secret list` (masked).
- Don't commit the registry to a public repo: names, scopes and file paths are a map for
  an attacker even without values.
- Don't rewrite git history to "fix" a leak before rotating. The old value is already out.
