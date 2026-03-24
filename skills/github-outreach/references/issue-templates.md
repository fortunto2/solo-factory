# GitHub Issue Templates for Outreach

## Principles

- Lead with THEIR problem, not your solution
- Reference specific code/features they use
- Show concrete benefit with numbers
- Include migration snippet (1-3 lines)
- "You might find useful" tone, never "you should switch"
- Always disclose: "I'm the maintainer of X"

## Template 1: Performance Win (streaming/agent loops)

```markdown
Title: Potential performance improvement for {their_feature} with persistent WebSockets

Hi! I noticed {repo_name} uses async-openai for {what_they_do}.

I maintain [openai-oxide](https://github.com/fortunto2/openai-oxide), a Rust OpenAI client
that keeps a single WebSocket connection open across multiple API calls. In benchmarks with
sequential tool calls (similar to your {specific_pattern}), this reduces latency by ~40%
compared to HTTP REST — no TLS handshake overhead after the first request.

If you're interested, the migration is minimal:

```toml
# Cargo.toml
openai-oxide = { version = "0.9", features = ["websocket", "responses"] }
```

```rust
let mut session = client.ws_session().await?;
// reuse session across calls
let response = session.send(request).await?;
```

Happy to help if you'd like to try it. No pressure — just thought it might be relevant
given your use of {streaming/tool_calls/agent_loop}.

Disclosure: I'm the maintainer of openai-oxide.
```

## Template 2: Structured Outputs (type safety)

```markdown
Title: Auto-generated JSON schemas for structured outputs

Hi! Looking at {repo_name}, I see you're building JSON schemas manually for
{their_structured_usage}. You might find `openai-oxide`'s `parse::<T>()` useful —
it auto-generates the schema from your Rust types:

```rust
#[derive(Deserialize, JsonSchema)]
struct YourType { /* fields */ }

let result = client.chat().completions()
    .parse::<YourType>(request).await?;
// result.parsed is Option<YourType>
```

No manual schema construction, no drift between types and schemas.

Docs: https://fortunto2.github.io/openai-oxide/guides/structured-output.html

Disclosure: I maintain openai-oxide. Happy to answer questions.
```

## Template 3: WASM Deployment

```markdown
Title: WASM/Cloudflare Workers support for {repo_name}

Hi! I noticed {repo_name} {uses_wasm_or_edge_context}.

openai-oxide compiles to `wasm32-unknown-unknown` out of the box — streaming, structured
outputs, and retry logic all work in WASM. We have a live Cloudflare Workers demo:
https://cloudflare-worker-dioxus.nameless-sunset-8f24.workers.dev

```toml
openai-oxide = { version = "0.9", default-features = false, features = ["chat", "responses"] }
```

If edge deployment is on your roadmap, this might save you some cfg-gating work.

Disclosure: I maintain openai-oxide.
```

## Template 4: HTTP Optimizations (general)

```markdown
Title: HTTP/2 optimizations for OpenAI API calls

Hi! I saw {repo_name} makes OpenAI API calls via async-openai. You might see
a latency improvement with these HTTP-level optimizations that openai-oxide enables
by default:

- gzip compression (~30% smaller responses)
- TCP_NODELAY (lower latency)
- HTTP/2 keep-alive pings (prevents idle disconnects)
- HTTP/2 adaptive flow control
- Connection pooling (4 per host)

These are standard reqwest builder options — you could also add them to your current
setup. Here's the relevant code if helpful:
https://github.com/fortunto2/openai-oxide/blob/main/src/client.rs#L85

Disclosure: I maintain openai-oxide.
```

## Anti-patterns (never do this)

- "async-openai is slow/bad/outdated" — disrespectful
- "You should switch to X" — pushy
- Generic copy-paste to 50 repos — spam, gets you reported
- Issues on repos with <5 stars — waste of time
- Issues on archived repos — nobody home
- Multiple issues on same repo — harassment
- Not disclosing you're the maintainer — dishonest
