#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# Run-related functions for gh-ai

# Parse run explain arguments in a single pass
#
# Extracts the run ID (first numeric arg) via nameref.
#
# Example: _parse_run_explain_args id 123456
_parse_run_explain_args() {
	local -n gh_run_id_ref="$1"
	shift

	local args=("$@")
	local i=0

	while [[ $i -lt ${#args[@]} ]]; do
		local arg="${args[$i]#\#}"
		if [[ -z "$gh_run_id_ref" && "$arg" =~ ^[0-9]+$ ]]; then
			gh_run_id_ref="$arg"
			return 0
		fi
		((++i))
	done
}

# Run chat help function
#
# Displays help information for the run chat command.
_show_run_chat_help() {
	cat <<'EOF'
gh ai run chat - Open a Claude Code debug session for a workflow run

USAGE:
    gh ai run chat <RUN_ID>

DESCRIPTION:
    Generates an AI explanation of the workflow run (via gh ai run explain),
    creates a git worktree on the run's head branch (fast-forwarded),
    and opens a Claude Code session seeded with that explanation.
    Re-running the command resumes the previous session.
    The session is focused on analyzing the failure and helping fix issues.

EXAMPLES:
    gh ai run chat 12345678
EOF
}

# Parse run chat arguments
#
# Extracts the run ID (first positional arg, stripping leading #).
# Unknown flags produce an error.
#
# Example: _parse_run_chat_args id 12345678
_parse_run_chat_args() {
	local -n gh_run_id_ref="$1"
	shift

	local raw_args=("$@")
	local i=0

	while [[ $i -lt ${#raw_args[@]} ]]; do
		case "${raw_args[$i]}" in
		--)
			break
			;;
		-*)
			echo "error: unknown flag '${raw_args[$i]}'" >&2
			return 1
			;;
		*)
			local arg="${raw_args[$i]#\#}"
			if [[ -z "$gh_run_id_ref" && "$arg" =~ ^[0-9]+$ ]]; then
				gh_run_id_ref="$arg"
			else
				echo "error: unexpected argument '${raw_args[$i]}'" >&2
				return 1
			fi
			;;
		esac
		((++i))
	done
}

# Run Chat implementation
#
# Generates an explanation of the workflow run, creates a git worktree on the
# run's head branch (synced to remote), and opens a Claude Code session seeded
# with the explanation for debugging. Re-running resumes the session.
#
# Usage: _gh_run_chat <RUN_ID>
_gh_run_chat() {
	case "${1:-}" in
	--help | -h | help)
		_show_run_chat_help
		return 0
		;;
	esac

	local gh_run_id=""
	_parse_run_chat_args gh_run_id "$@"

	if [[ -z "$gh_run_id" ]]; then
		gum log --level error "No run ID provided"
		gum log --level info "Usage: gh ai run chat <RUN_ID>"
		return 1
	fi

	local repo_name
	_get_repo_name repo_name || return 1

	local git_dir
	_get_git_repo_path git_dir || return 1

	local session_id session_file
	_init_claude_session session_id session_file "$repo_name" "R${gh_run_id}" "$git_dir"

	local remote_branch
	remote_branch=$(gh run view "$gh_run_id" --json headBranch -q '.headBranch' 2>/dev/null || true)
	if [[ -z "$remote_branch" ]]; then
		gum log --level error "Failed to fetch head branch for run $gh_run_id"
		return 1
	fi

	local branch="run-${gh_run_id}"
	# shellcheck disable=SC2154
	local wt_path="$git_dir/.claude/worktrees/${branch}"

	_git_worktree_sync "$branch" "$wt_path" "$remote_branch" "run $gh_run_id" || return 1

	local system_prompt="This is a debug session for GitHub Actions run #${gh_run_id}. Analyze the failure and help fix the issues."

	local agent_model
	agent_model=$(gh config get gh-ai.run.model 2>/dev/null || true)
	if [[ -z "$agent_model" ]]; then
		agent_model=$(gh config get gh-ai.model 2>/dev/null || true)
	fi

	_cmd_chat "$session_file" "$wt_path" "$session_id" "$system_prompt" "$agent_model" \
		gh ai run explain "$gh_run_id"
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
    gh ai run chat <RUN_ID>

DESCRIPTION:
    Analyzes GitHub Actions workflow runs and explains what happened.
    Opens a Claude Code debug session seeded with a run explanation in an isolated worktree.

COMMANDS:
    explain     Analyze a workflow run and explain failures
    chat        Open a Claude Code debug session for a workflow run

SEE ALSO:
    gh ai run explain --help    # Run explain usage
    gh ai run chat --help       # Run chat usage
EOF
}

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

	local args=("$@")

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_ai_source_dir/templates/gh_run_explain.tmpl"

	local gh_run_id=""
	_parse_run_explain_args gh_run_id "${args[@]}"
	if [[ -z "$gh_run_id" ]]; then
		gum log --level error "No run ID provided"
		gum log --level info "Usage: gh ai run explain <RUN_ID>"
		return 1
	fi

	# Fetch run metadata
	local gh_run_eval
	gh_run_eval=$(gum spin --title "Fetching GitHub workflow run #$gh_run_id metadata..." -- \
		gh run view "$gh_run_id" --json displayTitle,conclusion,url,event,headBranch,jobs \
		-q "$(<"$_gh_ai_source_dir/scripts/gh_run_meta.jq")" || true)
	if [[ -z "$gh_run_eval" ]]; then
		gum log --level error "Failed to fetch run $gh_run_id"
		return 1
	fi

	local gh_run_title gh_run_conclusion gh_run_url gh_run_event gh_run_branch gh_run_jobs
	eval "$gh_run_eval"

	# Fetch logs: use --log-failed for failed runs, --log otherwise
	local gh_run_log
	if [[ "$gh_run_conclusion" == "failure" ]]; then
		gh_run_log=$(gum spin --title "Fetching GitHub workflow run #$gh_run_id failed logs..." -- \
			gh run view "$gh_run_id" --log-failed || true)
	else
		gh_run_log=$(gum spin --title "Fetching GitHub workflow run #$gh_run_id logs..." -- \
			gh run view "$gh_run_id" --log || true)
	fi

	# Truncate log to avoid OS ARG_MAX limits when passing via environment variable.
	# GitHub Actions logs can be many MBs; AI context windows are finite anyway.
	local _max_log_bytes=100000
	if [[ ${#gh_run_log} -gt $_max_log_bytes ]]; then
		local _tail
		_tail=$(printf '%s' "$gh_run_log" | tail -c "$_max_log_bytes")
		gh_run_log="[... log truncated, showing last ${_max_log_bytes} bytes ...]"$'\n'"$_tail"
	fi

	local agent_model
	agent_model=$(gh config get gh-ai.run.model 2>/dev/null || true)

	local output
	# Generate explanation using assistant run
	output=$(
		gum spin --title "Analyzing GitHub workflow run #$gh_run_id..." -- \
			"$_gh_ai_source_dir/scripts/gh_cmd.sh" assist "$agent_model" < <(
				GH_RUN_TITLE="$gh_run_title" GH_RUN_CONCLUSION="$gh_run_conclusion" GH_RUN_URL="$gh_run_url" GH_RUN_EVENT="$gh_run_event" GH_RUN_BRANCH="$gh_run_branch" GH_RUN_JOBS="$gh_run_jobs" GH_RUN_LOG="$gh_run_log" \
					"$_gh_ai_source_dir/scripts/gh_cmd.sh" render "$template_file"
			)
	)

	# Validate we got explanation content
	if [[ -z "$output" ]]; then
		gum log --level error "Failed to generate run explanation"
		gum log --level info "Run with DEBUG=1 for detailed diagnostics"
		return 1
	fi

	printf '%s\n' "$output"
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
		exit 1
		;;
	esac
}
