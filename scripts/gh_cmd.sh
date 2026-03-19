#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

_gh_cmd_dir=$(dirname "${BASH_SOURCE[0]}")

# Core utility functions for gh-claude

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

# Resolve the configured model for a given scope
# Resolves: _GH_CLAUDE_ARGS --model → claude.<scope>.model → claude.model → haiku
# Usage: _gh_config_claude_model [SCOPE]   (SCOPE: pr | issue | run | empty)
_gh_config_claude_model() {
	local scope="${1:-}"
	local model=""
	model=$(_extract_claude_arg --model)
	if [[ -z "$model" && -n "$scope" ]]; then
		model=$(gh config get "claude.${scope}.model" 2>/dev/null || true)
	fi
	if [[ -z "$model" ]]; then
		model=$(gh config get claude.model 2>/dev/null || true)
	fi
	printf '%s' "${model:-haiku}"
}

# Extract a flag's value from the _GH_CLAUDE_ARGS array.
#
# Scans _GH_CLAUDE_ARGS for a --flag followed by its value.
# Prints the value to stdout if found; prints nothing otherwise.
#
# Usage: value=$(_extract_claude_arg --model)
_extract_claude_arg() {
	local _eca_flag="$1"
	local _eca_i=0
	while [[ $_eca_i -lt ${#_GH_CLAUDE_ARGS[@]} ]]; do
		if [[ "${_GH_CLAUDE_ARGS[$_eca_i]}" == "$_eca_flag" ]] && ((_eca_i + 1 < ${#_GH_CLAUDE_ARGS[@]})); then
			printf '%s' "${_GH_CLAUDE_ARGS[$((_eca_i + 1))]}"
			return 0
		fi
		((++_eca_i))
	done
}

# Send a prompt to Claude in non-interactive (prompt) mode
#
# Reads a prompt from stdin and sends it to claude.
# Uses the given model or falls back to claude.model / haiku.
#
# Usage: echo "prompt" | _cmd_ask [MODEL]
_cmd_ask() {
	local agent_model="${1:-}"
	if [[ -z "$agent_model" ]]; then
		agent_model=$(_gh_config_claude_model)
	fi

	MAX_THINKING_TOKENS=0 claude -p \
		--model="$agent_model" \
		--no-session-persistence \
		--disable-slash-commands \
		--setting-sources='' \
		--system-prompt='' \
		--tools='' \
		- || true
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

# Pipe a prompt into Claude
#
# Verifies the claude binary exists, then pipes the prompt into it.
# Extra positional args are forwarded to claude.
# Pre-trusts the current directory so Claude skips the "trust this folder" dialog.
#
# Usage: _cmd_chat "url" "context prompt" [AGENT_ARGS...]
_cmd_chat() {
	local url="$1"
	local prompt="$2"
	shift 2

	if ! command -v claude &>/dev/null; then
		gum log --level error "claude not found"
		gum log --level info "Install claude: https://docs.anthropic.com/en/docs/claude-code"
		return 1
	fi

	# Pre-trust the project root so Claude doesn't prompt the user to
	# trust the directory when starting a session.
	_trust_workspace "$(pwd -P)"

	if [[ -n "$prompt" ]]; then
		printf "%s" "$url" | claude --append-system-prompt "$prompt" "$@" "${_GH_CLAUDE_ARGS[@]}"
	else
		claude "$@" "${_GH_CLAUDE_ARGS[@]}"
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

# Resolve the repository's default branch name
#
# Tries origin/HEAD first, then falls back to the GitHub API, and finally
# defaults to "main".
#
# Usage: branch=$(_git_default_branch)
_git_default_branch() {
	local branch
	branch=$(git rev-parse --abbrev-ref origin/HEAD 2>/dev/null | sed 's|origin/||' ||
		gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null || echo "main")
	printf '%s' "$branch"
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

# Resolve the main worktree root, even when called from a linked worktree.
#
# git rev-parse --git-common-dir returns the shared .git directory path;
# its parent is always the main worktree root regardless of which worktree
# is currently active.
#
# Writes the result into the nameref; returns 1 and logs an error on failure.
#
# Usage: _git_main_worktree_path path_ref
_git_main_worktree_path() {
	local -n _gmwp_ref="$1"
	local _gmwp_common_dir
	_gmwp_common_dir=$(git rev-parse --git-common-dir 2>/dev/null || true)
	if [[ -z "$_gmwp_common_dir" ]]; then
		gum log --level error "Not inside a git repository"
		return 1
	fi
	_gmwp_ref=$(cd "$_gmwp_common_dir/.." && pwd -P)
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
	_cdir_ref=$(mktemp -d "${_ctx_tmpdir%/}/gh-claude-ctx.XXXXXXXXXX")
}

# Generate a UUID v4 using /dev/urandom and od (no uuidgen required).
#
# Reads 16 random bytes, formats them as a lowercase UUID v4 string with
# the version (4) and variant bits set correctly.
#
# Stdout: uuid string (e.g. f47ac10b-58cc-4372-a567-0e02b2c3d479)
# Usage: uuid=$(_uuidgen)
_uuidgen() {
	local _ug_hex
	_ug_hex=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
	printf '%s-%s-4%s-%02x%s-%s\n' \
		"${_ug_hex:0:8}" \
		"${_ug_hex:8:4}" \
		"${_ug_hex:13:3}" \
		$(( (16#${_ug_hex:16:2} & 0x3f) | 0x80 )) \
		"${_ug_hex:18:2}" \
		"${_ug_hex:20:12}"
}

# Resolve the base directory for persistent chat sessions.
# Uses XDG_STATE_HOME if set, otherwise ~/.local/state/gh/claude/sessions.
#
# Stdout: base directory path
# Usage: base=$(_gh_session_base_dir)
_gh_session_base_dir() {
	printf '%s' "${XDG_STATE_HOME:-$HOME/.local/state}/gh/claude/sessions"
}

# Resolve context directory: persistent session dir for chat, temp dir otherwise
#
# For chat commands, returns early if dir_ref is already set (pre-resolved by
# _resolve_chat_session). Otherwise creates the session directory under the
# XDG-based sessions base. All other command types get a temporary directory
# via _create_context_dir.
#
# Usage: _resolve_context_dir type session_name dir_ref
_resolve_context_dir() {
	local _rcd_type="$1"
	local _rcd_name="$2"
	local -n _rcd_dir="$3"

	if [[ "$_rcd_type" == "chat" ]]; then
		if [[ -n "$_rcd_dir" ]]; then
			return 0
		fi
		local _rcd_base
		_rcd_base=$(_gh_session_base_dir)
		_rcd_dir="${_rcd_base}/${_rcd_name}"
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
	mkdir -p "$(dirname "$dir/$name")"
	printf '%s' "$content" >"$dir/$name"
}

# Shared argument parser for chat commands.
#
# Extracts a numeric resource ID (first positional arg) and -d/--description
# value. Unknown flags produce an error. All internal variables use _pca_
# prefix to avoid nameref collisions.
#
# Usage: _parse_chat_args id_ref desc_ref [args...]
_parse_chat_args() {
	local -n _pca_id="$1"
	local -n _pca_desc="$2"
	shift 2

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
				gum log --level error -- "${_pca_raw[$_pca_i]} requires a value"
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

# Resolve session directory and arguments for chat commands.
#
# Four modes:
#   - user_resume non-empty: dir must exist; chat.id must match resource name;
#     is_new="", args=() (--resume is already in passthrough)
#   - user_session_id non-empty: dir = <base>/<user_session_id>; if dir already
#     exists, is_new="" (skip context); if absent, create dir, write chat.id,
#     is_new=1; args=() in both cases (--session-id is already in passthrough)
#   - GH_CLAUDE_DEFAULT_SESSION_ID set: dir = <base>/<GH_CLAUDE_DEFAULT_SESSION_ID>;
#     if dir exists, is_new="", args=(--resume UUID) — auto-resume;
#     if absent, create dir, write chat.id, is_new=1, args=(--session-id UUID)
#   - Auto-generate: new UUID, create dir, write chat.id, is_new=1,
#     args=(--session-id <UUID>)
#
# Usage: _resolve_chat_session name user_session_id user_resume dir_ref is_new_ref args_ref
_resolve_chat_session() {
	local _rcs_name="$1"
	local _rcs_user_session_id="$2"
	local _rcs_user_resume="$3"
	local -n _rcs_dir="$4"
	local -n _rcs_is_new="$5"
	local -n _rcs_args="$6"

	local _rcs_base
	_rcs_base=$(_gh_session_base_dir)

	if [[ -n "$_rcs_user_resume" ]]; then
		_rcs_dir="${_rcs_base}/${_rcs_user_resume}"
		if [[ ! -d "$_rcs_dir" ]]; then
			gum log --level error "Session not found: ${_rcs_user_resume}"
			return 1
		fi
		local _rcs_stored_name
		_rcs_stored_name=$(cat "$_rcs_dir/chat.id" 2>/dev/null || true)
		if [[ "$_rcs_stored_name" != "$_rcs_name" ]]; then
			gum log --level error "Session ${_rcs_user_resume} belongs to '${_rcs_stored_name}', not '${_rcs_name}'"
			return 1
		fi
		# shellcheck disable=SC2034 # nameref: set by caller
		_rcs_is_new=""
		# shellcheck disable=SC2034 # nameref: set by caller
		_rcs_args=()
	elif [[ -n "$_rcs_user_session_id" ]]; then
		_rcs_dir="${_rcs_base}/${_rcs_user_session_id}"
		if [[ -d "$_rcs_dir" ]]; then
			# shellcheck disable=SC2034 # nameref: set by caller
			_rcs_is_new=""
		else
			mkdir -p "$_rcs_dir"
			printf '%s' "$_rcs_name" >"$_rcs_dir/chat.id"
			# shellcheck disable=SC2034 # nameref: set by caller
			_rcs_is_new=1
		fi
		# shellcheck disable=SC2034 # nameref: set by caller
		_rcs_args=()
	elif [[ -n "${GH_CLAUDE_DEFAULT_SESSION_ID:-}" ]]; then
		_rcs_dir="${_rcs_base}/${GH_CLAUDE_DEFAULT_SESSION_ID}"
		if [[ -d "$_rcs_dir" ]]; then
			# shellcheck disable=SC2034 # nameref: set by caller
			_rcs_is_new=""
			# shellcheck disable=SC2034 # nameref: set by caller
			_rcs_args=(--resume "$GH_CLAUDE_DEFAULT_SESSION_ID")
		else
			mkdir -p "$_rcs_dir"
			printf '%s' "$_rcs_name" >"$_rcs_dir/chat.id"
			# shellcheck disable=SC2034 # nameref: set by caller
			_rcs_is_new=1
			# shellcheck disable=SC2034 # nameref: set by caller
			_rcs_args=(--session-id "$GH_CLAUDE_DEFAULT_SESSION_ID")
		fi
	else
		local _rcs_uuid
		_rcs_uuid=$(_uuidgen)
		if [[ -z "$_rcs_uuid" ]]; then
			gum log --level error "Failed to generate session UUID"
			return 1
		fi
		_rcs_dir="${_rcs_base}/${_rcs_uuid}"
		mkdir -p "$_rcs_dir"
		printf '%s' "$_rcs_name" >"$_rcs_dir/chat.id"
		# shellcheck disable=SC2034 # nameref: set by caller
		_rcs_is_new=1
		# shellcheck disable=SC2034 # nameref: set by caller
		_rcs_args=(--session-id "$_rcs_uuid")
	fi
}


main() {
	local cmd
	cmd="${1:-}"

	case "$cmd" in
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
