# Background Debugging

For a hard bug — something throwing, failing, flaky, or slow with an unknown cause — run `/solo:diagnose`: build a tight feedback loop that goes red on the bug *before* forming any hypothesis.

When debugging apps with running servers, dev tools, or log streams:

- Run the log/server process as a **background task** (`run_in_background: true`) so you can monitor output while continuing work
- Use Playwright MCP or browser MCP to read console errors directly instead of asking the user to copy-paste
- Provide screenshots of UI issues — Claude Code can read images
