#!/usr/bin/env bash

[ -z "$DEBUG" ] || set -x

set -eo pipefail

# Core utility functions for gh-assistant

# Render a template file by substituting {{ param "NAME" }} with env var values
#
# Reads the given template file, finds all {{ param "NAME" }} occurrences,
# and replaces each with the value of the corresponding environment variable.
#
# Usage: MY_VAR="value" _cmd_render template.tmpl
_cmd_render() {
	local content
	content=$(cat <"$1")

	local match
	local name
	while IFS= read -r match; do
		[[ -z "$match" ]] && continue
		# shellcheck disable=SC2001
		name=$(echo "$match" | sed 's/.*"\([^"]*\)".*/\1/')
		content="${content//$match/${!name}}"
	done < <(grep -oE '\{\{[[:space:]]*param[[:space:]]+"[^"]+"[[:space:]]*\}\}' <<<"$content" | sort -u)

	printf '%s' "$content"
}

_cmd_assist() {
	local agent_model="${1:-}"

	local agent_provider
	agent_provider=$(gh config get gh-assistant.provider 2>/dev/null || true)
	agent_provider="${agent_provider:-anthropic}"

	if [[ -z "$agent_model" ]]; then
		agent_model=$(gh config get gh-assistant.model 2>/dev/null || true)
		agent_model="${agent_model:-haiku}"
	fi

	case "$agent_provider" in
	anthropic)
		MAX_THINKING_TOKENS=0 claude -p \
			--model="$agent_model" \
			--tools='' \
			--disable-slash-commands \
			--setting-sources='' \
			--system-prompt='' \
			"$(cat)"
		;;
	*)
		echo "gh-assistant: unsupported provider '$agent_provider' (supported: anthropic)" >&2
		exit 1
		;;
	esac
}

main() {
	local command
	command="${1:-}"

	case "$command" in
	render)
		_cmd_render "$2"
		;;
	assist)
		_cmd_assist "$2"
		;;
	*)
		echo "Usage: gh_cmd.sh <render|assist> [args]" >&2
		exit 1
		;;
	esac
}

# CLI entry point (when executed directly, not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
