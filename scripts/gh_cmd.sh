#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# Core utility functions for gh-ai

# Render a template file by substituting {{ param "NAME" }} with env var values
#
# Reads the given template file, finds all {{ param "NAME" }} occurrences,
# and replaces each with the value of the corresponding environment variable.
#
# Usage: MY_VAR="value" _cmd_render template.tmpl
_cmd_render() {
	local template_file="$1"

	if [[ ! -f "$template_file" ]]; then
		gum log --level error "Template not found: $template_file"
		return 1
	fi

	local template_content
	template_content=$(cat <"$template_file")

	# Sentinel used to escape {{ in substituted values, preventing template injection
	# when git content contains literal {{ param "..." }} strings.
	local sentinel=$'\x01\x02'

	local match
	local name
	local value
	while IFS= read -r match; do
		[[ -z "$match" ]] && continue
		# shellcheck disable=SC2001
		name=$(echo "$match" | sed 's/.*"\([^"]*\)".*/\1/')
		value="${!name}"
		# Escape {{ in substituted values so they aren't treated as template directives
		value="${value//\{\{/${sentinel}}"
		template_content="${template_content//$match/$value}"
	done < <(grep -oE '\{\{[[:space:]]*param[[:space:]]+"[^"]+"[[:space:]]*\}\}' <<<"$template_content" | sort -u)

	# Restore escaped braces
	template_content="${template_content//${sentinel}/\{\{}"

	printf '%s' "$template_content"
}

_cmd_assist() {
	local agent_provider
	agent_provider=$(gh config get gh-ai.provider 2>/dev/null || true)
	agent_provider="${agent_provider:-anthropic}"

	local agent_model="${1:-}"
	if [[ -z "$agent_model" ]]; then
		agent_model=$(gh config get gh-ai.model 2>/dev/null || true)
		agent_model="${agent_model:-haiku}"
	fi

	case "$agent_provider" in
	anthropic)
		MAX_THINKING_TOKENS=0 claude -p \
			--model="$agent_model" \
			--disable-slash-commands \
			--setting-sources='' \
			--system-prompt='' \
			--tools='' \
			- || true
		;;
	*)
		gum log --level error "Unsupported provider '$agent_provider' (supported: anthropic)"
		exit 1
		;;
	esac
}

main() {
	local command
	command="${1:-}"

	case "$command" in
	render)
		_cmd_render "${2:-}"
		;;
	assist)
		_cmd_assist "${2:-}"
		;;
	*)
		gum log --level error "Usage: gh_cmd.sh <render|assist> [args]"
		exit 1
		;;
	esac
}

# CLI entry point (when executed directly, not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
