#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# Run-related functions for gh-ai

# Shared context helper for run commands.
#
# Fetches workflow run metadata and logs, saves context files to the run
# directory, and populates the output variables via namerefs.
#
# When type is "chat" the context is written to the persistent session directory
# .claude/sessions/run-<id> so Claude can resume across invocations.
# For all other types a temporary directory is created.
#
# Usage: _prepare_run_context type run_id dir_ref title_ref conclusion_ref url_ref event_ref branch_ref sha_ref
_prepare_run_context() {
	local _ctx_type="$1"
	local _ctx_id="$2"
	local -n _ctx_dir="$3"
	local -n _ctx_title="$4"
	local -n _ctx_conclusion="$5"
	local -n _ctx_url="$6"
	local -n _ctx_event="$7"
	local -n _ctx_branch="$8"
	local -n _ctx_head_sha="$9"

	local _ctx_meta
	_ctx_meta=$(gum spin --title "Fetching GitHub workflow run #$_ctx_id metadata..." -- \
		gh run view "$_ctx_id" --json displayTitle,conclusion,url,event,headBranch,headSha,jobs || true)
	if [[ -z "$_ctx_meta" ]]; then
		gum log --level error "Failed to fetch run #$_ctx_id"
		return 1
	fi

	_ctx_title=$(printf '%s' "$_ctx_meta" | jq -r '.displayTitle // empty')
	_ctx_conclusion=$(printf '%s' "$_ctx_meta" | jq -r '.conclusion // empty')
	_ctx_url=$(printf '%s' "$_ctx_meta" | jq -r '.url // empty')
	_ctx_event=$(printf '%s' "$_ctx_meta" | jq -r '.event // empty')
	_ctx_branch=$(printf '%s' "$_ctx_meta" | jq -r '.headBranch // empty')
	_ctx_head_sha=$(printf '%s' "$_ctx_meta" | jq -r '.headSha // empty')

	local _ctx_jobs
	# shellcheck disable=SC2154
	_ctx_jobs=$(printf '%s' "$_ctx_meta" | jq -rf "$_gh_ai_source_dir/scripts/gh_run_jobs.jq")

	local _ctx_log
	if [[ "$_ctx_conclusion" == "failure" ]]; then
		_ctx_log=$(gum spin --title "Fetching GitHub workflow run #$_ctx_id failed logs..." -- \
			gh run view "$_ctx_id" --log-failed || true)
	else
		_ctx_log=$(gum spin --title "Fetching GitHub workflow run #$_ctx_id logs..." -- \
			gh run view "$_ctx_id" --log || true)
	fi

	if [[ -z "$_ctx_log" ]]; then
		gum log --level error "No logs available for run #$_ctx_id"
		gum log --level info "Logs may still be streaming, have expired, or the run may not have started yet"
		return 1
	fi

	_resolve_context_dir "$_ctx_type" "run-$_ctx_id" _ctx_dir || return 1

	_save_context_file "$_ctx_dir" "run_jobs.txt" "$_ctx_jobs"
	_save_context_file "$_ctx_dir" "run_log.txt" "$_ctx_log"
}

