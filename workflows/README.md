# Workflows

Saved Claude Code workflows shipped with the plugin. A workflow is a script that fans work out
to subagents in a fixed shape; these three run as `/solo:<name>`. All are read-only: they
return a result, the caller decides what to change.

| Workflow | Use it when | Shape |
|---|---|---|
| `verify-claims` | a number is about to reach a person or a journal | each claim measured again blind, then attacked; `holds` / `rejected` / `unverified` |
| `dream` | memory notes may have drifted from reality | per note: check its claims against the sources, attack every proposed change, then one pass across the set for duplicates and index drift |
| `log-review` | choosing what to fix in a service that logs its calls | health against the previous window, four angles of candidates, each re-measured and dated against fixes already made, ranked by occurrences per week over effort |

None of them names a path, a table or a host. The caller passes where the truth lives
(`sources`, `memory`, `log`, `known`), so the same script works in any project.

Cost, measured: `dream` about 225k tokens a note, `verify-claims` two agents a claim. Run them
where the limit has room, and pass `model` / `effort` when the session's default is too dear.
A scheduled job (`claude -p`) starts one by name in its prompt; the `ultracode` keyword does not
trigger there.
