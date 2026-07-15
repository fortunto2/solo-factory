# Code Patterns & Examples

Concrete implementations from Codex CLI, Claude Code (HitCC), and PAC1 agent.

---

## Codex CLI Tool Architecture

Codex CLI (codex-rs) defines tools in `core/src/tools/spec.rs` using `ToolSpec::Function` with typed JSON schemas. Each tool has a separate handler in `core/src/tools/handlers/`.

### Tool Definition Pattern (Codex)

```rust
// From codex-rs/core/src/tools/spec.rs
fn create_read_file_tool() -> ToolSpec {
    let properties = BTreeMap::from([
        ("file_path".to_string(), JsonSchema::String {
            description: Some("Absolute path to the file".to_string()),
        }),
        ("offset".to_string(), JsonSchema::Number {
            description: Some("The line number to start reading from. Must be 1 or greater.".to_string()),
        }),
        ("limit".to_string(), JsonSchema::Number {
            description: Some("The maximum number of lines to return.".to_string()),
        }),
        ("mode".to_string(), JsonSchema::String {
            description: Some(
                "Optional mode selector: \"slice\" for simple ranges (default) or \
                 \"indentation\" to expand around an anchor line.".to_string(),
            ),
        }),
    ]);

    ToolSpec::Function(ResponsesApiTool {
        name: "read_file".to_string(),
        description:
            "Reads a local file with 1-indexed line numbers, supporting slice and \
             indentation-aware block modes.".to_string(),
        strict: false,
        parameters: JsonSchema::Object {
            properties,
            required: Some(vec!["file_path".to_string()]),
            additional_properties: Some(false.into()),
        },
        output_schema: None,
    })
}
```

Key observations:
- `strict: false` -- allows optional parameters without listing all in `required`
- `additional_properties: Some(false.into())` -- prevents LLM from inventing fields
- `output_schema: None` -- most tools don't define output schema (only `exec_command` does)
- Description is one sentence -- action + key feature

### Shell Tool (Codex)

```rust
// From codex-rs/core/src/tools/handlers/shell.rs
pub struct ShellHandler;
pub struct ShellCommandHandler {
    backend: ShellCommandBackend,  // Classic or ZshFork
}

// Shell tool description (Linux/macOS)
"Runs a shell command and returns its output.
 Always set the `workdir` param when using the shell_command function.
 Do not use `cd` unless absolutely necessary."
```

The shell handler is the most complex tool -- it manages subprocess execution, output streaming, timeout handling, and permission checks. Key lesson: even the most powerful tool has a simple description.

### Freeform Tool Pattern (js_repl)

```rust
// From codex-rs/core/src/tools/spec.rs
ToolSpec::Freeform(FreeformTool {
    name: "js_repl".to_string(),
    description: "Runs JavaScript in a persistent Node kernel with top-level await. \
        This is a freeform tool: send raw JavaScript source text, optionally with \
        a first-line pragma like `// codex-js-repl: timeout_ms=15000`; \
        do not send JSON/quotes/markdown fences.".to_string(),
    format: FreeformToolFormat {
        r#type: "grammar".to_string(),
        syntax: "lark".to_string(),
        definition: JS_REPL_FREEFORM_GRAMMAR.to_string(),
    },
})
```

`js_repl` is the only freeform tool -- it accepts raw JS source text instead of JSON arguments. The grammar validates syntax without requiring JSON wrapping. This is a unique pattern: when the tool input IS code, don't wrap it in JSON.

### Tool Registration (Codex)

```rust
// Codex registers tools with parallel execution support
builder.push_spec_with_parallel_support(create_read_file_tool(), true);
builder.register_handler("read_file", read_file_handler);

builder.push_spec_with_parallel_support(create_grep_files_tool(), true);
builder.register_handler("grep_files", grep_files_handler);
```

Read-only tools are marked as parallel-safe. The framework can execute multiple parallel tool calls in one step.

---

## Claude Code Deferred Tools (from HitCC)

### ToolSearch Mechanism

From HitCC reverse-engineering (Chinese), the deferred tool system works:

```text
Model sees deferred tool names (no schema)
  -> Calls ToolSearch(query)
  -> tool_result contains tool_reference(tool_name)
  -> Next request build extracts discovered tool names from history
  -> Only matched deferred tools added to tools array with full schema
  -> Next turn can call the tool
