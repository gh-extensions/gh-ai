#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# Run-related functions for gh-ai

# Extract run ID from arguments
#
# Looks for the first numeric argument in the provided args.
# Returns the run ID or empty string if none found.
#
# Example: _get_run_id explain 123456  # Returns: 123456
_get_run_id() {
	local args=("$@")
	local i=0

	while [[ $i -lt ${#args[@]} ]]; do
		if [[ "${args[$i]}" =~ ^[0-9]+$ ]]; then
			echo "${args[$i]}"
			return 0
		fi
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

DESCRIPTION:
    Analyzes GitHub Actions workflow runs and explains what happened.

COMMANDS:
    explain     Analyze a workflow run and explain failures

SEE ALSO:
    gh ai run explain --help    # Run explain usage
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
	local args=("$@")

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_ai_source_dir/templates/gh_run_explain.tmpl"

	local gh_run_id
	gh_run_id=$(_get_run_id "${args[@]}")
	if [[ -z "$gh_run_id" ]]; then
		gum log --level error "No run ID provided"
		gum log --level info "Usage: gh ai run explain <RUN_ID>"
		return 1
	fi

	# Fetch run metadata
	local gh_run_json
	gh_run_json=$(gum spin --title "Fetching GitHub workflow run metadata..." -- \
		gh run view "$gh_run_id" --json displayTitle,conclusion,url,event,headBranch,jobs || true)
	if [[ -z "$gh_run_json" ]]; then
		gum log --level error "Failed to fetch run $gh_run_id"
		return 1
	fi

	local gh_run_title
	gh_run_title=$(echo "$gh_run_json" | jq -r '.displayTitle // ""')

	local gh_run_conclusion
	gh_run_conclusion=$(echo "$gh_run_json" | jq -r '.conclusion // ""')

	local gh_run_url
	gh_run_url=$(echo "$gh_run_json" | jq -r '.url // ""')

	local gh_run_event
	gh_run_event=$(echo "$gh_run_json" | jq -r '.event // ""')

	local gh_run_branch
	gh_run_branch=$(echo "$gh_run_json" | jq -r '.headBranch // ""')

	local gh_run_jq_file
	gh_run_jq_file="$_gh_ai_source_dir/scripts/gh_run_explain.jq"

	local gh_run_jobs
	gh_run_jobs=$(echo "$gh_run_json" | jq -r -f "$gh_run_jq_file")

	# Fetch logs: use --log-failed for failed runs, --log otherwise
	local gh_run_log
	if [[ "$gh_run_conclusion" == "failure" ]]; then
		gh_run_log=$(gum spin --title "Fetching GitHub workflow run failed logs..." -- \
			gh run view "$gh_run_id" --log-failed || true)
	else
		gh_run_log=$(gum spin --title "Fetching GitHub workflow run logs..." -- \
			gh run view "$gh_run_id" --log || true)
	fi

	# Truncate to last 500 lines to keep prompt size reasonable
	gh_run_log=$(echo "$gh_run_log" | tail -n 500)

	local agent_model
	agent_model=$(gh config get gh-ai.run.model 2>/dev/null || true)

	local output
	# Generate explanation using assistant run
	output=$(
		gum spin --title "Analyzing GitHub workflow run..." -- \
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
# Subcommands: explain, help
_gh_run() {
	local subcommand="${1:-}"
	shift || true

	case $subcommand in
	explain)
		_gh_run_explain "$@"
		;;
	--help | -h | help | "")
		_show_run_help
		;;
	*)
		gum log --level error "Unknown run command '$subcommand'"
		gum log --level info "Available commands: explain"
		gum log --level info "Run 'gh ai run --help' for usage information"
		exit 1
		;;
	esac
}
