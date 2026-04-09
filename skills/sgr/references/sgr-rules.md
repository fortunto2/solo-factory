# SGR Design Rules

Source: [Rinat Abdullin](https://abdullin.com/schema-guided-reasoning/) + practical experience.

## Core Rules

1. **Cascade order = reasoning order.** Fields are generated top-to-bottom. Put analysis before decision, evidence before verdict. The model "thinks" in the order you define.

2. **Constrain everything possible.** `Literal["pass", "fail"]` not `str`. `Annotated[int, Le(50)]` not `int`. `MinLen(1), MaxLen(5)` not unbounded list. Tighter constraints = fewer hallucinations.

3. **Discriminated unions for routing.** Every tool gets `tool: Literal["tool_name"]`. Pydantic uses it as discriminator → deterministic dispatch via `isinstance()`.

4. **Verification AFTER decision.** Put `reasoning_for_verdict: str` after `verdict: Literal[...]`, not before. Model commits to the enum first, then explains. Prevents rationalization drift.

5. **One schema per reasoning path.** Don't mix code analysis and mutation planning in one model. Two schemas, two calls. Simpler = more reliable.

6. **Think → Plan → Act in one schema.** NextStep pattern: `current_state` (think) → `plan_remaining_steps` (plan) → `function` (act). First step of plan = the action. Discard remaining steps — they're context, not commitments.

7. **Business rules in types, not prompts.** `discount_percent: Annotated[int, Le(50)]` is a compile-time guarantee. "Never give more than 50% discount" in a prompt is a suggestion.

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|-------------|---------|-----|
| Free-form `action: str` | Unparseable, undispatchable | Use `Union[Tool1, Tool2]` with Literal discriminator |
| Decision before analysis | Model picks answer then post-hoc rationalizes | Reorder: analysis fields first, decision last |
| Unbounded lists | Model generates 50 items, blows context | `MaxLen(N)` on every list |
| Single giant schema | Too many concerns, poor accuracy | Split into pipeline: Schema1 → Schema2 |
| Prompt-only constraints | LLM ignores them under pressure | Move to type annotations |
| No completion signal | Agent loops forever | Add `ReportCompletion` to Union |

## Provider Notes

| Provider | API | Constrained Decoding |
|----------|-----|---------------------|
| OpenAI | `response_format=Schema` via `.parse()` | Full support (json_schema mode) |
| Anthropic | `tools` with input_schema | Via tool use, not native CD |
| Google Gemini | `response_schema` | Supported in 2.0+ |
| Local (vLLM) | `guided_json` | xgrammar / outlines backend |
| Local (llama.cpp) | `grammar` | GBNF grammar |

## Token Efficiency

SGR is cheaper than prompt chains:
- One structured call replaces 3-5 prompt chain steps
- Schema itself adds ~200-500 tokens (vs 1000+ for multi-prompt instructions)
- Constrained decoding generates fewer tokens (no filler text)
- Failed parses = 0 (guaranteed valid JSON)
