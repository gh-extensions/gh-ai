#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# Forge provider functions for gh-ai

# Print the default Forge model for gh-ai commands
#
# Forge selects its model from its own configuration, so gh-ai does not
# pass a --model flag. Returns empty.
#
# Usage: _get_forge_default_model
_get_forge_default_model() {
	printf '%s' ""
}

# Send a prompt to Forge and print the response
#
# Usage: echo "prompt" | _ask_forge MODEL
_ask_forge() {
	local prompt output error_file
	prompt=$(cat)
	error_file=$(mktemp "${TMPDIR:-/tmp}/gh-ai-forge-error.XXXXXX")

	if ! output=$(forge --prompt "$prompt" </dev/null 2>"$error_file"); then
		echo "gh-ai: forge failed to generate a response" >&2
		cat "$error_file" >&2
		rm -f "$error_file"
		return 1
	fi
	rm -f "$error_file"

	if [[ -z "$output" ]]; then
		echo "gh-ai: forge returned an empty response" >&2
		return 1
	fi
	printf '%s' "$output"
}

# Pipe a prompt into Forge for an interactive session
#
# Forge accepts the seed prompt on stdin. The shared dispatcher in
# scripts/gh_cmd.sh appends the prompt as the last positional arg, so we
# pop it off before feeding it through the pipe.
#
# Usage: _chat_forge [AGENT_ARGS...] [PROMPT]
_chat_forge() {
	local prompt=""
	if [[ $# -gt 0 ]]; then
		prompt="${!#}"
		set -- "${@:1:$#-1}"
	fi

	if [[ -n "$prompt" ]]; then
		printf '%s' "$prompt" | forge "${_GH_AI_ARGS[@]}" "$@"
	else
		forge "${_GH_AI_ARGS[@]}" "$@"
	fi
}
