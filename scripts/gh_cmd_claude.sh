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
# Usage: echo "prompt" | _ask_ai MODEL
_ask_ai() {
	local agent_model="$1"

	MAX_THINKING_TOKENS=0 claude -p \
		--model="$agent_model" \
		--no-session-persistence \
		--disable-slash-commands \
		--setting-sources='' \
		--system-prompt='' \
		--tools='' \
		- || true
}

# Pipe a prompt into Claude for an interactive session
#
# Usage: printf "%s" "$prompt" | _chat_ai [AGENT_ARGS...]
_chat_ai() {
	claude "${_GH_AI_ARGS[@]}" "$@"
}

# Aliases for backward compatibility or explicit 'claude' agent setting
_ask_claude() { _ask_ai "$@"; }
_chat_claude() { _chat_ai "$@"; }
