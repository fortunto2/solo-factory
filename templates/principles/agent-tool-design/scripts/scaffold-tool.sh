#!/bin/bash
# Generate Rust tool boilerplate for an agent tool
#
# Usage: scaffold-tool.sh ToolName "Short description"
# Example: scaffold-tool.sh GrepCount "Count lines matching a regex pattern"
#
# Output: prints Rust code to stdout. Redirect to file:
#   ./scaffold-tool.sh GrepCount "Count matching lines" > src/tools/grep_count.rs

set -euo pipefail

TOOL_NAME="${1:?Usage: scaffold-tool.sh ToolName \"description\"}"
DESCRIPTION="${2:?Usage: scaffold-tool.sh ToolName \"description\"}"

# Convert PascalCase to snake_case for function/module name
SNAKE_NAME=$(echo "$TOOL_NAME" | sed 's/\([A-Z]\)/_\L\1/g' | sed 's/^_//')

cat <<RUST
use std::sync::Arc;

use async_trait::async_trait;
use schemars::JsonSchema;
use serde::Deserialize;
use serde_json::Value;

use sgr_agent::{AgentContext, Tool, ToolError, ToolOutput};

use crate::pcm::PcmClient;

pub struct ${TOOL_NAME}Tool(pub Arc<PcmClient>);

#[derive(Deserialize, JsonSchema)]
struct ${TOOL_NAME}Args {
    /// Primary argument (rename this)
    path: String,
}

#[async_trait]
impl Tool for ${TOOL_NAME}Tool {
    fn name(&self) -> &str { "${SNAKE_NAME}" }

    fn description(&self) -> &str {
        "${DESCRIPTION}"
    }

    fn parameters_schema(&self) -> Value {
        schemars::schema_for!(${TOOL_NAME}Args).into()
    }

    fn is_readonly(&self) -> bool { true }

    async fn execute(&self, args: Value, _ctx: &AgentContext) -> Result<ToolOutput, ToolError> {
        let a: ${TOOL_NAME}Args = serde_json::from_value(args)
            .map_err(|e| ToolError::InvalidArgs(e.to_string()))?;

        // TODO: implement tool logic
        let result = format!("${TOOL_NAME} executed on {}", a.path);

        Ok(ToolOutput::text(result))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_parse_args() {
        let args = json!({"path": "/test"});
        let parsed: ${TOOL_NAME}Args = serde_json::from_value(args).unwrap();
        assert_eq!(parsed.path, "/test");
    }

    #[test]
    fn test_name() {
        let tool = ${TOOL_NAME}Tool(Arc::new(PcmClient::mock()));
        assert_eq!(tool.name(), "${SNAKE_NAME}");
    }
}
RUST
