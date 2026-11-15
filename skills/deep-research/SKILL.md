---
name: solo-deep-research
description: Deep research on any question from three independent angles in parallel, every claim tied to a source, contradictions checked before the answer. Use when "deep research", "дип ресерч", "глубокое исследование", "разберись глубоко", "parallel research", "research it from several angles", or a decision rests on facts one quick search will not settle. Do NOT use for a quick idea scan (use /research), idea scoring and PRD (use /validate), or handing coding tasks to worker agents (that is the swarm tool, not research).
license: MIT
metadata:
  author: fortunto2
  version: "2.0.0"
  openclaw:
    emoji: "🔬"
allowed-tools: Read, Grep, Glob, Bash, Agent, WebSearch, WebFetch, Write, mcp__searxng__web_search, mcp__searxng__web_extract, mcp__solograph__kb_search, mcp__solograph__project_info, mcp__solograph__symbol_search, mcp__solograph__session_search
argument-hint: "[question, idea or topic]"
---

# /deep-research

Research "$ARGUMENTS" deeply: three angles in parallel, each claim with its source, then one
pass that checks the claims against each other before anything is concluded.

Use it when being wrong is expensive: a market to enter, a tool to bet on, a legal or
financial fact, a technical choice. For a first look at an idea, `/research` is cheaper.

## 1. Before searching

- **What is already known.** If MCP `kb_search` is available, search the local knowledge base
  first; if `session_search` is available, check whether this was researched before. Start from
  what exists and say what it already answers.
- **The question, sharpened.** Write the one question the answer must settle and what would
  change the decision. A vague topic becomes 3–5 concrete sub-questions.
- **Three angles that do not overlap.** Pick them for this question. For a startup idea the
  default is market (competitors, size, pricing), users (pain, sentiment, quotes) and tech
  (feasibility, open-source, effort). For a tool: capability, cost and limits, what users report.
  For a fact: primary sources, secondary reporting, counter-evidence.

## 2. Three researchers in parallel

Spawn three subagents (Agent tool) in one message so they run at once. Each brief carries the
question, its own angle, what is already known, and the source rules below. Each returns a list
of findings, every one with a URL and the date of the source.

Agent teams work too when available (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`), but plain
subagents are enough: the researchers do not need to talk to each other, the lead compares them.

**Source rules for every researcher:**
- Each claim carries a link to where it was read, and the source's date.
- Prefer primary sources: the vendor's docs and pricing page, the filing, the paper, the
  statute, the repo. A blog quoting them is a pointer to the primary, not a source.
- Numbers keep their unit, date and scope ("$4.2B global TAM 2025, per X", not "a big market").
- Not found is a finding: say what was searched and that it came back empty.
- No source, no claim. A guess is labelled as a guess.

**Search backends**, in this order where available: MCP `web_search` (engine routing,
`site:` filters), WebSearch (built in), MCP `web_extract` or WebFetch to read a page in full.
Targeted: `site:reddit.com`, `site:news.ycombinator.com`, `site:github.com`, official docs.

## 3. Check before concluding

The lead, not a researcher:
- Lines up the three lists: where they agree, where they contradict, what only one saw.
- Opens the source of every claim the conclusion rests on and confirms it says that, with the
  date. A claim whose source does not hold it is dropped and named as dropped.
- Resolves contradictions by the better source (primary over secondary, newer over older) or
  leaves them open and says so.
- Separates what is verified from what is reported and from what is inferred.

## 4. Output

`docs/research.md` in the current project (for an idea, the format from `/research`), or the
answer in chat when there is no project. It holds:
1. **Answer first**: the question and the conclusion in two or three sentences, with how sure.
2. **Findings by angle**, each with its link and date.
3. **Contradictions and open questions**, and what would settle them.
4. **Verdict**: for an idea GO / NO-GO / PIVOT and the next step (`/validate <idea>`); for other
   questions, the recommendation and what it depends on.

## Common issues

### The three angles return the same links
**Cause:** the angles overlap or the briefs are generic.
**Fix:** make each brief name what the angle must NOT cover, and give each its own search terms.

### Web search returns little
**Cause:** only the built-in search is available.
**Fix:** WebSearch still works. For richer results with engine routing (Reddit, GitHub, YouTube),
set up [SearXNG](https://github.com/fortunto2/searxng-docker-tavily-adapter) (self-hosted, free)
and the solograph MCP.

### A finding cannot be traced back
**Cause:** a researcher summarised without keeping the URL.
**Fix:** the claim does not go into the answer. Ask that researcher for the source or drop it.
