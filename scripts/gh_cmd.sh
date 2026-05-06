#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

_gh_cmd_dir=$(dirname "${BASH_SOURCE[0]}")

# Source provider modules
# shellcheck source=scripts/gh_cmd_claude.sh
source "$_gh_cmd_dir/gh_cmd_claude.sh"
# shellcheck source=scripts/gh_cmd_codex.sh
source "$_gh_cmd_dir/gh_cmd_codex.sh"
# shellcheck source=scripts/gh_cmd_gemini.sh
source "$_gh_cmd_dir/gh_cmd_gemini.sh"

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
	printf '%s' "${agent:-ai}"
}

# Resolve the default model for an AI provider
#
# Usage: _get_agent_default_model AGENT
_get_agent_default_model() {
	case "$1" in
	ai | claude)
		_get_claude_default_model
		;;
	codex)
		_get_codex_default_model
		;;
	gemini)
		_get_gemini_default_model
		;;
	*)
		gum log --level error "Unsupported agent '$1' (supported: ai, codex, gemini)"
		return 1
		;;
	esac
}

# Resolve the configured model for a given scope
# Resolves: _GH_AI_ARGS --model → ai.<scope>.model → ai.model → agent default
# Usage: _gh_config_ai_model [SCOPE]   (SCOPE: pr | issue | run | empty)
_gh_config_ai_model() {
	local scope="${1:-}"
	local agent
	agent=$(_get_agent)

	local model=""
	model=$(_extract_ai_arg --model)
	if [[ -z "$model" && -n "$scope" ]]; then
		model=$(gh config get "ai.${scope}.model" 2>/dev/null || true)
	fi
	if [[ -z "$model" ]]; then
		model=$(gh config get ai.model 2>/dev/null || true)
	fi
	if [[ -z "$model" ]]; then
		model=$(_get_agent_default_model "$agent")
	fi
	printf '%s' "${model:-haiku}"
}

# Extract a flag's value from the _GH_AI_ARGS array.
#
# Scans _GH_AI_ARGS for a --flag followed by its value.
# Prints the value to stdout if found; prints nothing otherwise.
#
# Usage: value=$(_extract_ai_arg --model)
_extract_ai_arg() {
	local _eca_flag="$1"
	local _eca_i=0
	while [[ $_eca_i -lt ${#_GH_AI_ARGS[@]} ]]; do
		if [[ "${_GH_AI_ARGS[$_eca_i]}" == "$_eca_flag" ]] && ((_eca_i + 1 < ${#_GH_AI_ARGS[@]})); then
			printf '%s' "${_GH_AI_ARGS[$((_eca_i + 1))]}"
			return 0
		fi
		((++_eca_i))
	done
}

# Send a prompt to the configured AI provider in non-interactive (prompt) mode
#
# Reads a prompt from stdin and sends it to the configured AI provider.
# Uses the given model or falls back to configured model / agent default.
#
# Usage: echo "prompt" | _cmd_ask [MODEL]
_cmd_ask() {
	local agent
	agent=$(_get_agent)

	local agent_model="${1:-}"
	if [[ -z "$agent_model" ]]; then
		agent_model=$(_gh_config_ai_model)
	fi

	case "$agent" in
	ai | claude)
		_ask_ai "$agent_model"
		;;
	codex)
		_ask_codex "$agent_model"
		;;
	gemini)
		_ask_gemini "$agent_model"
		;;
	*)
		gum log --level error "Unsupported agent '$agent' (supported: ai, codex, gemini)"
		return 1
		;;
	esac
}

# Pipe a prompt into the configured AI provider for an interactive session
#
# Verifies the agent binary exists, then pipes the prompt into it.
# Extra positional args are forwarded to the agent.
#
# Usage: _cmd_chat "context prompt" [AGENT_ARGS...]
_cmd_chat() {
	local prompt="$1"
	shift 1

	local agent
	agent=$(_get_agent)

	local binary="$agent"
	[[ "$agent" == "ai" || "$agent" == "claude" ]] && binary="claude"

	# Verify the agent binary exists
	if ! command -v "$binary" &>/dev/null; then
		gum log --level error "$binary not found"
		case "$binary" in
		claude) gum log --level info "Install claude: https://docs.anthropic.com/en/docs/claude-code" ;;
		codex) gum log --level info "Install codex: https://developers.openai.com/codex" ;;
		gemini) gum log --level info "Install gemini: https://github.com/google-gemini/gemini-cli" ;;
		esac
		return 1
	fi

	if [[ -n "$prompt" ]]; then
		printf "%s" "$prompt" | "_chat_$agent" "$@"
	else
		"_chat_$agent" "$@"
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

# Resolve the base directory for persistent chat sessions.
#
# Uses XDG_STATE_HOME if set, otherwise ~/.local/state/gh/ai/sessions.
#
# Stdout: base directory path
# Usage: base=$(_gh_session_base_dir)
_gh_session_base_dir() {
	printf '%s' "${XDG_STATE_HOME:-$HOME/.local/state}/gh/ai/sessions"
}

# Create a temporary context directory for commands
#
# Creates a temp directory that can hold context files. Caller is
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
