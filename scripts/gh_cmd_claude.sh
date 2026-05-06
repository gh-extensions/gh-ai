#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# Claude provider functions for gh-claude

# Print the default Claude model for gh-claude commands
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
# Usage: printf "%s" "$prompt" | _chat_claude [AGENT_ARGS...]
_chat_claude() {
	# Pre-trust the project root so Claude doesn't prompt the user to
	# trust the directory when starting a session.
	_trust_workspace "$(pwd -P)"

	claude "$@" "${_GH_CLAUDE_ARGS[@]}"
}