# Shared argument parser for run commands that accept only a run ID.
#
# Extracts the run ID (first numeric arg) via nameref. Unknown flags produce
# an error. All internal variables use _pra_ prefix to avoid nameref collisions.
#
# Usage: _parse_run_args id_ref [args...]
_parse_run_args() {
	local -n _pra_id="$1"
	shift

	local _pra_raw=("$@")
	local _pra_i=0

	while [[ $_pra_i -lt ${#_pra_raw[@]} ]]; do
		case "${_pra_raw[$_pra_i]}" in
		-*)
			gum log --level error "unknown flag '${_pra_raw[$_pra_i]}'"
			return 1
			;;
		*)
			local _pra_arg="${_pra_raw[$_pra_i]#\#}"
			if [[ -z "$_pra_id" && "$_pra_arg" =~ ^[0-9]+$ ]]; then
				_pra_id="$_pra_arg"
			else
				gum log --level error "unexpected argument '${_pra_raw[$_pra_i]}'"
				return 1
			fi
			;;
		esac
		((++_pra_i))
	done
}

# Thin wrapper around _parse_run_args for the explain subcommand.
_parse_run_explain_args() { _parse_run_args "$@"; }

# Fetches run metadata and logs into a temp directory for use by _gh_run_explain.
_prepare_run_explain_context() { _prepare_run_context "explain" "$@"; }

# Run explain help function
#
# Displays help information for the run explain command
# including usage examples and available options.
_show_run_explain_help() {
	cat <<'EOF'
gh ai run explain - Analyze a workflow run and explain failures

USAGE:
    gh ai run explain <RUN_ID>

DESCRIPTION:
    Analyzes a GitHub Actions workflow run and generates an AI explanation
    of what happened, focusing on root cause and actionable fixes.
    Uses --log-failed for failed runs and --log otherwise.

EXAMPLES:
    gh ai run explain 123456
EOF
}

# Run Explain implementation
#
# Analyzes a GitHub Actions workflow run and generates an AI explanation
# of what happened, focusing on root cause and actionable fixes.
# Prints the explanation to stdout.
#
# Usage: _gh_run_explain <RUN_ID>
_gh_run_explain() {
	case "${1:-}" in
	--help | -h | help)
		_show_run_explain_help
		return 0
		;;
	esac

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_ai_source_dir/templates/gh_run_explain.tmpl"

	local gh_run_id=""
	_parse_run_explain_args gh_run_id "$@"

	if [[ -z "$gh_run_id" ]]; then
		gum log --level error "No run ID provided"
		gum log --level info "Usage: gh ai run explain <RUN_ID>"
		return 1
	fi

	local gh_run_dir="" gh_run_title="" gh_run_conclusion="" gh_run_url="" gh_run_event="" gh_run_branch="" gh_run_sha=""
	_prepare_run_explain_context "$gh_run_id" gh_run_dir gh_run_title gh_run_conclusion gh_run_url gh_run_event gh_run_branch gh_run_sha || return 1

	local gh_run_agent_model
	gh_run_agent_model=$(gh config get ai.run.model 2>/dev/null || true)

	local gh_run_explain
	# Generate explanation using assistant run
	# *_FILE vars are read by 'gh_cmd.sh render' and inlined as their non-FILE counterparts.
	gh_run_explain=$(
		gum spin --title "Analyzing GitHub workflow run #$gh_run_id..." -- \
			"$_gh_ai_source_dir/scripts/gh_cmd.sh" ask "$gh_run_agent_model" < <(
				GH_RUN_TITLE="$gh_run_title" \
					GH_RUN_CONCLUSION="$gh_run_conclusion" \
					GH_RUN_URL="$gh_run_url" \
					GH_RUN_EVENT="$gh_run_event" \
					GH_RUN_BRANCH="$gh_run_branch" \
					GH_RUN_SHA="$gh_run_sha" \
					GH_RUN_JOBS_FILE="$gh_run_dir/run_jobs.txt" \
					GH_RUN_LOG_FILE="$gh_run_dir/run_log.txt" \
					"$_gh_ai_source_dir/scripts/gh_cmd.sh" render "$template_file"
			)
	)

	# Clean up the temp context directory now that the AI call is done.
	rm -rf "$gh_run_dir"

	# Validate we got explanation content
	if [[ -z "$gh_run_explain" ]]; then
		gum log --level error "Failed to generate run explanation"
		gum log --level info "Run with DEBUG=1 for detailed diagnostics"
		return 1
	fi

	printf '%s\n' "$gh_run_explain"
}

# Thin wrapper around _parse_chat_args for the chat subcommand.
_parse_run_chat_args() { _parse_chat_args "$@"; }

# Fetches run metadata and logs into .claude/sessions/run-<id> for use by _gh_run_chat.
# The session directory persists across invocations so Claude can resume context.
# _resolve_chat_session tracks the Claude session UUID separately via a
# "session.id" file written inside the session directory.
_prepare_run_chat_context() { _prepare_run_context "chat" "$@"; }

# Run chat help function
#
# Displays help information for the run chat command
# including usage examples and available options.
_show_run_chat_help() {
	cat <<'EOF'
gh ai run chat - Open an agent session with workflow run context

USAGE:
    gh ai run chat <RUN_ID> [-d <DESCRIPTION>] [-n]

DESCRIPTION:
    Fetches the GitHub Actions workflow run metadata and logs, renders
    it as context, and pipes it into the configured agent binary
    (default: claude).

    Configure the agent: gh config set ai.agent <binary>
    Configure the model: gh config set ai.run.model <model>

FLAGS:
    -d, --description string   Extra context or focus for the agent (optional)
    -n, --new-session          Start a new session

EXAMPLES:
    gh ai run chat 123456
    gh ai run chat 123456 -d "focus on test failures"
    gh ai run chat 123456 --new-session
EOF
}

