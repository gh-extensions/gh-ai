#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

_gh_cmd_dir=$(dirname "${BASH_SOURCE[0]}")

# Core utility functions for gh-ai

# Render a template file by substituting ${VAR} placeholders with env var values
#
# Reads the given template file and uses awk to replace ${VAR} tokens with the
# values of the corresponding environment variables (via ENVIRON[]).
#
# File-backed variables: If ENVIRON[VAR] is empty but ENVIRON[VAR_FILE] is set,
# reads the file content from that path. This allows large content to bypass ARG_MAX.
#
# Safety: substitution is a single left-to-right pass — values are never
# re-scanned, so ${...} patterns inside a substituted value (e.g. in a git
# diff) are never expanded. Template files use ALL_CAPS variable names
# (GH_PR_DIFF, etc.) that do not overlap with standard shell variables.
#
# Usage: MY_VAR="value" _cmd_render template.tmpl
# Usage: GH_PR_DIFF_FILE="/tmp/diff.patch" _cmd_render template.tmpl
_cmd_render() {
	local template_file="$1"

	if [[ ! -f "$template_file" ]]; then
		gum log --level error "Template not found: $template_file"
		return 1
	fi

	awk -f "$_gh_cmd_dir/gh_render.awk" "$template_file"
}

# Resolve the configured agent binary name
#
# Reads ai.agent from gh config (default: claude).
#
# Usage: _get_agent       # prints binary name to stdout
_get_agent() {
	local agent
	agent=$(gh config get ai.agent 2>/dev/null || true)
	printf '%s' "${agent:-claude}"
}

# Set the terminal title via the xterm escape sequence.
# tmux intercepts this to rename the current window.
# No-op when not inside tmux.
#
# Usage: _set_terminal_title "P#42/claude"
_set_terminal_title() {
	[[ -z "${TMUX:-}" ]] && return 0
	printf $'\033k%s\033\\' "$1"
}

# Send a prompt to the AI agent in non-interactive (prompt) mode
#
# Reads a prompt from stdin and sends it to the configured agent binary.
# Uses the given model or falls back to ai.model / haiku.
# Currently supports claude as the agent.
#
# Usage: echo "prompt" | _cmd_ask [MODEL]
_cmd_ask() {
	local agent
	agent=$(_get_agent)

	local agent_model="${1:-}"
	if [[ -z "$agent_model" ]]; then
		agent_model=$(gh config get ai.model 2>/dev/null || true)
		agent_model="${agent_model:-haiku}"
	fi

	case "$agent" in
	claude)
		MAX_THINKING_TOKENS=0 claude -p \
			--model="$agent_model" \
			--no-session-persistence \
			--disable-slash-commands \
			--setting-sources='' \
			--system-prompt='' \
			--tools='' \
			- || true
		;;
	*)
		gum log --level error "Unsupported agent '$agent' for ask (supported: claude)"
		return 1
		;;
	esac
}

# Pre-trust a workspace directory in Claude Code so the trust dialog is skipped.
#
# Claude stores trust decisions in ~/.claude.json under per-workspace keys.
# By injecting the entry before Claude enters the directory, we bypass the
# interactive "trust this folder" prompt that would otherwise block the session.
#
# Usage: _trust_workspace "/path/to/workspace"
_trust_workspace() {
	local workspace_path="$1"
	local claude_json="$HOME/.claude.json"
	local tmp
	tmp=$(mktemp)

	if [[ -f "$claude_json" ]]; then
		jq --arg path "$workspace_path" \
			'.projects[$path].hasTrustDialogAccepted = true' "$claude_json" >"$tmp"
	else
		jq -n --arg path "$workspace_path" \
			'{projects: {($path): {hasTrustDialogAccepted: true}}}' >"$tmp"
	fi

	mv "$tmp" "$claude_json"
}

