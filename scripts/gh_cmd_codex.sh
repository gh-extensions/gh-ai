#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# Codex provider functions for gh-ai

# Print the default Codex model for gh-ai commands
#
# Usage: _get_codex_default_model
_get_codex_default_model() {
	printf '%s' "gpt-5.4-mini"
}

# Send a prompt to Codex and print only the final assistant message
#
# Codex emits progress output during non-interactive runs. The
# --output-last-message flag gives gh-ai a stable message-only output channel.
#
# Usage: echo "prompt" | _ask_codex MODEL
_ask_codex() {
	local agent_model="$1"
	local output_file error_file
	output_file=$(mktemp "${TMPDIR:-/tmp}/gh-ai-codex.XXXXXX")
	error_file=$(mktemp "${TMPDIR:-/tmp}/gh-ai-codex-error.XXXXXX")

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
		echo "gh-ai: codex failed to generate a response" >&2
		cat "$error_file" >&2
		rm -f "$output_file" "$error_file"
		return 1
	fi
	if [[ ! -s "$output_file" ]]; then
		echo "gh-ai: codex returned an empty response" >&2
		rm -f "$output_file" "$error_file"
		return 1
	fi
	cat "$output_file"
	rm -f "$output_file" "$error_file"
}

# Start an interactive Codex session
#
# Codex requires a TTY on stdin and only accepts the prompt as a positional
# argument, so all arguments (including any seeding prompt) are forwarded
# directly to codex rather than piped via stdin.
#
# Usage: _chat_codex [AGENT_ARGS...] [PROMPT]
_chat_codex() {
	codex "${_GH_AI_ARGS[@]}" "$@"
}
