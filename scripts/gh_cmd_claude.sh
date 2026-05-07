#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# Claude provider functions for gh-ai

# Print the default Claude model for gh-ai commands
#
# Usage: _get_claude_default_model
_get_claude_default_model() {
	printf '%s' "haiku"
}

# Send a prompt to Claude in non-interactive (prompt) mode
#
# Usage: echo "prompt" | _ask_claude MODEL
_ask_claude() {
	local agent_model="$1"

	MAX_THINKING_TOKENS=0 claude -p \
		--dangerously-skip-permissions \
		--model="$agent_model" \
		--no-session-persistence \
		--disable-slash-commands \
		--setting-sources='' \
		--system-prompt='' \
		--tools='Read(*)' \
		- || true
}

# Pipe a prompt into Claude for an interactive session
#
# Usage: printf "%s" "$prompt" | _chat_claude [AGENT_ARGS...]
_chat_claude() {
	claude "${_GH_AI_ARGS[@]}" "$@"
}
