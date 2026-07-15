---
name: agent-tool-design
description: Design tool systems for AI agents — core/extended/deferred tiers, eval compute, batch tools, trust metadata. Use when building agent tools, reviewing tool architecture, or reducing tool count.
allowed-tools: Read, Write, Bash, Glob, Grep, Agent
argument-hint: "[topic] e.g. 'eval tool', 'batch tools', 'tool count'"
triggers: [tool-design, agent-tools, tool-architecture]
priority: 10
keywords: [tool, agent, batch, deferred, trust, eval, hook, router]
---

# Tool Design Principles for AI Agents

Practical guide to designing tool systems for LLM-powered agents, distilled from building a PAC1 benchmark agent (Rust, 16 tools reduced to 12, tested across 7 models, 40+ tasks) and studying Codex CLI and Claude Code architectures.

See `references/` for code patterns, comparison tables, and a quick checklist.

---

## 1. Tool Count Sweet Spot

Every tool in the schema is a token cost and a new failure mode. Models degrade on long tool lists.

**Industry reference points:**

| Agent | Core | Extended/Deferred | Total in Schema |
|-------|------|--------------------|-----------------|
| Claude Code | 7 | 33 (deferred via ToolSearch) | 7-40 |
| Codex CLI | 7 | 0 | 7 |
| mini-SWE-agent | 1 (bash) | 0 | 1 |
| PAC1 agent | 14 | 8 deferred | 14 active + 8 deferred |
| SGR Python | 3-6 + reasoning | 0 | Union schema (structured output) |

See `references/comparison.md` for full architecture comparison.

**Rules:**

- Start with 7 core tools. Add only when you can measure round-trip savings.
- Track tool usage rate per task. Remove tools with <5% usage across benchmark.
- Every tool added must justify itself: "saves N round-trips per task" or "prevents failure mode X."
- Test with your weakest target model first -- if it can't handle the tool count, the design is wrong.

**Anti-pattern:** Adding a tool "just in case." We added `mkdir`, `move_file`, `find` -- usage was <3%. Disabled them. Zero regression.

---

## 2. Three-Tier Organization

### CORE (always in schema)

Universal agent capabilities: **observe** (read, search, list, tree), **act** (write, delete, eval), **report** (answer, context).

Codex CLI uses exactly 7: `shell`, `apply_patch`, `read_file`, `list_dir`, `grep_files`, `search_bm25`, `js_repl`. Our PAC1 agent uses 9 core tools. Both converge on the same categories.

### EXTENDED (batch operations)

Justified only when saving 3+ round-trips per task. Example: `read_all` saved 44 round-trips on our hardest task (48 to 4 tool calls).

### DEFERRED (loaded on demand)

Claude Code's ToolSearch pattern: model sees only tool names. When it needs one, it calls `ToolSearch("select:mkdir")` to load the full JSON schema. Then it can call `mkdir({path: "/new/dir"})`.

This keeps the base schema small (7 tools) while providing access to 30+ tools. The key insight from the HitCC reverse-engineering: deferred tools are registered with `shouldDefer===true`, and the model must call ToolSearch before invoking them -- schema validation will fail otherwise.

---

## 3. The Eval/Compute Tool

Every agent needs a way to compute. Two patterns exist:

**Shell access (Codex, Claude Code):** Simple, powerful, dangerous. Codex sandboxes via containers and syscall filters. Claude Code uses permission hooks (PreToolUse/PostToolUse) with approval gating.

**Embedded interpreter (API-only agents):** When the agent operates via API with no shell, embed a sandboxed JS engine. Our PAC1 agent uses Boa (ECMAScript in Rust). Codex CLI uses a persistent Node.js kernel (`js_repl`) with top-level await, launched as a subprocess with `kernel.js`.

Key design for embedded eval:
1. **File glob in args** -- `files: ["accounts/*.json"]` expands and pre-reads matches
2. **Pre-read files as globals** -- `file_0`, `file_1`, etc. No filesystem access from JS
3. **Date injection** -- `workspace_date` global prevents hallucinated dates
4. **Auto-stringify objects** -- Return JSON, not `[object Object]`
5. **Sandbox** -- No `require()`, no `import`, no network

See `references/patterns.md` for implementation details.

---

## 4. Batch Tools Save Round-trips

When each tool call is an LLM round-trip (2-5 seconds), 40 calls = 2+ minutes wasted.