```

Query forms supported:
- `"select:Read,Edit,Grep"` -- fetch exact tools by name
- `"notebook jupyter"` -- keyword search
- `"+slack send"` -- require "slack" in name, rank by remaining terms

### Tool Execution Pipeline (Claude Code)

```text
tool_use block
  -> he6(...)           # find tool definition
    -> Ho_(...)         # validate
      -> Mo_(...)       # execute
        -> PreToolUse hooks     # permission/approval
        -> permission merge     # sandbox checks
        -> tool.call(...)       # actual execution
        -> PostToolUse hooks    # post-processing
        -> tool_result / attachments / contextModifier
```

Key insight: hooks run BEFORE and AFTER every tool call. This is the same pattern as our HookRegistry, but at the framework level.

---

## PAC1 Agent Tool Patterns

### Trust Metadata

```rust
// From agent-bit/src/tools.rs
fn infer_trust(path: &str) -> &'static str {
    let normalized = path.trim_start_matches('/');
    let parts: Vec<&str> = normalized.split('/').collect();
    if parts.len() == 1 {
        let lower = parts[0].to_lowercase();
        if lower == "agents.md" || lower == "readme.md" {
            return "trusted";
        }
    }
    "untrusted"
}

fn wrap_with_meta(path: &str, content: &str) -> String {
    format!("[{} | {}]\n{}", path, infer_trust(path), content)
}
```

### Post-Read Security Guard

```rust
pub(crate) fn guard_content(content: String) -> String {
    let score = crate::scanner::threat_score(&content);
    if score >= 6 {
        format!(
            "{}\n\n[!] SECURITY NOTE (threat_score={}): \
             injection-like patterns detected. \
             Check [CLASSIFICATION] annotation above.",
            content, score
        )
    } else {
        content
    }
}
```

### Batch Tool: read_all

```rust
// From agent-bit/src/tools.rs
impl Tool for ReadAllTool {
    fn name(&self) -> &str { "read_all" }
    fn description(&self) -> &str {
        "Read ALL files in a directory in one call. \
         Much faster than listing then reading one by one. \
         Returns each file with its path header."
    }

    async fn execute_readonly(&self, args: Value, _ctx: &AgentContext)
        -> Result<ToolOutput, ToolError>
    {
        let listing = self.pcm.list(&a.path).await?;
        let mut output = String::new();
        for name in listing.lines().skip(1) {
            if name.ends_with('/') { continue; }
            let content = self.pcm.read(&full_path, false, 0, 0).await?;
            let trust = infer_trust(&full_path);
            output.push_str(&format!("\n--- {} [{}] ---\n{}", full_path, trust, content));
        }
        Ok(ToolOutput::text(output))
    }
}
```

### Search Auto-Expand

```rust
async fn auto_expand_search(pcm: &PcmClient, search_output: String) -> String {
    let files = unique_files_from_search(&search_output, 10);
    if files.is_empty() || files.len() > 10 {
        return search_output; // Too many -- let model pick
    }
    let mut expanded = search_output;
    for path in &files {
        if let Ok(content) = pcm.read(path, false, 0, 0).await {
            let trust = infer_trust(path);
            let capped: String = content.lines().take(200).collect::<Vec<_>>().join("\n");
            expanded.push_str(&format!("\n\n--- {} [{}] ---\n{}", path, trust, capped));
        }
    }
    expanded
}
```

### Eval Tool with File Glob

```rust
#[derive(Deserialize, JsonSchema)]
struct EvalArgs {
    /// JavaScript code. Last expression = output.
    /// Globals: file_0..file_N, file_paths[], workspace_date
    code: String,
    /// File paths to pre-read. Supports glob: "projects/*/README.MD"
    #[serde(default)]
    files: Vec<String>,
}
```

### Tool Filtering by Task Type (Router)

```rust
fn filter_tools_for_task(task_type: &str, step: u32, all_defs: Vec<ToolDef>) -> Vec<ToolDef> {
    match task_type {
        "security" => all_defs.into_iter()
            .filter(|t| matches!(t.name.as_str(),
                "read" | "read_all" | "search" | "search_and_read"
                | "grep_count" | "eval" | "find" | "list" | "answer"
            )).collect(),

        "delete" => all_defs.into_iter()
            .filter(|t| matches!(t.name.as_str(),
                "search" | "search_and_read" | "read" | "read_all"
                | "find" | "list" | "delete" | "answer"
            )).collect(),

        "analyze" if step == 0 => all_defs.into_iter()
            .filter(|t| matches!(t.name.as_str(),
                "read" | "read_all" | "search" | "find" | "list"
                | "tree" | "context" | "answer"
            )).collect(),

        _ => all_defs,
    }
}
```

### Hook Registry

```rust
pub struct Hook {
    pub tool: String,
    pub path_contains: String,
    pub exclude: Vec<String>,
    pub message: String,
}

