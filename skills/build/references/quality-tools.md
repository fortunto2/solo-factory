# Platform-Specific Quality Tools

Run these checks after each task implementation, before `git commit`. If any fail, fix before proceeding.

## Python Stack

Detected by `pyproject.toml` or stack YAML. Full Astral toolchain:

1. **Ruff** — linting + formatting (always):
   ```bash
   uv run ruff check --fix .
   uv run ruff format .
   ```

2. **ty** — type-checking (if `ty` in dev dependencies or stack YAML):
   ```bash
   uv run ty check .
   ```
   ty is Astral's type-checker (extremely fast, replaces mypy/pyright). Fix type errors before committing.

3. **Hypothesis** — property-based testing (if `hypothesis` in dependencies):
   - Use `@given(st.from_type(MyModel))` to auto-generate Pydantic model inputs.
   - Use `@given(st.text(), st.integers())` for edge-case coverage on parsers/validators.
   - Hypothesis tests go in the same test files alongside regular pytest tests.

4. **Pre-commit** — run all hooks before committing:
   ```bash
   uv run pre-commit run --all-files
   ```

## JS/TS Stack

Detected by `package.json` or stack YAML:

1. **ESLint** — linting (always):
   ```bash
   pnpm lint --fix
   ```

2. **Prettier** — formatting (always):
   ```bash
   pnpm format
   ```

3. **tsc --noEmit** — type-checking (strict mode):
   ```bash
   pnpm tsc --noEmit
   ```
   Fix type errors before committing. Strict mode should be on in tsconfig.json.

4. **Knip** — dead code detection (if in devDependencies, run periodically):
   ```bash
   pnpm knip
   ```
   Finds unused files, exports, and dependencies. Run after significant refactors.

5. **Pre-commit** — husky + lint-staged runs ESLint + Prettier + tsc on staged files.

## iOS Stack (Swift)

```bash
swiftlint lint --strict
swift-format format --in-place --recursive Sources/
```

## Android Stack (Kotlin)

```bash
./gradlew detekt
./gradlew ktlintCheck
```

Both mobile stacks use **lefthook** for pre-commit hooks (language-agnostic, no Node.js required).
