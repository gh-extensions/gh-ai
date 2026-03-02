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

	local raw_args=("$@")
	local i=0

	while [[ $i -lt ${#raw_args[@]} ]]; do
		case "${raw_args[$i]}" in
		--)
			break
			;;
		-*)
			gum log --level error "unknown flag '${raw_args[$i]}'"
			return 1
			;;
		*)
			local arg="${raw_args[$i]#\#}"
			if [[ -z "$gh_run_id_ref" && "$arg" =~ ^[0-9]+$ ]]; then
				gh_run_id_ref="$arg"
			else
				gum log --level error "unexpected argument '${raw_args[$i]}'"
				return 1
			fi
			;;
		esac
		((++i))
	done
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
    gh ai run chat <RUN_ID> [-d <DESCRIPTION>] [-- AGENT_OPTIONS]

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

	# Fetch run metadata
	local gh_run_eval
	gh_run_eval=$(gum spin --title "Fetching GitHub workflow run #$gh_run_id metadata..." -- \
		gh run view "$gh_run_id" --json displayTitle,conclusion,url,event,headBranch,jobs \
		-q "$(<"$_gh_ai_source_dir/scripts/gh_run_meta.jq")" || true)
	if [[ -z "$gh_run_eval" ]]; then
		gum log --level error "Failed to fetch run #$gh_run_id"
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

	local agent_model
	agent_model=$(gh config get ai.run.model 2>/dev/null || true)

	# Create context directory and save large content to files (no truncation needed)
	local context_dir
	_create_context_dir context_dir
	_save_context_file "$context_dir" "run_jobs.txt" "$gh_run_jobs"
	_save_context_file "$context_dir" "run_log.txt" "$gh_run_log"

	local output
	# Generate explanation using assistant run
	output=$(
		gum spin --title "Analyzing GitHub workflow run #$gh_run_id..." -- \
			"$_gh_ai_source_dir/scripts/gh_cmd.sh" ask "$agent_model" < <(
				GH_RUN_TITLE="$gh_run_title" \
					GH_RUN_CONCLUSION="$gh_run_conclusion" \
					GH_RUN_URL="$gh_run_url" \
					GH_RUN_EVENT="$gh_run_event" \
					GH_RUN_BRANCH="$gh_run_branch" \
					GH_RUN_JOBS_FILE="$context_dir/run_jobs.txt" \
					GH_RUN_LOG_FILE="$context_dir/run_log.txt" \
					"$_gh_ai_source_dir/scripts/gh_cmd.sh" render "$template_file"
			)
	)

	# Clean up temp context directory
	rm -rf "$context_dir"

	# Validate we got explanation content
	if [[ -z "$output" ]]; then
		gum log --level error "Failed to generate run explanation"
		gum log --level info "Run with DEBUG=1 for detailed diagnostics"
		return 1
	fi

	printf '%s\n' "$output"
}