# Run Chat implementation
#
# Fetches a GitHub Actions workflow run's metadata and logs, renders the
# context template, and pipes it into the configured agent binary.
# Session continuity is managed via _resolve_chat_session — subsequent
# invocations resume the previous session automatically; --new-session
# forces a fresh session ID.
#
# Usage: _gh_run_chat <RUN_ID> [-d <DESCRIPTION>] [-n]
_gh_run_chat() {
	case "${1:-}" in
	--help | -h | help)
		_show_run_chat_help
		return 0
		;;
	esac

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_ai_source_dir/templates/gh_run_chat.tmpl"

	local gh_run_id="" gh_run_description="" gh_run_new_session=""
	_parse_run_chat_args gh_run_id gh_run_description gh_run_new_session "$@"

	if [[ -z "$gh_run_id" ]]; then
		gum log --level error "No run ID provided"
		gum log --level info "Usage: gh ai run chat <RUN_ID> [-d <DESCRIPTION>] [-n]"
		return 1
	fi

	local gh_run_focus=""
	if [[ -n "$gh_run_description" ]]; then
		gh_run_focus="<focus>${gh_run_description}</focus>"
	fi

	local gh_run_dir="" gh_run_title="" gh_run_conclusion="" gh_run_url="" gh_run_event="" gh_run_branch="" gh_run_sha=""
	_prepare_run_chat_context "$gh_run_id" gh_run_dir gh_run_title gh_run_conclusion gh_run_url gh_run_event gh_run_branch gh_run_sha || return 1

	local gh_run_worktree
	gh_run_worktree="run-$gh_run_id"
	_save_worktree_state "$gh_run_dir" "$gh_run_worktree" "$gh_run_branch" "$gh_run_sha"

	local gh_run_is_new_chat="" gh_run_session_args=()
	_resolve_chat_session "$gh_run_dir" "$gh_run_new_session" gh_run_is_new_chat gh_run_session_args || return 1

	local gh_run_preamble=""
	if [[ -n "$gh_run_is_new_chat" ]]; then
		gh_run_preamble=$(
			GH_RUN_ID="$gh_run_id" \
				GH_RUN_TITLE="$gh_run_title" \
				GH_RUN_CONCLUSION="$gh_run_conclusion" \
				GH_RUN_FOCUS="$gh_run_focus" \
				GH_RUN_URL="$gh_run_url" \
				GH_RUN_EVENT="$gh_run_event" \
				GH_RUN_BRANCH="$gh_run_branch" \
				GH_RUN_SHA="$gh_run_sha" \
				GH_WT_BRANCH="$gh_run_worktree" \
				GH_SESSION_DIR="$gh_run_dir" \
				"$_gh_ai_source_dir/scripts/gh_cmd.sh" render "$template_file"
		)
	fi

	_cmd_chat "$gh_run_preamble" --worktree "$gh_run_worktree" "${gh_run_session_args[@]}"
}

# Run help function
#
# Displays comprehensive help information for all run subcommands
# including usage examples and available options.
_show_run_help() {
	cat <<'EOF'
gh ai run - Workflow run commands with AI assistance

USAGE:
    gh ai run explain <RUN_ID>
    gh ai run chat <RUN_ID> [-d <DESCRIPTION>] [-n]

DESCRIPTION:
    Analyzes GitHub Actions workflow runs and explains what happened.
    Opens agent sessions with run context.

COMMANDS:
    explain     Analyze a workflow run and explain failures
    chat        Open an agent session with workflow run context

SEE ALSO:
    gh ai run explain --help    # Run explain usage
    gh ai run chat --help       # Run chat usage
EOF
}

# Run subcommand handler
#
# Routes run subcommands to their appropriate handler functions.
# Shows help for unknown commands.
#
# Usage: _gh_run <subcommand> [OPTIONS]
# Subcommands: explain, chat, help
_gh_run() {
	local subcommand="${1:-}"
	shift || true

	case $subcommand in
	explain)
		_gh_run_explain "$@"
		;;
	chat)
		_gh_run_chat "$@"
		;;
	--help | -h | help | "")
		_show_run_help
		;;
	*)
		gum log --level error "Unknown run command '$subcommand'"
		gum log --level info "Available commands: explain, chat"
		gum log --level info "Run 'gh ai run --help' for usage information"
		return 1
		;;
	esac
}
