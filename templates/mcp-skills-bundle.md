# MCP + Skills Bundle Template

Pattern 5 from Anthropic guide: "Domain-specific intelligence" — each product ships
with an MCP server for domain tools AND skills for workflow guidance.

## What Gets Generated

When `/scaffold` creates a new project, it generates:

```
.claude/
├── skills/
│   └── dev/
│       └── SKILL.md       # Dev workflow: run, test, build, deploy
└── settings.json           # Project hooks (optional)
```

For products with MCP servers, the scaffold should also generate:

```
.mcp.json                   # MCP server config (project-local)
src/mcp/                    # MCP server source (if applicable)
```

## Skill Template

Every scaffolded project gets a `dev` skill. The skill frontmatter:

```yaml
---
name: <project>-dev
description: Dev workflow for <Project> — run, test, build, deploy.
  Use when working on <Project> features, fixing bugs, or deploying.
  Do NOT use for other projects.
license: MIT
metadata:
  author: <github_org>
  version: "1.0.0"
allowed-tools: Read, Grep, Glob, Bash, Write, Edit
---
```

Body sections (generated from PRD + stack):
- **Stack**: packages, versions, config locations
- **Commands**: `make dev`, `make test`, etc. (from Makefile)
- **Architecture**: directory structure, naming, patterns
- **Testing**: framework, file locations, conventions
- **Common tasks**: add page/screen, API endpoint, model

## MCP Server Pattern (for products with domain tools)

If the product has domain-specific tools (search, data processing, etc.),
scaffold should also generate an MCP server stub:

```
src/mcp/
├── server.py          # FastMCP server (or index.ts for Node)
├── tools/             # Domain tools
│   └── search.py      # Example: product-specific search
└── __init__.py
```

With `.mcp.json`:
```json
{
  "mcpServers": {
    "<project>": {
      "command": "uv",
      "args": ["run", "src/mcp/server.py"],
      "env": {}
    }
  }
}
```

## README Section

Add to generated README.md:

```markdown
## Claude Code Integration

This project includes Claude Code skills and MCP tools for AI-assisted development.

### Skills
- `/dev` — Project workflow: run, test, build, deploy commands

### MCP Tools (if applicable)
Available via `.mcp.json` — auto-loaded when Claude Code opens this project.
```

## When to Generate MCP

Not every project needs an MCP server. Rules:

| Product Type | MCP? | Why |
|-------------|------|-----|
| Web app (SaaS) | No | Standard CRUD, no domain tools needed |
| Data product | Yes | Search, indexing, analysis tools |
| AI product | Yes | Model inference, pipeline tools |
| Developer tool | Yes | Code analysis, transformation tools |
| Content site | No | Standard SSG, no domain tools needed |
| Mobile app | No | MCP runs server-side, mobile is client-side |

The `/scaffold` skill should check the PRD for indicators:
- "search", "index", "analyze" → consider MCP
- "API", "pipeline", "agent" → consider MCP
- Otherwise → skills only (no MCP server)