# Parse run chat arguments
#
# Extracts the run ID (first numeric arg), optional -d/--description value,
# and -n/--new-session flag. Unknown flags produce an error.
#
# Example: _parse_run_chat_args id desc new_session 123456 -d "focus on test failures"
_parse_run_chat_args() {
	local -n gh_run_id_ref="$1"
	local -n gh_run_description_ref="$2"
	local -n gh_run_new_session_ref="$3"
	shift 3

	local raw_args=("$@")
	local skip_next=false
	local i=0

	while [[ $i -lt ${#raw_args[@]} ]]; do
		if [ "$skip_next" = true ]; then
			skip_next=false
			((++i))
			continue
		fi

		case "${raw_args[$i]}" in
		--description | -d)
			if ((i + 1 >= ${#raw_args[@]})); then
				gum log --level error "${raw_args[$i]} requires a value"
				return 1
			fi
			gh_run_description_ref="${raw_args[$((i + 1))]}"
			skip_next=true
			;;
		--description=*)
			# shellcheck disable=SC2034 # nameref: set by caller
			gh_run_description_ref="${raw_args[$i]#--description=}"
			;;
		--new-session | -n)
			# shellcheck disable=SC2034 # nameref: set by caller
			gh_run_new_session_ref=1
			;;
		-*)
			gum log --level error "unknown flag '${raw_args[$i]}' (use -- to pass flags to the agent)"
			return 1
			;;
		*)
			local arg="${raw_args[$i]#\#}"
			if [[ -z "$gh_run_id_ref" && "$arg" =~ ^[0-9]+$ ]]; then
				gh_run_id_ref="$arg"
			else
				gum log --level error "unexpected argument '${raw_args[$i]}'"
				return 1
			fi
			;;
		esac
		((++i))
	done
}

# Run chat help function
#
# Displays help information for the run chat command
# including usage examples and available options.
_show_run_chat_help() {
	cat <<'EOF'
gh ai run chat - Open an agent session with workflow run context

USAGE:
    gh ai run chat <RUN_ID> [-d <DESCRIPTION>] [-- AGENT_OPTIONS]

DESCRIPTION:
    Fetches the GitHub Actions workflow run metadata and logs, renders
    it as context, and pipes it into the configured agent binary
    (default: claude). Options after -- are passed directly to the agent.

    Configure the agent: gh config set ai.agent <binary>

FLAGS:
    -d, --description string   Extra context or focus for the agent (optional)
    -n, --new-session          Start a new session

EXAMPLES:
    gh ai run chat 123456
    gh ai run chat 123456 -d "focus on test failures"
    gh ai run chat 123456 --new-session
    gh ai run chat 123456 -- --model sonnet
EOF
}

# Run Chat implementation
#
# Fetches a GitHub Actions workflow run's metadata and logs, renders the
# context template, and pipes it into the configured agent binary.
#
# Usage: _gh_run_chat <RUN_ID> [-d <DESCRIPTION>] [-- AGENT_OPTIONS]
_gh_run_chat() {
	case "${1:-}" in
	--help | -h | help)
		_show_run_chat_help
		return 0
		;;
	esac

	local ai_args=()
	local passthrough=()
	_split_on_separator ai_args passthrough "$@"

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_ai_source_dir/templates/gh_run_chat.tmpl"

	local gh_run_id=""
	local gh_run_description=""
	local gh_run_new_session=""
	_parse_run_chat_args gh_run_id gh_run_description gh_run_new_session "${ai_args[@]}"

	if [[ -z "$gh_run_id" ]]; then
		gum log --level error "No run ID provided"
		gum log --level info "Usage: gh ai run chat <RUN_ID> [-d <DESCRIPTION>] [-- AGENT_OPTIONS]"
		return 1
	fi

	# Try to resume existing session before expensive API calls
	local gh_repo=""
	_gh_repo_name gh_repo || return 1
	local gh_run_url="https://github.com/${gh_repo}/actions/runs/${gh_run_id}"

	local session_args=()
	if _try_resume_chat_session session_args "$gh_run_url" "$gh_run_new_session" "${passthrough[@]}"; then
		_cmd_chat "" "${session_args[@]}" "${passthrough[@]}"
		return
	fi

	# Fetch run metadata
	local gh_run_eval
	gh_run_eval=$(gum spin --title "Fetching GitHub workflow run #$gh_run_id metadata..." -- \
		gh run view "$gh_run_id" --json displayTitle,conclusion,url,event,headBranch,headSha,jobs \
		-q "$(<"$_gh_ai_source_dir/scripts/gh_run_meta.jq")" || true)
	if [[ -z "$gh_run_eval" ]]; then
		gum log --level error "Failed to fetch run #$gh_run_id"
		return 1
	fi

	local gh_run_title gh_run_conclusion gh_run_event gh_run_branch gh_run_sha gh_run_jobs
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
	if [[ -z "$gh_run_log" ]]; then
		gum log --level error "No logs available for run #$gh_run_id"
		gum log --level info "Logs may still be streaming, have expired, or the run may not have started yet"
		return 1
	fi

	local gh_run_focus=""
	if [[ -n "$gh_run_description" ]]; then
		gh_run_focus="<focus>${gh_run_description}</focus>"
	fi

	# Capture current branch for template context
	local gh_current_branch
	gh_current_branch=$(git branch --show-current 2>/dev/null || echo "")

	# Compute session directory path for preamble and context files
	local session_id session_dir
	session_id=$(_uuidv5 "$gh_run_url")
	local git_root
	_git_repo_path git_root || return 1
	session_dir="$git_root/.claude/sessions/$session_id"

	# Render context — session_dir path is embedded as a string;
	# files are written after _resolve_chat_session creates the directory.
	local preamble
	preamble=$(
		GH_RUN_ID="$gh_run_id" \
			GH_RUN_TITLE="$gh_run_title" \
			GH_RUN_CONCLUSION="$gh_run_conclusion" \
			GH_RUN_FOCUS="$gh_run_focus" \
			GH_RUN_URL="$gh_run_url" \
			GH_RUN_EVENT="$gh_run_event" \
			GH_RUN_BRANCH="$gh_run_branch" \
			GH_CURRENT_BRANCH="$gh_current_branch" \
			GH_SESSION_DIR="$session_dir" \
			"$_gh_ai_source_dir/scripts/gh_cmd.sh" render "$template_file"
	)

	session_args=()
	_resolve_chat_session session_args "$gh_run_url" "$gh_run_new_session" "$gh_run_branch" "" "$gh_run_sha" "${passthrough[@]}"

	# Save context files after _resolve_chat_session has created (or recreated)
	# the session directory — this ensures --new-session doesn't wipe them.
	_save_context_file "$session_dir" "run_jobs.txt" "$gh_run_jobs"
	_save_context_file "$session_dir" "run_log.txt" "$gh_run_log"

	_cmd_chat "$preamble" "${session_args[@]}" "${passthrough[@]}"
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
