.PHONY: plugin-link plugin-publish clawhub-publish clawhub-publish-all publish-all test test-verbose test-triggers hooks help

plugin-link: ## Link solo-factory as live plugin (dev mode — edit files, instant updates)
	@bash scripts/link-plugin.sh

plugin-publish: ## Push + reinstall Claude Code plugin globally
	@git push
	@cd ~/.claude/plugins/marketplaces/solo && git fetch origin && git reset --hard origin/main
	@CLAUDECODE= claude plugin install solo@solo --scope user
	@echo "Done. Restart Claude Code session."

clawhub-publish: ## Publish one skill to ClawHub (S=skill-name, e.g. S=research)
	@test -n "$(S)" || (echo "Usage: make clawhub-publish S=research" && exit 1)
	@version=$$(grep -A3 'metadata:' skills/$(S)/SKILL.md | grep 'version:' | sed 's/.*version: *"\(.*\)"/\1/' | head -1); \
	 test -n "$$version" || version="1.0.0"; \
	 echo "Publishing solo-$(S)@$$version to ClawHub..."; \
	 pnpm dlx clawhub@latest publish "$$(pwd)/skills/$(S)" --slug solo-$(S) --version $$version --changelog "$(MSG)"

clawhub-publish-all: ## Publish all skills to ClawHub (slow — 3s delay per skill, rate limit ~5/hour for new)
	@for dir in skills/*/; do \
	   name=$$(basename "$$dir"); \
	   version=$$(grep -A3 'metadata:' "$$dir/SKILL.md" | grep 'version:' | sed 's/.*version: *"\(.*\)"/\1/' | head -1); \
	   test -n "$$version" || version="1.0.0"; \
	   echo -n "solo-$$name@$$version... "; \
	   pnpm dlx clawhub@latest publish "$$(pwd)/$$dir" --slug "solo-$$name" --version "$$version" --changelog "Update" 2>&1 | grep -oE '(OK\. Published|Rate limit|already exists|Error).*' | head -1; \
	   sleep 3; \
	 done

clawhub-publish-remaining: ## Publish only unpublished skills to ClawHub (checks registry first)
	@echo "Checking published skills..."; \
	 published=$$(pnpm dlx clawhub@latest search "solo-" 2>/dev/null | grep -oE 'solo-[a-z-]+' | sort -u); \
	 for dir in skills/*/; do \
	   name=$$(basename "$$dir"); \
	   if echo "$$published" | grep -q "^solo-$$name$$"; then \
	     echo "skip solo-$$name (already published)"; \
	   else \
	     version=$$(grep -A3 'metadata:' "$$dir/SKILL.md" | grep 'version:' | sed 's/.*version: *"\(.*\)"/\1/' | head -1); \
	     test -n "$$version" || version="1.0.0"; \
	     echo -n "NEW solo-$$name@$$version... "; \
	     pnpm dlx clawhub@latest publish "$$(pwd)/$$dir" --slug "solo-$$name" --version "$$version" --changelog "Initial publish" 2>&1 | grep -oE '(OK\. Published|Rate limit|Error).*' | head -1; \
	     sleep 3; \
	   fi; \
	 done

publish-all: plugin-publish clawhub-publish-all ## Publish to ALL registries (Claude Code + ClawHub)

evolve: ## Show evolution log (factory defects from retros + codex critiques)
	@cat ~/.solo/evolution.md 2>/dev/null || echo "No evolution log yet. Run a pipeline with retro to generate."

evolve-apply: ## Apply evolution fixes to solo-factory (interactive)
	@echo "Defects in ~/.solo/evolution.md:"
	@grep -c "^DEFECT:" ~/.solo/evolution.md 2>/dev/null || echo "0"
	@echo ""
	@echo "Run: claude -p '/solo:plan Apply factory defects from ~/.solo/evolution.md to solo-factory skills and scripts'"

test: ## Run all tests (BATS + trigger validation)
	@bats tests/
	@python3 scripts/validate_triggers.py

test-bats: ## Run BATS tests only
	@bats tests/

test-verbose: ## Run BATS tests with verbose output
	@bats --verbose-run tests/

test-triggers: ## Run skill trigger validation
	@python3 scripts/validate_triggers.py

hooks: ## Install pre-commit hooks
	@uvx pre-commit install
	@echo "Pre-commit hooks installed."

factory-critique: ## Run Codex factory critique on a project (P=project)
	@bash scripts/solo-codex.sh $(P) --factory

help: ## Show available commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
