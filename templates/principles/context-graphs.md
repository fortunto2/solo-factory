# Context Graphs — Agent Trajectories and Organizational Memory

Synthesis of Foundation Capital's (Ashu Garg) context graphs concept — an infrastructure layer that turns agent traces into a compounding asset.

---

## Definition

**Context Graph** — a graph that captures AI agent decision-making trajectories: not just *what* the agent did, but *how* and *why*. A system of records for decisions, not just data.

> "A system of record for decisions, not just data." — Dharmesh Shah (HubSpot)

> "We've entered the era of context, where organizational knowledge becomes the competitive differentiator." — Aaron Levie (Box)

---

## Key Concepts

### Agent Trajectories

When an agent performs a task, it traverses the organization's state space — touches systems, reads data, calls APIs. This trajectory is a **decision trace**.

Each trajectory captures:
- Reasoning steps and intermediate decisions
- Tool selections and API calls
- Error recovery and backtracking
- Context state at each decision point

As trajectories accumulate, an **organizational world model** emerges.

### Decision Traces

Difference between "traces" in observability and "decision traces":
- **Observability trace** = what happened (latency, errors, spans)
- **Decision trace** = why it happened (reasoning, alternatives, context)

Agents sit on a unique set of trajectories representing real decision-making in organizations — something otherwise impossible to even observe.

### Half-life of Decisions

Decisions have an expiry date:
- Policies change, teams change
- Agents need to know which precedents are **still relevant**, not just which precedents **exist**
- Need a mechanism for decay and re-evaluation

---

## Connection to Process Mining

Context graphs advance Process Mining ideas (Celonis, UiPath) to a new level:

| Process Mining | Context Graphs |
|---------------|----------------|
| Business process mapping | Decision mapping |
| System logs (SAP, Salesforce) | Agent trajectories |
| Flow optimization | Training agents on precedents |
| Static maps | Living, updatable graphs |
| Human processes | Human + agent hybrid |

---

## Practical Cycle: Capture -> Retrieve -> Apply

Not a formal standard, but a working pattern for using decision traces:

1. **Capture** — record agent decisions into a graph (what + why)
2. **Retrieve** — before new task, search for similar precedents
3. **Apply** — adapt found patterns to current situation

This creates a flywheel: each successful action improves future ones -> compound learning.

**Note:** "Context graphs" is Foundation Capital's VC thesis term, not a technical standard. The idea is useful, not the branding.

---

## Ontology Debates

Three approaches to structuring context graphs:

### Emergent Ontology (PlayerZero / Animesh)
- Don't prescribe structure upfront
- Let agents **discover** the ontology through usage
- Decision traces compile into organizational world models
- Ontology is **found**, not **declared**

### Prescriptive Ontology (Palantir)
Three layers:
1. **Semantic layer** — objects and relationships
2. **Kinetic layer** — actions and flows
3. **Dynamic layer** — simulations and decision logic

### Hybrid (Graphlit et al.)
- Core entities (Person, Organization, Account, Event) — stable, no need to discover
- Domain relationships and decision patterns — let agents discover
- Pragmatic balance: don't wait for agent to "discover" the obvious

---

## Trillion-Dollar Thesis

Economic value of context graphs:

1. **Reduced compute waste** — reuse proven decision paths
2. **Accelerated onboarding** — new agents bootstrapped from accumulated knowledge
3. **Compound learning** — every action improves future ones
4. **Enterprise memory** — organization retains agent expertise
5. **Network effects** — value grows exponentially with graph enrichment

> Whoever first captures decision traces in a high-value domain creates a compounding asset and moat.

---

## Practical Implementation

### For Small Projects and Assistants

Context graphs don't require enterprise scale. Applicable to:

1. **Session history** (already implemented in solograph)
   - `session_search` — search past Claude Code sessions
   - Each session = decision trajectory

2. **CodeGraph** (already implemented)
   - `codegraph_query` — Cypher queries on code graph
   - `codegraph_explain` — architectural overview
   - `codegraph_shared` — shared packages across projects
   - Structural memory about code

3. **Knowledge Base** (already implemented)
   - `kb_search` — semantic search
   - Decisions, patterns, precedents

4. **Source Graph** (already implemented)
   - `source_search` — Telegram, YouTube
   - `source_related` — related videos by tags
   - External knowledge sources in graph

### What to Strengthen

- **Decision logging** — capture in KB not just results, but **why** a decision was made
- **Agent trajectory export** — export trajectories from session_search in structured format
- **Pattern mining** — find recurring decision patterns across sessions
- **Precedent retrieval** — before new task, auto-search for similar past solutions
- **Decay mechanism** — mark stale decisions (half-life)

---

## Connection to Harness Engineering

Context graphs and harness engineering are complementary:

| Harness Engineering | Context Graphs |
|-------------------|----------------|
| Prevents mistakes | Learns from decisions |
| Guardrails and linters | Decision traces and precedents |
| Encodes "how not to" | Encodes "how to do it right" |
| Static rules | Living, growing graph |
| Per-repository | Cross-organization |

**Together:** harness constrains the agent, context graph helps choose the best path within constraints.

---

## Evaluation via Context Graphs

Assessing agents through decision traces:
- Did the agent traverse the expected graph edges?
- Are the constraints adequate?
- Do similar contexts produce consistent trajectories?
- Is decision quality degrading over time?

---

## Industry and Adoption

- **Dharmesh Shah** (HubSpot): "system of record for decisions"
- **Aaron Levie** (Box): "era of context"
- **Arvind Jain** (Glean): "the concept finally has a name"
- **Cognition** (Devin): integrated into product
- **Fortune 500 CIOs**: requesting roadmap
- **OpenAI + Anthropic**: employees sharing as required reading

---

*Sources:*
- *[Foundation Capital — Context Graphs: AI's Trillion-Dollar Opportunity](https://foundationcapital.com/context-graphs-ais-trillion-dollar-opportunity/) (Ashu Garg)*
- *[Foundation Capital — Context Graphs, One Month In](https://foundationcapital.com/context-graphs-one-month-in/) (Jan 2026)*
- *[Foundation Capital — Why Context Graphs Are the Missing Layer](https://foundationcapital.com/why-are-context-graphs-are-the-missing-layer-for-ai/)*
- *[Graphlit — Context Graphs: What the Ontology Debate Gets Wrong](https://www.graphlit.com/blog/what-the-ontology-debate-gets-wrong)*
