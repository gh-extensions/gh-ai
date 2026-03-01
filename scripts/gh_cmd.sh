#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

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
# (GH_PR_DIFF, GH_ISSUE_*, etc.) that do not overlap with standard shell variables.
#
# Usage: MY_VAR="value" _cmd_render template.tmpl
# Usage: GH_PR_DIFF_FILE="/tmp/diff.patch" _cmd_render template.tmpl
_cmd_render() {
	local template_file="$1"

	if [[ ! -f "$template_file" ]]; then
		gum log --level error "Template not found: $template_file"
		return 1
	fi

	awk '
	function readfile(path,    content, line, cmd) {
		content = ""
		cmd = "cat " path
		while ((cmd | getline line) > 0) {
			if (content != "") content = content "\n"
			content = content line
		}
		close(cmd)
		return content
	}
	{ content = content $0 "\n" }
	END {
		result = ""; remaining = content
		while (match(remaining, /\$\{[A-Z_][A-Z0-9_]*\}/)) {
			varname = substr(remaining, RSTART+2, RLENGTH-3)
			val = ENVIRON[varname]
			if (val == "" && ENVIRON[varname "_FILE"] != "") {
				val = readfile(ENVIRON[varname "_FILE"])
			}
			result = result substr(remaining, 1, RSTART-1) val
			remaining = substr(remaining, RSTART+RLENGTH)
		}
		printf "%s%s", result, remaining
	}' "$template_file"
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

# Pipe a preamble into the configured agent binary
#
# Resolves ai.agent (default: claude), verifies the binary exists, then
# pipes the preamble into it. Automatically injects --settings pointing to
# the extension's scripts/gh_claude.json. Extra positional args are forwarded
# to the agent.
#
# Usage: _cmd_chat "context preamble" [AGENT_ARGS...]
_cmd_chat() {
	local preamble="$1"
	shift

	# Drop --from-pr; it conflicts with gh-ai's own session management
	local args=()
	local skip_next=false
	for arg in "$@"; do
		if [[ "$skip_next" == true ]]; then
			skip_next=false
			continue
		fi
		case "$arg" in
		--from-pr)
			gum log --level warn "--from-pr is not compatible with gh-ai session management; ignoring"
			skip_next=true
			continue
			;;
		--from-pr=*)
			gum log --level warn "--from-pr is not compatible with gh-ai session management; ignoring"
			continue
			;;
		esac
		args+=("$arg")
	done

	local agent
	agent=$(_get_agent)
	if ! command -v "$agent" &>/dev/null; then
		gum log --level error "Agent '$agent' not found"
		gum log --level info "Install it or set: gh config set ai.agent <binary>"
		return 1
	fi
	# shellcheck disable=SC2154
	export _GH_AI_SOURCE_DIR="$_gh_ai_source_dir"
	local settings_file="$_gh_ai_source_dir/scripts/gh_claude.json"
	printf '%s\n' "$preamble" | "$agent" --settings "$settings_file" "${args[@]}"
}

# Extract title from AI response
#
# Gets the title from AI-generated content by taking the first line
# and removing any markdown heading prefix (#).
#
# Example: _parse_title "# Fix bug in parser\n\nDescription..."
# Returns: "Fix bug in parser"
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
	_cdir_ref=$(mktemp -d "${TMPDIR:-/tmp}/gh-ai-ctx.XXXXXXXXXX")
}

# Save content to a named file in a context directory
#
# Writes content to a file using printf builtin (no execve, so no ARG_MAX impact).
#
# Usage: _save_context_file "/path/to/context/dir" "filename" "content"
_save_context_file() {
	local dir="$1" name="$2" content="$3"
	printf '%s' "$content" > "$dir/$name"
}

# Generate a UUIDv5 from a name using the NAMESPACE_URL (RFC 4122)
#
# Pure bash implementation — uses printf for the 16-byte NAMESPACE_URL raw
# bytes and shasum -a 1 (both ship with macOS/Linux).
#
# Usage: _uuidv5 "https://github.com/owner/repo/issues/42"
_uuidv5() {
	local name="$1"
	local hash
	hash=$({
		printf '\x6b\xa7\xb8\x11\x9d\xad\x11\xd1\x80\xb4\x00\xc0\x4f\xd4\x30\xc8'
		printf '%s' "$name"
	} | shasum -a 1 | cut -d' ' -f1)
	local h="${hash:0:32}"
	local byte6 byte8
	byte6=$(printf '%02x' $((0x${h:12:2} & 0x0f | 0x50)))
	byte8=$(printf '%02x' $((0x${h:16:2} & 0x3f | 0x80)))
	printf '%s-%s-%s%s-%s%s-%s\n' \
		"${h:0:8}" "${h:8:4}" "$byte6" "${h:14:2}" "$byte8" "${h:18:2}" "${h:20:12}"
}

