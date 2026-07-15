# Architecture Comparison

Side-by-side analysis of tool architectures from Codex CLI, Claude Code, and PAC1 agent.

---

## Tool Count & Organization

| Dimension | Codex CLI | Claude Code | PAC1 Agent |
|-----------|-----------|-------------|------------|
| Core tools | 7 | 7 | 9 |
| Extended/batch | 0 | 0 | 3 (read_all, search_and_read, grep_count) |
| Deferred | 0 | 33 (via ToolSearch) | 5 (mkdir, move, find, list_skills, get_skill) |
| Total available | 7 | 40 | 17 (12 active) |
| Schema size | Fixed | Dynamic (grows on demand) | Fixed per task type |

---

## Tool-by-Tool Mapping

| Capability | Codex CLI | Claude Code | PAC1 Agent |
|------------|-----------|-------------|------------|
| **Execute** | `shell` / `shell_command` / `exec_command` | `Bash` | -- (API-only) |
| **Compute** | `js_repl` (Node kernel, freeform grammar) | `Bash` (Python/Node via shell) | `eval` (Boa JS engine, sandboxed) |
| **Read** | `read_file` (slice + indentation modes) | `Read` (offset + limit) | `read` (line numbers, range, trust metadata) |
| **Write** | `apply_patch` (unified diff or freeform) | `Edit` (exact string replace) / `Write` | `write` (full or ranged overwrite + hooks) |
| **Search** | `grep_files` (ripgrep wrapper, 30s timeout) | `Grep` (ripgrep, multiple output modes) | `search` (auto-expand, smart retry) |
| **Semantic search** | `search_bm25` (BM25 + app connectors) | -- | `query_crm` (petgraph + ONNX embeddings) |
| **List/tree** | `list_dir` (depth + pagination) | `Glob` (pattern matching) | `list` + `tree` |
| **Delete** | via `shell` | via `Bash` | `delete` (policy-gated, batch paths) |
| **Image** | `view_image` | `Read` (multimodal) | -- |
| **Sub-agents** | `spawn_agent` / `send_input` | `Agent` (sub-agent tool) | -- |
| **Deferred lookup** | -- | `ToolSearch` (name -> full schema) | `list_skills` / `get_skill` |
| **Batch read** | -- | -- | `read_all` (dir -> all files) |
| **Batch search** | -- | -- | `search_and_read` (search + auto-read) |
| **Count** | -- | `Grep` (count mode) | `grep_count` |

---

## Architectural Patterns

### Permission Model

| Agent | Model | How |
|-------|-------|-----|
| Codex CLI | Approval-based | `ExecApprovalRequest` checks `is_known_safe_command()`, unknown commands prompt user |
| Claude Code | Hook-based | `PreToolUse` / `PostToolUse` hooks gate execution, permission merge |
| PAC1 Agent | Policy + Workflow SM | `policy.rs` for file protection, `workflow.rs` for phase-based guards |

### Tool Output Schema

| Agent | Pattern |
|-------|---------|
| Codex CLI | Only `exec_command` defines `output_schema` (JSON with exit_code, output, session_id). Others return plain text |
| Claude Code | Tools return `tool_result` blocks. Some return `contextModifier` attachments |
| PAC1 Agent | All tools return `ToolOutput::text()`. Trust metadata + hook messages appended |

### Error Handling

| Agent | Pattern |
|-------|---------|
| Codex CLI | `FunctionCallError` type with structured error messages |
| Claude Code | `is_error: true` flag on tool_result, with retry hints ("select tool via ToolSearch first") |
| PAC1 Agent | `ToolError` enum, JSON auto-repair on parse failure, retry on empty response |

---

## Key Design Trade-offs

### Codex: Minimal + Freeform

- 7 tools total, never changes
- `js_repl` uses freeform grammar (Lark) instead of JSON -- unique approach for code-as-input
- `apply_patch` also supports freeform (unified diff format)
- No batch tools needed -- shell can do anything in one call
- Pro: simple schema, reliable tool selection
- Con: requires shell access (not suitable for API-only environments)

### Claude Code: Dynamic + Deferred

- 7 core tools visible, 33+ available via ToolSearch
- Schema grows dynamically as model discovers tools
- MCP tools (`isMcp===true`) auto-deferred
- Built-in tools can also be deferred via `shouldDefer===true`
- Pro: scales to unlimited tools without schema bloat
- Con: extra round-trip per new tool discovery

### PAC1: Task-Filtered + Augmented

- 12 active tools, filtered per task type by ML classifier
- Router restricts available tools based on task (delete = no write)
- Trust metadata + hook injection augment tool output
- Batch tools replace multi-step patterns
- Pro: structural safety guarantees, round-trip efficiency
- Con: classifier errors can lock out needed tools (mitigated by step-based unlock)