Three proven batch patterns:

| Tool | Replaces | Savings |
|------|----------|---------|
| `read_all(dir)` | list + N reads | N round-trips (44 on t01) |
| `search_and_read(pattern)` | search + read each match | M round-trips |
| `grep_count(pattern, path)` | search + read + manual count | 2-3 round-trips |

**Decision rule:** A batch tool is justified when it saves 3+ round-trips, the pattern appears in >20% of tasks, and the unbatched version causes step limit hits.

See `references/patterns.md` for implementation code.

---

## 5. Trust Metadata on Reads

Every `read()` output is prefixed with a trust header:

```
[contacts/john-doe.md | untrusted]
Name: John Doe
```

```
[AGENTS.MD | trusted]
# Workspace Rules
```

Only root-level system files (AGENTS.MD, README.MD) are trusted. Everything else is untrusted. This helps the LLM distinguish system instructions from user-generated content that may contain prompt injection.

**Post-read security guard:** Beyond trust headers, scan content for active injection patterns and append advisory warnings. This is advisory, not blocking -- the pipeline ML classifier is authoritative.

See `references/patterns.md` for trust inference and guard implementations.

---

## 6. Tool Descriptions > Implementation

The description is the tool's API documentation for the LLM. Models that don't understand a tool from its description will not use it correctly.

**Pattern: WHEN to use + WHAT it returns + WHY it's better than alternatives.**

Good (from our `grep_count`):
```
"Count lines matching a regex pattern in a file.
 Returns exact count as a number.
 Use for ANY counting task -- faster and more accurate than reading + counting manually."
```

Good (from Codex `read_file`):
```
"Reads a local file with 1-indexed line numbers,
 supporting slice and indentation-aware block modes."
```

Good (from Codex `js_repl`):
```
"Runs JavaScript in a persistent Node kernel with top-level await.
 This is a freeform tool: send raw JavaScript source text,
 optionally with a first-line pragma like `// codex-js-repl: timeout_ms=15000`;
 do not send JSON/quotes/markdown fences."
