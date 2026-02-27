# AI Code Comments Convention

Use special prefixes for AI agent memory and coordination:

- `# AI-NOTE:` — important context for future AI sessions
- `# AI-TODO:` — task for later implementation
- `# AI-ASK:` — question needing human answer
- `# AI-PATTERN:` — common pattern worth documenting

Before modifying a file, search: `grep -r "# AI-" file`. Keep concise (one line). Remove AI-TODO after completing, convert AI-ASK to AI-NOTE after answered.
