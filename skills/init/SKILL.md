---
name: solo-init
description: First-time Solo Factory setup — configure org defaults
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
allowed-tools: Read, Bash, Write, AskUserQuestion
argument-hint: ""
---

# /init

First-time setup for Solo Factory. Creates `~/.solo-factory/defaults.yaml` with org-specific values used by `/scaffold` and other skills.

Run once after installing solo-factory. Safe to re-run — shows current values and lets you update them.

## Steps

1. **Check if already configured:**
   - Read `~/.solo-factory/defaults.yaml`
   - If exists, show current values and ask: "Update existing config?" or "Keep current"
   - If not exists, continue to step 2

2. **Ask org defaults** via AskUserQuestion:

   a. **Reverse-domain prefix** (used for iOS bundle ID + Android applicationId):
      - "What is your reverse-domain prefix for app IDs?"
      - Examples: `co.superduperai`, `com.mycompany`, `io.myname`
      - This becomes `<org_domain>` in templates

   b. **Apple Developer Team ID** (optional, for iOS):
      - "Apple Developer Team ID? (leave empty if no iOS apps)"
      - Find at: https://developer.apple.com/account → Membership Details
      - 10-character alphanumeric, e.g. `J6JLR9Y684`
      - This becomes `<apple_dev_team>` in templates

   c. **GitHub org/user** (for `gh repo create`):
      - "GitHub username or org for new repos?"
      - e.g. `fortunto2`, `my-org`

   d. **Projects directory:**
      - "Where do you keep projects?"
      - Default: `~/startups/active`

3. **Create config directory and file:**
   ```bash
   mkdir -p ~/.solo-factory
   ```

   Write `~/.solo-factory/defaults.yaml`:
   ```yaml
   # Solo Factory — org defaults
   # Used by /scaffold and other skills for placeholder replacement.
   # Re-run /init to update these values.

   org_domain: "<answer from 2a>"
   apple_dev_team: "<answer from 2b>"
   github_org: "<answer from 2c>"
   projects_dir: "<answer from 2d>"
   ```

4. **Verify Solograph MCP** (optional check):
   - Try reading `~/.codegraph/registry.yaml`
   - If exists: "Solograph detected — code graph ready"
   - If not: "Tip: install Solograph for code search across projects"

5. **Output summary:**
   ```
   Solo Factory configured!

     Config: ~/.solo-factory/defaults.yaml

     org_domain:     <value>
     apple_dev_team: <value>
     github_org:     <value>
     projects_dir:   <value>

   Next: /scaffold <project-name> <stack-name>
   ```
