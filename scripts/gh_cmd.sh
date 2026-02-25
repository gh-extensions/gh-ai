#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# Filter out specified flags and their values from an argument list
#
# Takes two space-separated lists of flags to remove (value flags and standalone
# flags), then -- followed by the arguments to filter.
#
# Usage: _filter_args "VALUE_FLAGS" "STANDALONE_FLAGS" -- "$@"
# Example: _filter_args "--title -t --body -b" "--fill --fill-first" -- --title "test" --draft --fill
# Returns: --draft
_filter_args() {
	local vf=" $1 "
	local sf=" ${2:-} "
	shift 2
	shift # consume value_flags, standalone_flags, --

	local filtered=()
	while [[ $# -gt 0 ]]; do
		if [[ "$sf" == *" $1 "* ]]; then
			shift
		elif [[ "$vf" == *" $1 "* ]]; then
			shift
			[[ $# -gt 0 && "$1" != -* ]] && shift
		elif [[ "$1" == --*=* ]] && [[ "$vf" == *" ${1%%=*} "* ]]; then
			shift
		else
			filtered+=("$1")
			shift
		fi
	done

	[[ ${#filtered[@]} -gt 0 ]] && printf '%s\n' "${filtered[@]}" || true
}

# Core utility functions for gh-assistant

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
	agent_provider=$(gh config get gh-assistant.provider 2>/dev/null || true)
	agent_provider="${agent_provider:-anthropic}"

	local agent_model="${1:-}"
	if [[ -z "$agent_model" ]]; then
		agent_model=$(gh config get gh-assistant.model 2>/dev/null || true)
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
