.PHONY: plugin-link help

plugin-link: ## Link solo-factory as live plugin (run once after install or version bump)
	@bash scripts/link-plugin.sh

help: ## Show available commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