# Pipe a preamble into the configured agent binary
#
# Resolves ai.agent (default: claude), verifies the binary exists, then
# pipes the preamble into it. Extra positional args are forwarded to the agent.
# Pre-trusts the current directory so Claude skips the "trust this folder" dialog.
#
# Usage: _cmd_chat "context preamble" [AGENT_ARGS...]
_cmd_chat() {
	local preamble="$1"
	shift

	local agent
	agent=$(_get_agent)
	if ! command -v "$agent" &>/dev/null; then
		gum log --level error "Agent '$agent' not found"
		gum log --level info "Install it or set: gh config set ai.agent <binary>"
		return 1
	fi

	# Pre-trust the project root so Claude doesn't prompt the user to
	# trust the directory when starting a session.
	_trust_workspace "$(pwd -P)"

	printf "Starting %s — loading context..." "$agent"
	# shellcheck disable=SC2154
	export _GH_AI_SOURCE_DIR="$_gh_ai_source_dir"
	if _gh_in_worktree; then
		gum log --level warn "Running inside a git worktree — skipping worktree setup"
		printf '%s' "$preamble" | cat -s | "$agent" "$@"
	else
		local settings_file="$_gh_ai_source_dir/scripts/gh_worktree.json"
		printf '%s' "$preamble" | cat -s | "$agent" --settings "$settings_file" "$@"
	fi
}

