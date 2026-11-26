#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# Pi provider functions for gh-ai

# Print the default Pi model for gh-ai commands
#
# Pi has no single built-in model: it resolves one from the configured
# provider and credentials. Returning nothing leaves --model unset so Pi
# picks its own default.
#
# Usage: _get_pi_default_model
_get_pi_default_model() {
	printf '%s' ""
}

# Send a prompt to Pi in non-interactive (print) mode
#
# Pi reads the prompt from stdin and prints only the final assistant text to
# stdout. Tools are limited to read so the agent can inspect staged context
# files without modifying the working tree, and sessions are ephemeral.
#
# Usage: echo "prompt" | _ask_pi MODEL
_ask_pi() {
	local agent_model="$1"

	local pi_args=(
		--print
		--no-session
		--no-context-files
		--no-mcp
		--tools read
	)

	if [[ -n "$agent_model" ]]; then
		pi_args+=(--model "$agent_model")
	fi

	pi "${pi_args[@]}"
}

# Start an interactive Pi session
#
# Pi accepts the seeding prompt as a positional argument, so all arguments
# (including any prompt) are forwarded directly.
#
# Usage: _chat_pi [AGENT_ARGS...] [PROMPT]
_chat_pi() {
	pi "${_GH_AI_ARGS[@]}" "$@"
}