pub struct HookRegistry {
    hooks: Vec<Hook>,
}

impl HookRegistry {
    pub fn check(&self, tool_name: &str, path: &str) -> Vec<String> {
        self.hooks.iter()
            .filter(|h| h.tool == tool_name)
            .filter(|h| path.to_lowercase().contains(&h.path_contains))
            .filter(|h| !h.exclude.iter().any(|ex| path.to_lowercase().contains(ex)))
            .map(|h| h.message.clone())
            .collect()
    }
}
```

### Parsing Hooks from Workspace Rules

```rust
pub fn from_agents_md(content: &str) -> HookRegistry {
    let mut registry = HookRegistry::new();
    for line in content.lines() {
        let ll = line.to_lowercase();

        // "when adding/writing to {path}, also {action}"
        if (ll.contains("when adding") || ll.contains("when writing"))
            && ll.contains("also")
        {
            if let Some(source_path) = extract_path_ref(line) {
                if let Some(action) = line.to_lowercase().split("also").nth(1) {
                    registry.add(Hook {
                        tool: "write".into(),
                        path_contains: source_path.to_lowercase(),
                        exclude: vec!["template".into()],
                        message: format!("NEXT: {}", action.trim()),
                    });
                }
            }
        }

        // "keep files in {path} immutable"
        if ll.contains("immutable") || ll.contains("do not modify") {
            if let Some(path) = extract_path_ref(line) {
                registry.add(Hook {
                    tool: "write".into(),
                    path_contains: path.to_lowercase(),
                    exclude: vec![],
                    message: format!("[!] Files in {} are immutable.", path),
                });
            }
        }
    }
    registry
}
```

### Hook Delivery in Tool Output

```rust
// In WriteTool::execute()
let mut output = format!("Written to {}", a.path);
let hook_messages = self.hooks.lock().unwrap().check("write", &a.path);
for msg in hook_messages {
    output.push_str(&format!("\n\n{}", msg));
}
Ok(ToolOutput::text(output))
```

---

## Tool Description Examples (all from real code)

| Agent | Tool | Description |
|-------|------|-------------|
| Codex | `read_file` | "Reads a local file with 1-indexed line numbers, supporting slice and indentation-aware block modes." |
| Codex | `shell_command` | "Runs a shell command and returns its output. Always set the `workdir` param." |
| Codex | `exec_command` | "Runs a command in a PTY, returning output or a session ID for ongoing interaction." |
| Codex | `list_dir` | "Lists entries in a local directory with 1-indexed entry numbers and simple type labels." |
| Codex | `js_repl` | "Runs JavaScript in a persistent Node kernel with top-level await. This is a freeform tool..." |
| Codex | `view_image` | "View a local image from the filesystem (only use if given a full filepath by the user...)" |
| PAC1 | `read` | "Read file contents. Use number=true to see line numbers (like cat -n)..." |
| PAC1 | `search` | "Search file contents with regex pattern. Smart search: auto-retries with name variants..." |
| PAC1 | `grep_count` | "Count lines matching a regex pattern in a file. Returns exact count as a number." |
| PAC1 | `delete` | "Delete one or more files. Pass `path` for single, or `paths` (array) for batch." |

### Unit Test Examples

```rust
#[cfg(test)]
mod tests {
    // Argument parsing edge cases
    #[test]
    fn test_parse_args_missing_optional() {
        let args = json!({"path": "/foo"});
        let parsed: ReadArgs = parse_args(&args).unwrap();
        assert_eq!(parsed.number, false);
        assert_eq!(parsed.start_line, 0);
    }