# Extract title from AI response
#
# Gets the title from AI-generated content by taking the first line
# and removing any markdown heading prefix (#).
#
# Usage: _parse_title content
_parse_title() {
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
#
# Usage: _parse_body content
_parse_body() {
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
# Usage: _gh_repo_name repo_ref
_gh_repo_name() {
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
# Usage: _git_repo_path git_dir_ref
_git_repo_path() {
	local -n _git_dir_ref="$1"
	_git_dir_ref=$(git rev-parse --show-toplevel 2>/dev/null || true)
	if [[ -z "$_git_dir_ref" ]]; then
		gum log --level error "Not inside a git repository"
		return 1
	fi
}

# Compute diff, diffstat, log, and formatted commits between two branches
#
# Tries origin/<base> first, falls back to bare <base>.
# Writes results into four namerefs; returns 1 if the diff is empty.
#
# Usage: _git_branch_diff base head diff_ref stat_ref log_ref commits_ref
_git_branch_diff() {
	local base="$1" head="$2"
	local -n _diff_ref="$3" _stat_ref="$4" _log_ref="$5" _commits_ref="$6"

	# Resolve effective base ref once: prefer origin/<base>, fall back to bare <base>
	local effective_base="origin/$base"
	if ! git rev-parse "$effective_base" &>/dev/null; then
		effective_base="$base"
	fi

	_diff_ref=$(git diff "$effective_base"..."$head" 2>/dev/null || true)
	if [[ -z "$_diff_ref" ]]; then
		gum log --level error "Failed to get diff between $base and $head"
		return 1
	fi

	_stat_ref=$(git diff "$effective_base"..."$head" --stat 2>/dev/null || true)
	_log_ref=$(git log --oneline "$effective_base".."$head" 2>/dev/null || true)
	# shellcheck disable=SC2001
	_commits_ref=$(printf '%s\n' "$_log_ref" | sed 's/^[a-f0-9]* /- /')
}

# Create a temporary context directory for ask-mode commands
#
# Creates a temp directory that can hold large context files. Caller is
# responsible for cleanup (rm -rf) after use.
#
# Usage: _create_context_dir context_dir_ref
_create_context_dir() {
	local -n _cdir_ref="$1"
	local _ctx_tmpdir="${TMPDIR:-/tmp}"
	_cdir_ref=$(mktemp -d "${_ctx_tmpdir%/}/gh-ai-ctx.XXXXXXXXXX")
}

# Resolve context directory: persistent session dir for chat, temp dir otherwise
#
# Chat commands get a persistent directory under .claude/sessions/<name>;
# all other commands get a temporary directory via _create_context_dir.
#
# Usage: _resolve_context_dir type session_name dir_ref
_resolve_context_dir() {
	local _rcd_type="$1"
	local _rcd_name="$2"
	local -n _rcd_dir="$3"

	if [[ "$_rcd_type" == "chat" ]]; then
		local _rcd_git_root
		_git_repo_path _rcd_git_root || return 1
		_rcd_dir="$_rcd_git_root/.claude/sessions/$_rcd_name"
		mkdir -p "$_rcd_dir"
	else
		_create_context_dir _rcd_dir
	fi
}

# Save content to a named file in a context directory
#
# Writes content to a file using printf builtin (no execve, so no ARG_MAX impact).
#
# Usage: _save_context_file "/path/to/context/dir" "filename" "content"
_save_context_file() {
	local dir="$1" name="$2" content="$3"
	printf '%s' "$content" >"$dir/$name"
}

# Shared argument parser for chat commands.
#
# Extracts a numeric resource ID (first positional arg), -d/--description value,
# and -n/--new-session flag. Unknown flags produce an error. All internal
# variables use _pca_ prefix to avoid nameref collisions.
#
# Usage: _parse_chat_args id_ref desc_ref new_session_ref [args...]
_parse_chat_args() {
	local -n _pca_id="$1"
	local -n _pca_desc="$2"
	local -n _pca_new_session="$3"
	shift 3

	local _pca_raw=("$@")
	local _pca_skip=false
	local _pca_i=0

	while [[ $_pca_i -lt ${#_pca_raw[@]} ]]; do
		if [[ "$_pca_skip" = true ]]; then
			_pca_skip=false
			((++_pca_i))
			continue
		fi

		case "${_pca_raw[$_pca_i]}" in
		--description | -d)
			if ((_pca_i + 1 >= ${#_pca_raw[@]})); then
				gum log --level error "${_pca_raw[$_pca_i]} requires a value"
				return 1
			fi
			# shellcheck disable=SC2034 # nameref: set by caller
			_pca_desc="${_pca_raw[$((_pca_i + 1))]}"
			_pca_skip=true
			;;
		--description=*)
			# shellcheck disable=SC2034 # nameref: set by caller
			_pca_desc="${_pca_raw[$_pca_i]#--description=}"
			;;
		--new-session | -n)
			# shellcheck disable=SC2034 # nameref: set by caller
			_pca_new_session=1
			;;
		-*)
			gum log --level error "unknown flag '${_pca_raw[$_pca_i]}'"
			return 1
			;;
		*)
			local _pca_arg="${_pca_raw[$_pca_i]#\#}"
			if [[ -z "$_pca_id" && "$_pca_arg" =~ ^[0-9]+$ ]]; then
				_pca_id="$_pca_arg"
			else
				gum log --level error "unexpected argument '${_pca_raw[$_pca_i]}'"
				return 1
			fi
			;;
		esac
		((++_pca_i))
	done
}

# Validate chat passthrough args, rejecting flags managed by gh-ai.
#
# Returns 1 if --worktree, --session-id, or --resume are found.
#
# Usage: _validate_chat_passthrough passthrough_ref
_validate_chat_passthrough() {
	local -n _vcp_args="$1"
	local _vcp_flag
	for _vcp_flag in "${_vcp_args[@]}"; do
		case "$_vcp_flag" in
		--worktree | --session-id | --resume)
			gum log --level error "$_vcp_flag is managed by gh-ai and cannot be passed through"
			return 1
			;;
		esac
	done
}

# Resolve session arguments for _cmd_chat and report whether a new session
# is being started.
#
# Reads the session UUID from $session_dir/session.id.
#   - File present and new_session is empty: sets is_new_ref to "" and
#     args_ref to (--resume <uuid>).
#   - File absent or new_session is non-empty: generates a new UUID, writes it
#     to the file, sets is_new_ref to 1 and args_ref to (--session-id <uuid>).
#
# Usage: _resolve_chat_session session_dir new_session is_new_ref args_ref
_resolve_chat_session() {
	local _rcs_dir="$1"
	local _rcs_new_session="$2"
	local -n _rcs_is_new="$3"
	local -n _rcs_args="$4"

	local _rcs_session_file="$_rcs_dir/session.id"
	local _rcs_uuid

	if [[ -n "$_rcs_new_session" ]]; then
		rm -fr "$_rcs_session_file"
	fi

	if [[ -f "$_rcs_session_file" ]]; then
		_rcs_uuid=$(<"$_rcs_session_file")
		# shellcheck disable=SC2034 # nameref: set by caller
		_rcs_is_new=""
		# shellcheck disable=SC2034 # nameref: set by caller
		_rcs_args=(--resume "$_rcs_uuid")
	else
		_rcs_uuid=$(uuidgen 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)
		if [[ -z "$_rcs_uuid" ]]; then
			gum log --level error "Failed to generate session UUID"
			return 1
		fi
		printf '%s' "$_rcs_uuid" >"$_rcs_session_file"
		# shellcheck disable=SC2034 # nameref: set by caller
		_rcs_is_new=1
		# shellcheck disable=SC2034 # nameref: set by caller
		_rcs_args=(--session-id "$_rcs_uuid")
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
	chat)
		shift
		_cmd_chat "$@"
		;;
	*)
		gum log --level error "Usage: gh_cmd.sh <render|ask|chat> [args]"
		exit 1
		;;
	esac
}

# CLI entry point (when executed directly, not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
