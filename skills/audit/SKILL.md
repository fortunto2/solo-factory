---
name: solo-audit
description: Health check knowledge base for broken links, missing frontmatter, tag inconsistencies, and coverage gaps. Use when user says "audit KB", "check frontmatter", "find broken links", "tag cleanup", or "knowledge base quality". Do NOT use for SEO audits (use /seo-audit) or code reviews.
license: MIT
metadata:
  author: fortunto2
  version: "1.3.0"
allowed-tools: Read, Grep, Bash, Glob, mcp__solograph__kb_search
argument-hint: "[optional: focus area like 'tags' or 'frontmatter']"
---

# /audit

Audit the knowledge base for quality issues: missing frontmatter, broken links, tag inconsistencies, orphaned files, and coverage gaps. Works on any markdown-heavy project.

## Steps

1. **Parse focus area** from `$ARGUMENTS` (optional). If provided, focus on that area (e.g., "tags", "frontmatter", "links"). If empty, run full audit.

2. **Find all markdown files:** Use Glob to find all .md files, excluding common non-content directories: `.venv/`, `node_modules/`, `.git/`, `.embeddings/`, `archive/`, `.archive_old/`.

3. **Frontmatter audit:** For each markdown file, read it and check:
   - Has YAML frontmatter (starts with `---` and has closing `---`)
   - Required fields present: `type`, `status`, `title`, `tags`
   - `type` is valid: one of `principle`, `methodology`, `agent`, `opportunity`, `capture`, `research`
   - `status` is valid: one of `active`, `draft`, `validated`, `archived`
   - `tags` is a non-empty list
   Track files missing frontmatter and files with incomplete/invalid frontmatter.

4. **Link check:** Look for broken internal links:
   - If `scripts/check_links.py` exists, run it: `uv run python scripts/check_links.py`
   - Otherwise: Grep for markdown links `\[.*\]\(.*\.md\)` and verify each target exists

5. **Tag consistency audit:** Use Grep to find all `tags:` sections across .md files. Look for:
   - Near-duplicate tags (e.g., "ai" vs "AI" vs "artificial-intelligence")
   - Tags used only once (potential typos)
   - Very common tags that might be too broad
   List all unique tags with counts.

6. **Orphaned files:** Check which files are NOT referenced in any other file's `related:` field. Files that exist but are never cross-referenced may be orphaned.

7. **Opportunity quality:** Find all documents with `type: opportunity` and check:
   - Missing `opportunity_score` field
   - `evidence_sources` = 0 or missing
   - Status still `draft` for more than 30 days

8. **Coverage gaps:** Check each directory for content:
   - Flag any empty or near-empty directories
   - Look for directories with only 1-2 files (may need more content)

9. **Output report:**
   ```
   ## KB Audit Report

   **Date:** [today]

   ### Summary
   - Total .md files: X
   - With frontmatter: X (X%)
   - Without frontmatter: X

   ### Frontmatter Issues
   | File | Issue |
   |------|-------|
   | path | Missing field: type |

   ### Broken Links
   [list of broken references]

   ### Tag Analysis
   - Total unique tags: X
   - Single-use tags: [list]
   - Potential duplicates: [list]

   ### Orphaned Files
   [files not referenced anywhere]

   ### Opportunity Quality
   - Without opportunity_score: [list]
   - Without evidence_sources: [list]

   ### Coverage
   [directory analysis]

   ### Recommendations
   1. [specific action]
   2. [specific action]
   3. [specific action]
   ```

## Common Issues

### No markdown files found
**Cause:** Running in wrong directory or all files excluded.
**Fix:** Ensure you're in the knowledge base root. Check exclude patterns in step 2.

### Too many single-use tags
**Cause:** Inconsistent tagging across documents.
**Fix:** Pick canonical tags from the most-used list. Run audit again after cleanup.

### Frontmatter validation errors
**Cause:** YAML syntax issues (missing quotes, wrong indentation).
**Fix:** Ensure `---` delimiters are present. Use `type:` and `status:` from the allowed values list.
