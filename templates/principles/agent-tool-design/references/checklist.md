# Tool System Design Checklist

Quick reference for designing or reviewing an agent tool system. Score each item 0 (missing), 1 (partial), or 2 (done).

---

## Foundation (must-have)

- [ ] **7 core tools max** -- observe (read, search, list), act (write, delete, eval), report (answer)
- [ ] **Descriptions follow WHEN+WHAT+WHY** -- no example outputs in descriptions
- [ ] **No example outputs in descriptions** -- models copy examples verbatim as answers
- [ ] **`additionalProperties: false`** on all tool schemas -- prevent LLM from inventing fields
- [ ] **Required fields minimal** -- only truly mandatory params in `required` array

## Efficiency

- [ ] **Batch tools justified** -- each saves 3+ round-trips, used in >20% of tasks
- [ ] **Search auto-expand** -- search results include file content when matches are few
- [ ] **Tool usage tracking** -- remove tools with <5% usage across benchmark
- [ ] **Deferred loading** for rarely-used tools -- model sees names only, loads schema on demand

## Safety

- [ ] **Trust metadata on reads** -- `[path | trusted/untrusted]` header on all read outputs
- [ ] **Post-read security guard** -- advisory warning for injection patterns
- [ ] **Task-type filtering** -- router restricts tool set based on classifier, not model self-report
- [ ] **Permanent restrictions** for dangerous combos -- `delete` task cannot access `write`
- [ ] **Step-based unlock** for read-then-act -- step 0 read-only, step 1+ full toolkit

## Guidance

- [ ] **Hooks from workspace rules** -- parse AGENTS.MD into HookRegistry, not hardcoded
- [ ] **Hooks in tool output** -- append after normal result, not injected into system prompt
- [ ] **Built-in hooks for universal patterns** -- e.g. "update seq.json after writing to outbox/"

## Testing

- [ ] **Argument parsing unit tests** -- missing optionals, wrong types, edge cases
- [ ] **JSON auto-repair tests** -- trailing commas, unquoted keys, missing brackets
- [ ] **Trust inference tests** -- root vs nested, case sensitivity
- [ ] **Tool filtering tests** -- each task type blocks/allows correct tools
- [ ] **Sandbox safety tests** -- eval cannot access filesystem/network
- [ ] **Weakest model test** -- tool system works on your least capable target model

## Architecture

- [ ] **Tool handler separate from spec** -- definition in one file, implementation in another
- [ ] **Read-only tools marked parallel-safe** -- framework can batch parallel calls
- [ ] **Error messages actionable** -- tell the model what to do next, not just "error"
