# Context Graph Principles

Principles for capturing and reusing agent decision traces. Applicable at any scale — from solo projects to enterprises.

Source: Foundation Capital (Ashu Garg), "Context Graphs" thesis.

---

## Core Idea

Every agent action = decision trace (trajectory). Accumulated traces form organizational world model. Whoever captures decision traces first in a domain gets compounding moat.

## Practical Cycle: Capture → Retrieve → Apply

1. **Capture** — record agent decisions into a graph (what + why)
2. **Retrieve** — search for relevant precedents before new tasks
3. **Apply** — adapt found patterns to current situation

Each successful execution improves future ones → compound learning flywheel.

Note: "Context graphs" is Foundation Capital's VC thesis term, not a technical standard. The idea is useful, the branding is not.

## Practical Implementation

### What to capture

- Agent reasoning steps and intermediate decisions
- Tool selections and API calls
- Error recovery and backtracking paths
- Context state at each decision point
- **Why** (rationale), not just **what** (action)

### Storage patterns

- Graph database for decisions and transitions (FalkorDB, Neo4j)
- Semantic indexing for retrieval (vector search)
- Session history as raw trajectory source
- Code graph as structural context

### Already implemented (solograph)

- `session_search` — search past Claude Code sessions (raw trajectories)
- `codegraph_query` — structural code knowledge graph
- `kb_search` — semantic search over methodology and decisions
- `source_search` — external knowledge sources in graph

### What to add

- **Decision logging** — capture "why" alongside "what" in KB entries
- **Precedent retrieval** — before new task, auto-search for similar past solutions
- **Pattern mining** — find recurring decision patterns across sessions
- **Decay mechanism** — mark decisions with half-life, flag stale precedents

## Ontology Approaches

| Approach | When to use |
|----------|-------------|
| **Emergent** (let agents discover) | Domain-specific patterns, workflows |
| **Prescriptive** (define upfront) | Core entities (User, Project, File) |
| **Hybrid** (recommended) | Stable core + emergent edges |

## Connection to Harness Engineering

Harness constrains what agent CAN do. Context graph guides what agent SHOULD do.

- Harness = guardrails and linters (prevents mistakes)
- Context graph = precedents and patterns (enables better choices)
- Together: agent stays within boundaries AND picks optimal path