    // JSON auto-repair
    #[test]
    fn test_json_repair_trailing_comma() {
        let broken = r#"{"name": "John", "age": 30,}"#;
        let fixed = llm_json::repair_json(broken, &Default::default()).unwrap();
        let _: serde_json::Value = serde_json::from_str(&fixed).unwrap();
    }

    // Trust metadata
    #[test]
    fn test_trust_root_agents_md() {
        assert_eq!(infer_trust("AGENTS.MD"), "trusted");
        assert_eq!(infer_trust("contacts/agents.md"), "untrusted");
        assert_eq!(infer_trust("/docs/readme.md"), "untrusted");
    }

    // Tool filtering by task type
    #[test]
    fn test_delete_task_has_no_write() {
        let all_defs = make_all_tool_defs();
        let filtered = filter_tools_for_task("delete", 0, all_defs);
        assert!(filtered.iter().all(|t| t.name != "write"));
        assert!(filtered.iter().any(|t| t.name == "delete"));
    }

    // Eval sandbox safety
    #[test]
    fn test_eval_no_require() {
        let result = run_eval("require('fs').readFileSync('/etc/passwd')", vec![]);
        assert!(result.contains("error"));
    }
}
```

---

## Codex RS Deep Patterns (from codex-rs source)

### Parallel Tool Execution
```rust
// codex-rs/core/src/tools/parallel.rs
// Read-only tools run concurrently, mutating tools run exclusively
pub struct ToolCallRuntime {
    router: Arc<ToolRouter>,
    parallel_execution: Arc<RwLock<()>>,  // coordination lock
}

// Per-tool flag:
builder.push_spec_with_parallel_support(create_read_file_tool(), true);  // concurrent
builder.push_spec_with_parallel_support(create_shell_tool(), false);     // exclusive
```

### Indentation-Aware File Reading
```rust
// codex-rs/core/src/tools/handlers/read_file.rs (836 lines)
struct IndentationArgs {
    anchor_line: Option<usize>,   // start from this line
    max_levels: usize,            // depth limit (0=unlimited)
    include_siblings: bool,       // same-level blocks
    include_header: bool,         // comments above anchor
    max_lines: Option<usize>,     // hard cap
}
// Smart: reads code block at anchor, follows indentation structure
// Much better than raw offset/limit for code files
```

### Sandbox Retry Escalation
```rust
// codex-rs/core/src/tools/sandboxing.rs
trait Sandboxable {
    fn sandbox_preference(&self) -> SandboxablePreference;  // Auto|Always|Never
    fn escalate_on_failure(&self) -> bool;  // retry without sandbox
}
// Flow: sandbox → fail → prompt user → retry without sandbox (cached approval)
```

### JS REPL via Node.js Subprocess (NOT embedded engine)
```rust
// codex-rs/core/src/tools/js_repl/mod.rs (3918 lines!)
// - Spawns Node.js with --experimental-vm-modules
// - JSON line protocol (stdin/stdout)
// - VM context isolation per execution
// - Previous module namespace imported into new cells (REPL semantics)
// - Nested tool calls: JS can call back into Codex tools via async RPC
// - Embeds meriyah parser for static binding analysis
```

### Apply Patch (Diff-Based Edit) — saves tokens
```rust
// codex-rs/core/src/tools/handlers/apply_patch.rs
// Instead of rewriting full file (500 lines → 500 tokens):
// Send diff (2 lines → 50 tokens)
// Lark grammar parser for custom diff format
// Fallback to shell: git apply
```

### FileBackend Trait Pattern
```rust
// Recommended for reusable tools:
pub trait FileBackend: Send + Sync {
    async fn read(&self, path: &str) -> Result<String>;
    async fn write(&self, path: &str, content: &str) -> Result<()>;
    async fn search(&self, root: &str, pattern: &str) -> Result<String>;
    async fn list(&self, path: &str) -> Result<String>;
}

// Then tools are generic:
pub struct ReadTool<B: FileBackend>(pub Arc<B>);
pub struct SearchTool<B: FileBackend>(pub Arc<B>);

// Each project provides backend:
// agent-bit: FileBackend for PcmClient (BitGN API)
// rc-cli: FileBackend for LocalFs (std::fs)
```