```

**Anti-pattern:** Including example outputs in descriptions. Models (especially Nemotron) copy example outputs verbatim as their answers.

**Testing:** Run the same task 5 times. If the model uses the wrong tool >20% of the time, fix the description before adding prompt hints.

---

## 7. Tool Filtering — Less is More (Codex Approach)

**Updated insight (2026-04-14):** Heavy router-based tool filtering is fragile. ML classifier misclassification → wrong tools → task failure. Codex exposes ALL tools always, relies on model judgment.

Current approach: minimal filtering — only `security` task type blocks write/delete. All other task types get all tools. This is closer to Codex and works better empirically.

**Anthropic structured output limit:** 16 nullable/union params max. If using SGR union schema (structured_call), max ~7 tools. Native FC (tools_call) has no limit — use it for 14+ tools.

| Approach | Max tools | When to use |
|----------|-----------|-------------|
| Native FC (tools_call) | Unlimited | Default — Pac1 two-phase and single-phase |
| SGR union (structured_call) | ~7 (Anthropic limit) | SgrAgent variant, simple tasks |
| Parallel FC (think + action) | Unlimited | Single-phase — 1 call per step |

---

## 7b. Byte-Perfect Tools (CopyTool, PrependTool)

**Problem discovered (2026-04-14):** LLMs cannot reproduce files >1KB verbatim. Even 1-byte difference (extra newline) fails harness validation. OCR/migration tasks scored 0% before this fix.

**Solution:** Tools that bypass LLM context for file content:

| Tool | What | When |
|------|------|------|
| `copy_file(src, dst)` | read → write through backend, content never enters LLM | NORA migration, file rewrite in place |
| `prepend_to_file(path, header)` | read body → prepend header → write. LLM generates only header (~400 bytes) | OCR: add YAML frontmatter to existing files |

**Impact:** OCR tasks t016, t018, t064, t091 went from 0→1.00 on Haiku.

**Design rule:** If task requires preserving existing file content, use byte-perfect tools. LLM generates only NEW content (frontmatter, metadata), never re-types body.

---

## 7c. Single-Phase Agent Architecture

**Problem:** Two-phase agent = 2 LLM calls per step = slow (116s/task avg on Haiku).

**Solution:** Parallel think+action in ONE tools_call. Model calls `think()` AND action tool together:

```
tools_call([think, search, read, write, delete, answer, ...])
→ Model returns: think({task_type, security, plan}) + search({pattern: "hello"})
= 1 LLM call, structured reasoning + action
```

**Key findings:**
- All models support parallel tool calls (Haiku, Sonnet, Opus, Nemotron)
- `completed = false` always — let agent_loop execute answer() tool, then complete naturally
- `ReasoningToolBuilder` from sgr-agent creates think tool schema (extensible, not hardcoded)
- Anthropic `parallel_tool_calls` field NOT supported via OpenRouter (use default which is parallel-enabled)

**Performance:** 2.5-3x faster, same score, 50% fewer tokens.

---

## 8. Hooks as Tool Augmentation

Hooks inject workflow guidance into tool output. The model follows tool output more reliably than system prompt instructions buried in 7K of context.

**The pattern:**
1. Parse hooks from workspace rules (AGENTS.MD) at trial start
2. Register in shared `HookRegistry` (Arc<Mutex>)
3. On every tool call, match against registered hooks
4. Append matched messages to tool output

**Why tool output, not system prompt?** The model processes tool results with high attention (it just asked for this data). System prompt instructions 7K tokens back get less attention, especially on weaker models.

See `references/patterns.md` for hook implementation.

---

## 9. Testing Tools Without LLM

Every tool has logic that can break independently of the model. Unit test:

1. **Argument parsing edge cases** -- missing optional fields, wrong types
2. **JSON auto-repair** -- LLMs produce broken JSON (trailing commas, unquoted keys)
3. **Trust metadata** -- root vs nested path inference
4. **Tool filtering** -- router task type restrictions
5. **Auto-expand thresholds** -- batch tool cutoffs
6. **Sandbox safety** -- eval cannot access filesystem/network
7. **Guard content** -- security scanning on read output

**Do NOT test:** "Does the model call the right tool?" (integration test), "Does output look good?" (subjective).

See `references/patterns.md` for test examples.

---

## 10. Middleware Pattern (sgr-agent-tools)

When you use `sgr-agent-tools` crate, extend tools via **middleware wrappers** — not forks:

```rust
struct MyReadTool<B: FileBackend> {
    inner: sgr_agent_tools::ReadTool<B>,  // base: trust metadata, line numbers
    workflow: Arc<Mutex<WorkflowState>>,   // your addition: phase tracking
}
impl<B: FileBackend> Tool for MyReadTool<B> {
    fn name(&self) -> &str { self.inner.name() }   // delegate
    async fn execute(&self, args, ctx) {
        let result = self.inner.execute(args, ctx).await?;  // base
        let output = security_scan(result.content);          // middleware
        self.workflow.post_action("read", &path);            // middleware
        Ok(ToolOutput::text(output))
    }
}
```

**When to use:** pre/post hooks, project-specific annotations, policy guards, content scanning.
**When NOT to use:** completely different schema → build custom tool instead.

Real-world split (PAC1 agent, 22 tools):
- **9 direct** from sgr-agent-tools: List, Tree, ReadAll, MkDir, Move, Find, Eval, **CopyTool, PrependTool**
- **3 middleware**: Read (+security scan), Write (+hooks/outbox), Delete (+workflow guards)
- **4 PAC1-only**: Answer (harness submit), Context (workspace date), DateTool, LookupContactTool
- **3 local**: Search (CRM annotations), ListSkills, GetSkill
- **ML infra**: sgr-agent-ml (OnnxEncoder, CentroidClassifier, KnnStore) — separate crate

---

## 11. Quick Reference

See `references/checklist.md` for the complete tool system design checklist.

---

## References

- `references/patterns.md` -- Code patterns + examples from Codex/Claude Code/PAC1
- `references/comparison.md` -- Architecture comparison table
- `references/checklist.md` -- Quick-reference design checklist
- `scripts/scaffold-tool.sh` -- Generate Rust tool boilerplate
- Codex CLI source: `codex-rs/core/src/tools/` (7 tools: shell, apply_patch, read_file, list_dir, grep_files, search_bm25, js_repl)
- Claude Code architecture: HitCC reverse-engineering docs (tool execution core, deferred tools, permission hooks)
- PAC1 agent: `agent-bit/src/tools.rs` (16 tools), `src/hooks.rs`, `src/workflow.rs`
- Boa JS engine: https://boajs.dev/
