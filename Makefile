.PHONY: plugin-link plugin-publish help

plugin-link: ## Link solo-factory as live plugin (dev mode — edit files, instant updates)
	@bash scripts/link-plugin.sh

plugin-publish: ## Push + reinstall plugin globally (standard flow)
	@git push
	@cd ~/.claude/plugins/marketplaces/solo && git fetch origin && git reset --hard origin/main
	@CLAUDECODE= claude plugin install solo@solo --scope user
	@echo "Done. Restart Claude Code session."

help: ## Show available commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
