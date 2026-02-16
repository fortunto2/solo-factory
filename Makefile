.PHONY: plugin-link plugin-publish test test-verbose test-triggers hooks help

plugin-link: ## Link solo-factory as live plugin (dev mode — edit files, instant updates)
	@bash scripts/link-plugin.sh

plugin-publish: ## Push + reinstall plugin globally (standard flow)
	@git push
	@cd ~/.claude/plugins/marketplaces/solo && git fetch origin && git reset --hard origin/main
	@CLAUDECODE= claude plugin install solo@solo --scope user
	@echo "Done. Restart Claude Code session."

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
