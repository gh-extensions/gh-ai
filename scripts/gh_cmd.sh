#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# Core utility functions for gh-ai

# Render a template file by substituting ${VAR} placeholders with env var values
#
# Reads the given template file and uses envsubst to replace ${VAR} tokens
# with the values of the corresponding environment variables.
#
# Usage: MY_VAR="value" _cmd_render template.tmpl
_cmd_render() {
	local template_file="$1"

	if [[ ! -f "$template_file" ]]; then
		gum log --level error "Template not found: $template_file"
		return 1
	fi

	envsubst <"$template_file"
}

# Send a prompt to the AI provider and print the response
#
# Reads a prompt from stdin and sends it to the configured AI provider.
# Uses the given model or falls back to gh-ai.model / haiku.
#
# Usage: echo "prompt" | _cmd_assist [MODEL]
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

# Extract title from AI response
#
# Gets the title from AI-generated content by taking the first line
# and removing any markdown heading prefix (#).
#
# Example: _get_title "# Fix bug in parser\n\nDescription..."
# Returns: "Fix bug in parser"
_get_title() {
	local ai_content="$1"

	local title
	# Extract title (first line with # prefix removed)
	title=$(printf '%s\n' "$ai_content" | head -n 1 | sed 's/^# *//')

	# Validate we got a title
	if [[ -z "$title" ]]; then
		return 1
	fi

	printf '%s\n' "$title"
}

# Extract body from AI response
#
# Takes everything after the first line of AI content (skipping the title),
# removes leading blank lines, and prepends a markdownlint directive.
_get_body() {
	local ai_content="$1"

	local body
	# Extract body (skip first line) and remove leading blank lines
	body=$(printf '%s\n' "$ai_content" | tail -n +2 | sed '/./,$!d')

	# Suppress common markdownlint warnings in AI-generated body
	local footer
	footer="<!-- markdownlint-disable-file MD013 MD022 MD041 MD047 -->"

	printf '%s\n\n%s\n' "$body" "$footer"
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
