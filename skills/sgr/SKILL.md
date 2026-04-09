---
name: solo-sgr
description: Use when "design schemas", "structured output", "agent loop", "SGR", "constrained decoding", "tool dispatch", "Pydantic schema for LLM", or need to design a schema-guided reasoning pipeline for an agent or API. Do NOT use for general code review (/review) or planning (/plan).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
argument-hint: "<task description or 'audit' to review existing schemas>"
---

# /sgr

Design and implement Schema-Guided Reasoning (SGR) pipelines. Translate domain expert mental checklists into structured reasoning schemas for LLMs.

**Source:** [Rinat Abdullin — Schema-Guided Reasoning](https://abdullin.com/schema-guided-reasoning/)

## Core Principle

SGR = guide LLM reasoning through predefined steps via constrained decoding. Instead of free-form text → enforce a schema that defines what steps, in which order, where to focus attention.

```
Domain expert mental checklist → Pydantic/Zod schema → Constrained decoding → Deterministic dispatch
```

## When to Use

- Designing agent tool dispatch (NextStep pattern)
- Building structured analysis pipelines (compliance, code review, evaluation)
- Replacing prompt chains with single structured call
- Any place where LLM output must be parseable and actionable

## Steps

1. **Parse task** from `$ARGUMENTS`:
   - If "audit": scan project for existing Pydantic/Zod schemas, evaluate against SGR patterns
   - If task description: design SGR pipeline from scratch
   - If empty: ask "What domain/task should the SGR pipeline handle?"

2. **Identify the reasoning cascade** — interview the domain:
   - What decisions does a human expert make? In what order?
   - What information does each step need from previous steps?
   - Where does the expert need to "look before deciding"?
   - What are the possible actions at the end?

   This is the critical step. SGR quality = how well you translate the expert's mental checklist.

3. **Design the schema** following SGR patterns:

   ### The NextStep Pattern (agent loop)
   ```python
   class NextStep(BaseModel):
       current_state: str                    # thinking space
       plan_remaining_steps: list[str]       # 1-5 steps, only first used
       task_completed: bool                  # routing gate
       function: Union[Tool1, Tool2, ..., ReportCompletion] = Field(
           ..., description="execute first remaining step"
       )
   ```

   ### The Analysis Cascade Pattern (single-shot)
   ```python
   class Analysis(BaseModel):
       preliminary: str                      # initial assessment
       classification: Literal["a", "b", "c"]  # force categorization
       evidence: list[str]                   # cite sources
       gaps: list[GapItem]                   # structured findings
       verdict: Literal["pass", "partial", "fail"]  # final decision
       reasoning_for_verdict: str            # explain after deciding
   ```

   ### The Tool Dispatch Pattern
   ```python
   class SendEmail(BaseModel):
       tool: Literal["send_email"]           # discriminator
       recipient: str
       subject: str
       body: str

   class SearchDB(BaseModel):
       tool: Literal["search_db"]
       query: str

   # Union with Literal discriminator = deterministic routing
   Action = Union[SendEmail, SearchDB, ReportDone]
   ```

4. **Apply SGR design rules** (from `references/sgr-rules.md`):

   - **Cascade order matters** — put analysis before decision, evidence before verdict
   - **Constrain enums** — `Literal["pass", "fail"]` not `str`
   - **Limit lists** — `Annotated[list[str], MinLen(1), MaxLen(5)]`
   - **Discriminated unions** — `tool: Literal["name"]` for routing
   - **Verification after decision** — add `reasoning_for_X` AFTER the enum field, not before
   - **One schema per reasoning path** — don't mix analysis and action in one model
   - **Discount > 50% guard** — `Annotated[int, Le(50)]` — bake constraints into types

5. **Implement the dispatch loop** (if agent):

   ```python
   for i in range(MAX_STEPS):
       response = client.beta.chat.completions.parse(
           model=MODEL,
           response_format=NextStep,
           messages=log,
       )
       job = response.choices[0].message.parsed

       if isinstance(job.function, ReportCompletion):
           break  # done

       result = dispatch(job.function)  # deterministic routing
       log.append(assistant_message(job))
       log.append(tool_result(result))
   ```

6. **Add to project**:
   - Schemas in `schemas/` or `models/` directory
   - Dispatch in `dispatch.py` or equivalent
   - Tests: validate schema parsing, test each tool independently
   - Document the reasoning cascade in a comment or docstring

7. **Audit mode** (if `$ARGUMENTS` = "audit"):
   - Find all Pydantic BaseModel / Zod z.object in project
   - Check: do schemas follow cascade order? Are enums constrained? Are unions discriminated?
   - Report: which schemas are SGR-compliant, which need fixes

## Output

```
## SGR Pipeline: {domain}

**Pattern:** {NextStep | Analysis Cascade | Tool Dispatch}
**Schemas:** {N} models
**Tools:** {N} (if agent loop)

### Reasoning Cascade
{step 1} → {step 2} → ... → {decision/action}

### Files
- schemas/{name}.py — {N} models
- dispatch.py — tool routing
- tests/test_{name}.py — validation tests
```

## Key References

- `references/sgr-rules.md` — design rules and anti-patterns
- `references/sgr-demo.py` — complete working example (Abdullin's CRM demo, 304 lines Python)
- `references/sgr-patterns.md` — cascade patterns for 6 domains
- `references/sgr-full-guide.md` — full SGR guide with theory, code, tool calling internals

## Libraries & Implementations

### Rust
- **sgr-agent** (crate, v0.6.1) — SGR LLM client + agent framework: structured output, function calling, agent loop, 3 agent variants. Core crate for all Rust SGR agents. Part of [rust-code](https://github.com/fortunto2/rust-code)
- [openai-oxide](https://github.com/fortunto2/openai-oxide) — typed Rust client for OpenAI API (SGR at compile time via strong types)

In Rust, SGR is even stronger: `#[serde(tag = "tool")]` gives discriminated union dispatch at zero runtime cost. Enum variants = tools, serde deserialization = constrained decoding.

### Python
- [sgr-agent-core](https://github.com/vamplabAI/sgr-agent-core) (1K+ stars) — SGR agentic system design framework by neuraldeep community. Reference Python implementation
- Abdullin's demo in `references/sgr-demo.py` — minimal standalone example (304 lines, CRM agent)

## Common Issues

### Schema too flat
**Cause:** Tried to put everything in one model.
**Fix:** Split into analysis model + action model. Cascade, don't flatten.

### LLM ignores enum constraints
**Cause:** Model not supporting constrained decoding, or wrong API.
**Fix:** Use `response_format=Schema` (OpenAI), `tools` with schema (Anthropic). Check `references/sgr-rules.md` for provider-specific notes.

### Agent loops forever
**Cause:** No `task_completed` gate or `ReportCompletion` tool.
**Fix:** Always include a completion signal in the Union. Cap loop iterations.
