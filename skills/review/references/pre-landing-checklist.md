# Pre-Landing Review Checklist

Adapted from gstack (https://github.com/garrytan/gstack). Two-pass review: critical issues block shipping, informational issues go in PR body.

## Two-Pass Structure

```
CRITICAL (blocks ship):              INFORMATIONAL (in PR body):
+- SQL & Data Safety                 +- Conditional Side Effects
+- Race Conditions & Concurrency     +- Magic Numbers & String Coupling
+- LLM Output Trust Boundary         +- Dead Code & Consistency
                                     +- LLM Prompt Issues
                                     +- Test Gaps
                                     +- Crypto & Entropy
                                     +- Time Window Safety
                                     +- Type Coercion at Boundaries
                                     +- View/Frontend
```

## Pass 1 — CRITICAL

### SQL & Data Safety
- String interpolation in SQL (even if values are coerced — use parameterized queries)
- TOCTOU races: check-then-set patterns that should be atomic WHERE + UPDATE
- Bypassing validations on fields that have or should have constraints
- N+1 queries: missing includes/preload for associations used in loops/views

### Race Conditions & Concurrency
- Read-check-write without uniqueness constraint or retry on conflict
- `find_or_create` on columns without unique DB index — concurrent calls create duplicates
- Status transitions without atomic WHERE old_status = ? UPDATE SET new_status
- Unsanitized user-controlled data in HTML output (XSS)

### LLM Output Trust Boundary
- LLM-generated values (emails, URLs, names) written to DB without format validation
- Structured tool output accepted without type/shape checks before database writes
- Add lightweight guards (regex, URL parse, strip) before persisting AI-generated content

## Pass 2 — INFORMATIONAL

### Conditional Side Effects
- Code paths that branch on condition but forget side effect on one branch
- Log messages claiming action happened when it was conditionally skipped

### Magic Numbers & String Coupling
- Bare numeric literals in multiple files — should be named constants
- Error message strings used as query filters elsewhere

### Dead Code & Consistency
- Variables assigned but never read
- Version mismatch between PR title and VERSION/CHANGELOG files
- Comments describing old behavior after code changed

### LLM Prompt Issues
- 0-indexed lists in prompts (LLMs return 1-indexed)
- Prompt text listing capabilities that don't match what's wired up
- Word/token limits stated in multiple places that could drift

### Test Gaps
- Negative-path tests that assert type/status but not side effects
- Assertions on string content without checking format
- Security enforcement features without integration tests

### Crypto & Entropy
- Truncation instead of hashing (less entropy, easier collisions)
- `rand()` / `Math.random()` for security-sensitive values — use crypto-secure RNG
- Non-constant-time comparisons on secrets (timing attack)

### Time Window Safety
- Date-key lookups assuming "today" covers 24h (report at 8am only sees midnight->8am)
- Mismatched time windows between related features

### Type Coercion at Boundaries
- Values crossing language/serialization boundaries where type could change
- Hash inputs that don't normalize types before serialization

### View/Frontend
- Inline style blocks in partials (re-parsed every render)
- O(n*m) lookups in views (array.find in loop instead of index/map)
- Client-side filtering that could be a WHERE clause

## Suppressions — DO NOT Flag

- Harmless redundancy that aids readability
- "Add comment explaining why this constant was chosen" — thresholds change, comments rot
- "Assertion could be tighter" when assertion already covers behavior
- Consistency-only changes (adding guard to match another constant's pattern)
- Eval threshold tuning changes
- Harmless no-ops
- Anything already addressed in the diff being reviewed
