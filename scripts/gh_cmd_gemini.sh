#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# Gemini provider functions for gh-ai

# Print the default Gemini model for gh-ai commands
#
# Usage: _get_gemini_default_model
_get_gemini_default_model() {
	printf '%s' "gemini-2.0-flash"
}

# Send a prompt to Gemini and print the response
#
# Usage: echo "prompt" | _ask_gemini MODEL
_ask_gemini() {
	local agent_model="$1"
	local prompt output error_file
	prompt=$(cat)
	error_file=$(mktemp "${TMPDIR:-/tmp}/gh-ai-gemini-error.XXXXXX")

	if ! output=$(
		CI=true gemini \
			--prompt "$prompt" \
			--approval-mode plan \
			--extensions '' \
			--output-format json \
			--skip-trust \
			--model "$agent_model" \
			</dev/null \
			2>"$error_file"
	); then
		echo "gh-ai: gemini failed to generate a response" >&2
		cat "$error_file" >&2
		rm -f "$error_file"
		return 1
	fi
	rm -f "$error_file"

	output=$(printf '%s' "$output" | jq -r '.response // empty')

	if [[ -z "$output" ]]; then
		echo "gh-ai: gemini returned an empty response" >&2
		return 1
	fi
	printf '%s' "$output"
}

# Pipe a prompt into Gemini for an interactive session
#
# Usage: printf "%s" "$prompt" | _chat_gemini [AGENT_ARGS...]
_chat_gemini() {
	# Gemini CLI doesn't have a perfect "agent" mode like Claude,
	# but we can pass the prompt and let it be interactive if supported.
	gemini "${_GH_AI_ARGS[@]}" "$@"
}
