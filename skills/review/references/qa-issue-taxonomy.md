# QA Issue Taxonomy

Adapted from gstack (https://github.com/garrytan/gstack). Use for visual/E2E testing dimension.

## Severity Levels

| Severity | Definition | Examples |
|----------|------------|---------|
| **critical** | Blocks core workflow, data loss, crashes | Form submit error page, checkout broken, data deleted without confirmation |
| **high** | Major feature broken, no workaround | Search returns wrong results, upload silently fails, auth redirect loop |
| **medium** | Works but with noticeable problems | Slow load (>5s), validation missing but submit works, layout broken on mobile only |
| **low** | Minor cosmetic or polish | Typo, 1px alignment, inconsistent hover state |

## Categories

### 1. Visual/UI
- Layout breaks (overlapping, clipped text, horizontal scrollbar)
- Broken or missing images
- Incorrect z-index
- Font/color inconsistencies
- Animation glitches
- Dark mode / theme issues

### 2. Functional
- Broken links (404, wrong destination)
- Dead buttons (click does nothing)
- Form validation (missing, wrong, bypassed)
- Incorrect redirects
- State not persisting (lost on refresh, back button)
- Race conditions (double-submit, stale data)

### 3. UX
- Confusing navigation (no breadcrumbs, dead ends)
- Missing loading indicators
- Slow interactions (>500ms with no feedback)
- Unclear error messages
- No confirmation before destructive actions
- Inconsistent interaction patterns

### 4. Content
- Typos and grammar errors
- Placeholder / lorem ipsum left in
- Truncated text without ellipsis
- Wrong labels on buttons or fields
- Missing empty states

### 5. Performance
- Slow page loads (>3 seconds)
- Layout shifts (content jumping after load)
- Excessive network requests (>50 per page)
- Large unoptimized images
- Blocking JavaScript

### 6. Console/Errors
- JavaScript exceptions
- Failed network requests (4xx, 5xx)
- CORS errors
- Mixed content warnings
- CSP violations

### 7. Accessibility
- Missing alt text
- Unlabeled form inputs
- Keyboard navigation broken
- Focus traps
- Missing/incorrect ARIA attributes
- Insufficient color contrast

## Per-Page Exploration Checklist

For each page in a QA session:

1. **Visual scan** — screenshot, check layout, broken images, alignment
2. **Interactive elements** — click every button, link, control
3. **Forms** — submit empty, invalid data, edge cases (long text, special chars)
4. **Navigation** — all paths in/out, breadcrumbs, back button, deep links
5. **States** — empty state, loading state, error state, overflow state
6. **Console** — check for JS errors or failed requests after interactions
7. **Responsiveness** — mobile and tablet viewports
8. **Auth boundaries** — what happens logged out? Different roles?
