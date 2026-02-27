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
		return 1
		;;
	esac
}

# Launch or resume a Claude Code chat session in a worktree
#
# Reads the gh-ai provider from gh config (defaults to anthropic).
# Returns 1 with an error if the provider is not supported.
# If the session sentinel file exists, resumes the previous session.
# Otherwise runs cmd... to capture its output, then starts a new claude
# session with that output as the initial prompt, and touches the sentinel
# file on success.
#
# Usage: _cmd_chat <session_file> <worktree_name> <session_id> <preamble> <model> [cmd...]
#   session_file   — path to the sentinel file (created on first run)
#   worktree_name  — worktree name passed to claude --worktree (e.g. "issue-42")
#   session_id     — deterministic UUID for --session-id / --resume
#   preamble       — instruction prepended to the initial prompt (required)
#   model          — optional model string (pass "" to let claude use its default)
#   cmd...         — command whose stdout seeds the initial prompt
_cmd_chat() {
	local session_file="$1"
	local worktree_name="$2"
	local session_id="$3"
	local preamble="$4"
	local agent_model="$5"
	shift 5

	local agent_provider
	agent_provider=$(gh config get gh-ai.provider 2>/dev/null || true)
	agent_provider="${agent_provider:-anthropic}"

	case "$agent_provider" in
	anthropic)
		local claude_args=(--worktree "$worktree_name")
		[[ -n "$agent_model" ]] && claude_args+=(--model "$agent_model")

		if [[ -f "$session_file" ]]; then
			claude "${claude_args[@]}" --resume "$session_id"
		else
			"$@" | claude "${claude_args[@]}" --session-id "$session_id" "$preamble" && touch "$session_file"
		fi
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
	local -n _repo_ref="$1"
	_repo_ref=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || true)
	if [[ -z "$_repo_ref" ]]; then
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

# Initialise a deterministic chat session
#
# Derives a UUID v5 session ID from the repo name and entity key, writes the
# ID and the sentinel file path into the provided namerefs, and creates the
# session directory.
#
# Usage: _init_claude_session id_ref file_ref <repo_name> <entity_key> <git_dir>
#   repo_name   — "owner/repo" string
#   entity_key  — e.g. "I42", "P99", "R12345"
#   git_dir     — absolute path returned by git rev-parse --show-toplevel
_init_claude_session() {
	local -n _id_ref="$1"
	local -n _file_ref="$2"
	local repo_name="$3"
	local entity_key="$4"
	local git_dir="$5"

	_id_ref=$(uuid -v5 ns:URL "${repo_name}#${entity_key}")
	local session_dir="$git_dir/.claude/sessions"
	mkdir -p "$session_dir"
	_file_ref="$session_dir/$_id_ref"
}

# Create or fast-forward a worktree for a given branch
#
# If the worktree path does not exist, creates it with `git worktree add -B`.
# If it already exists, fast-forward merges from the remote branch.
# Returns 1 (with an error message) if the merge would not be fast-forward.
#
# Usage: _git_worktree_sync <branch> <path> <remote_branch> <label>
#   branch         — local branch name (e.g. "pr-99")
#   path           — absolute worktree path
#   remote_branch  — remote branch to fetch/merge (e.g. "feature/my-change")
#   label          — human-readable label for spinner messages
_git_worktree_sync() {
	local branch="$1"
	local wt_path="$2"
	local remote_branch="$3"
	local label="$4"

	if [[ ! -d "$wt_path" ]]; then
		gum spin --title "Fetching $label branch..." -- \
			git fetch origin "$remote_branch" || true
		git worktree add -B "$branch" "$wt_path" "origin/$remote_branch"
	else
		gum spin --title "Updating $label worktree..." -- \
			git -C "$wt_path" merge --ff-only "origin/$remote_branch" 2>/dev/null || {
			gum log --level error "Worktree '$wt_path' has diverged from origin/$remote_branch — resolve manually"
			return 1
		}
	fi
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
