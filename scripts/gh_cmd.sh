#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# Core utility functions for gh-ai

# Render a template file by substituting ${VAR} placeholders with env var values
#
# Reads the given template file and uses awk to replace ${VAR} tokens with the
# values of the corresponding environment variables (via ENVIRON[]).
#
# Safety: substitution is a single left-to-right pass — values are never
# re-scanned, so ${...} patterns inside a substituted value (e.g. in a git
# diff) are never expanded. Template files use ALL_CAPS variable names
# (GIT_DIFF, GH_PR_*, etc.) that do not overlap with standard shell variables.
#
# Usage: MY_VAR="value" _cmd_render template.tmpl
_cmd_render() {
	local template_file="$1"

	if [[ ! -f "$template_file" ]]; then
		gum log --level error "Template not found: $template_file"
		return 1
	fi

	awk '
	{ content = content $0 "\n" }
	END {
		result = ""; remaining = content
		while (match(remaining, /\$\{[A-Z_][A-Z0-9_]*\}/)) {
			varname = substr(remaining, RSTART+2, RLENGTH-3)
			result = result substr(remaining, 1, RSTART-1) ENVIRON[varname]
			remaining = substr(remaining, RSTART+RLENGTH)
		}
		printf "%s%s", result, remaining
	}' "$template_file"
}

# Send a prompt to the AI provider and print the response
#
# Reads a prompt from stdin and sends it to the configured AI provider.
# Uses the given model or falls back to gh-ai.model / haiku.
#
# Usage: echo "prompt" | _cmd_ask [MODEL]
_cmd_ask() {
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
		return 1
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
	local content="$1"

	local title
	# Extract title (first line with # prefix removed)
	title=$(printf '%s\n' "$content" | head -n 1 | sed 's/^# *//')

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
	local content="$1"

	local body
	# Extract body (skip first line) and remove leading blank lines
	body=$(printf '%s\n' "$content" | tail -n +2 | sed '/./,$!d')

	# Suppress common markdownlint warnings in AI-generated body
	local footer
	footer="<!-- markdownlint-disable-file MD013 MD022 MD041 MD047 -->"

	printf '%s\n\n%s\n' "$body" "$footer"
}

# Split arguments on the first `--` separator
#
# Populates two nameref arrays: everything before `--` goes into the first,
# everything after goes into the second.  A second `--` in the tail section
# is kept verbatim (passed through).
#
# Usage: _split_on_separator before_ref after_ref "$@"
_split_on_separator() {
	local -n _before_ref="$1"
	local -n _after_ref="$2"
	shift 2

	_before_ref=()
	_after_ref=()

	while [[ $# -gt 0 ]]; do
		if [[ "$1" == "--" ]]; then
			shift
			_after_ref=("$@")
			return 0
		fi
		_before_ref+=("$1")
		shift
	done
}

# Resolve the current repo's nameWithOwner (e.g. "owner/repo")
#
# Writes the result into the nameref; returns 1 and logs an error on failure.
#
# Usage: _get_repo_name repo_ref
_get_repo_name() {
	local -n _gh_repo_ref="$1"
	_gh_repo_ref=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || true)
	if [[ -z "$_gh_repo_ref" ]]; then
		gum log --level error "Not inside a GitHub repository (gh repo view failed)"
		return 1
	fi
}

# Resolve the git repository root directory
#
# Writes the result into the nameref; returns 1 and logs an error on failure.
#
# Usage: _get_git_repo_path git_dir_ref
_get_git_repo_path() {
	local -n _git_dir_ref="$1"
	_git_dir_ref=$(git rev-parse --show-toplevel 2>/dev/null || true)
	if [[ -z "$_git_dir_ref" ]]; then
		gum log --level error "Not inside a git repository"
		return 1
	fi
}

main() {
	local command
	command="${1:-}"

	case "$command" in
	render)
		_cmd_render "${2:-}"
		;;
	ask)
		_cmd_ask "${2:-}"
		;;
	*)
		gum log --level error "Usage: gh_cmd.sh <render|ask> [args]"
		exit 1
		;;
	esac
}

# CLI entry point (when executed directly, not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
