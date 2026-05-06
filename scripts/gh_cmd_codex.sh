#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# Codex provider functions for gh-claude

# Print the default Codex model for gh-claude commands
#
# Usage: _get_codex_default_model
_get_codex_default_model() {
	printf '%s' "gpt-5.4-mini"
}

# Send a prompt to Codex and print only the final assistant message
#
# Codex emits progress output during non-interactive runs. The
# --output-last-message flag gives gh-claude a stable message-only output channel.
#
# Usage: echo "prompt" | _ask_codex MODEL
_ask_codex() {
	local agent_model="$1"
	local output_file error_file
	output_file=$(mktemp "${TMPDIR:-/tmp}/gh-claude-codex.XXXXXX")
	error_file=$(mktemp "${TMPDIR:-/tmp}/gh-claude-codex-error.XXXXXX")

	local codex_args=(
		--ask-for-approval never
		exec
		--disable web_search_cached
		--disable web_search_request
		--disable image_generation
		--ephemeral
		--ignore-user-config
		--ignore-rules
		--sandbox read-only
		--color never
		--output-last-message "$output_file"
		-c 'model_reasoning_summary="none"'
		-c 'model_verbosity="low"'
	)

	if [[ -n "$agent_model" ]]; then
		codex_args+=(--model "$agent_model")
	fi

	if ! codex "${codex_args[@]}" - >/dev/null 2>"$error_file"; then
		echo "gh-claude: codex failed to generate a response" >&2
		cat "$error_file" >&2
		rm -f "$output_file" "$error_file"
		return 1
	fi
	if [[ ! -s "$output_file" ]]; then
		echo "gh-claude: codex returned an empty response" >&2
		rm -f "$output_file" "$error_file"
		return 1
	fi
	cat "$output_file"
	rm -f "$output_file" "$error_file"
}

# Pipe a prompt into Codex for an interactive session
#
# Usage: printf "%s" "$prompt" | _chat_codex [AGENT_ARGS...]
_chat_codex() {
	# For Codex, we use 'exec' to handle the piped prompt.
	# We don't use --output-last-message here to keep it interactive.
	codex "$@" "${_GH_CLAUDE_ARGS[@]}" -
}