# Resolve session state: validate inputs, compute IDs, and locate state file
#
# Shared helper for _try_resume_chat_session and _resolve_chat_session.
# Validates the resource URL, checks passthrough for user session flags,
# generates a deterministic session ID, derives the worktree name, resolves
# the git root, computes the state file path, and handles --new-session deletion.
#
# Returns 1 (skip) when URL is empty, user passed session flags, or git root
# is unavailable.  On success, populates the three namerefs and returns 0.
#
# Usage: _resolve_session_state sid_ref name_ref path_ref "$url" "$new_session" "${passthrough[@]}"
_resolve_session_state() {
	local -n _ss_sid="$1" _ss_name="$2" _ss_path="$3"
	local resource_url="$4"
	local new_session="$5"
	shift 5

	if [[ -z "$resource_url" ]]; then
		return 1
	fi

	local arg
	for arg in "$@"; do
		case "$arg" in
		--resume | --resume=* | --session-id | --session-id=* | --continue | -c)
			return 1
			;;
		esac
	done

	_ss_sid=$(_uuidv5 "$resource_url")

	# Derive worktree name from last two URL path segments (e.g. "issues/42" → "issue-42")
	_ss_name=$(printf '%s' "$resource_url" | awk -F/ '{sub(/s$/, "", $(NF-1)); print $(NF-1) "-" $NF}')

	local git_root
	_git_repo_path git_root || return 1

	_ss_path="$git_root/.claude/sessions/$_ss_sid"

	if [[ -n "$new_session" ]]; then
		# Clean up both old .json format and new directory format
		rm -f "${_ss_path}.json"
		rm -rf "$_ss_path"
	fi
}

# Try to resume an existing chat session
#
# Checks if a session state file exists for the given resource URL and
# populates session arguments for resumption. Does NOT create new sessions.
# When new_session is non-empty, deletes the existing state file before checking.
# Returns 0 if session can be resumed, 1 if a new session is needed.
#
# Usage: _try_resume_chat_session session_args_ref "https://github.com/..." "$new_session" "${passthrough[@]}"
_try_resume_chat_session() {
	local -n _session_args_ref="$1"
	local resource_url="$2"
	local new_session="$3"
	shift 3

	_session_args_ref=()

	local session_id="" name="" state_file=""
	_resolve_session_state session_id name state_file "$resource_url" "$new_session" "$@" || return 1

	# Check for new directory format first, then fall back to old .json format
	if [[ -d "$state_file" && -f "$state_file/state.json" ]] || [[ -f "${state_file}.json" ]]; then
		_session_args_ref=(--resume "$session_id" --worktree "$name")
		return 0
	fi

	return 1
}

# Resolve session arguments for chat commands
#
# Manages session state files for chat session persistence. On first run,
# creates a state file with the session ID, worktree name, and remote ref,
# then returns --session-id + --worktree. On subsequent runs, returns
# --resume + --worktree. When new_session is non-empty, deletes the existing
# state file first. Silently skips when the URL is empty, the user passed
# their own session flags, or the git root is unavailable.
#
# The remote_ref parameter specifies which branch to track in the worktree
# (e.g. the PR head branch). When empty, defaults to the repository's
# default branch via origin/HEAD.
#
# Usage: _resolve_chat_session session_args_ref "https://github.com/owner/repo/issues/42" "$new_session" "$remote_ref" "${passthrough[@]}"
_resolve_chat_session() {
	local -n _session_args_ref="$1"
	local resource_url="$2"
	local new_session="$3"
	local remote_ref="$4"
	shift 4

	_session_args_ref=()

	local session_id="" name="" state_file=""
	_resolve_session_state session_id name state_file "$resource_url" "$new_session" "$@" || return 0

	# Create session directory
	mkdir -p "$state_file"

	local state_json="$state_file/state.json"

	# Check both new and old formats for existing session
	if [[ -f "$state_json" ]] || [[ -f "${state_file}.json" ]]; then
		_session_args_ref=(--resume "$session_id" --worktree "$name")
	else
		# Default to the repository's default branch when no remote ref is provided
		if [[ -z "$remote_ref" ]]; then
			remote_ref=$(git rev-parse --abbrev-ref origin/HEAD 2>/dev/null | sed 's|origin/||')
			remote_ref="${remote_ref:-main}"
		fi
		jq -n --arg session_id "$session_id" --arg name "$name" --arg remote_ref "$remote_ref" \
			'{session_id: $session_id, name: $name, remote_ref: $remote_ref}' >"$state_json"
		_session_args_ref=(--session-id "$session_id" --worktree "$name")
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
