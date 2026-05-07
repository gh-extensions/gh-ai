#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# shellcheck source=gh_cmd.sh
source "$(dirname "${BASH_SOURCE[0]}")/gh_cmd.sh"

# Run-related functions for gh-ai

# Shared context helper for run commands.
#
# Fetches workflow run metadata and logs, saves context files to the run
# directory, and populates the output variables via namerefs.
#
# When type is "chat" the context is written to the pre-resolved session
# directory (set by _resolve_chat_session before this is called).
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

	_resolve_context_dir "$_ctx_type" "run-$_ctx_id" _ctx_dir || return 1

	local _ctx_meta
	_ctx_meta=$(gum spin --title "Fetching GitHub workflow run #$_ctx_id metadata..." -- \
		gh run view "$_ctx_id" --json displayTitle,conclusion,url,event,headBranch,headSha,jobs || true)
	if [[ -z "$_ctx_meta" ]]; then
		gum log --level error "Failed to fetch run #$_ctx_id"
		return 1
	fi

	# Single jq pass: extract all fields via eval
	local _ctx_jobs=""
	# shellcheck disable=SC2154
	eval "$(printf '%s' "$_ctx_meta" | jq -rf "$_gh_ai_source_dir/queries/gh_run_meta.jq")"

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

	_save_context_file "$_ctx_dir" "state/run_jobs.txt" "$_ctx_jobs"
	_save_context_file "$_ctx_dir" "state/run_log.txt" "$_ctx_log"
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

# Thin wrapper around _parse_analyze_args for the analyze subcommand.
_parse_run_analyze_args() { _parse_analyze_args "$@"; }

# Fetches run metadata and logs into the persistent session directory for _gh_run_analyze.
_prepare_run_analyze_context() { _prepare_run_context "analyze" "$@"; }

# Run analyze help function
#
# Displays help information for the run analyze command
# including usage examples and available options.
_show_run_analyze_help() {
	cat <<'EOF'
gh ai run analyze - Analyze a workflow run, optionally as an interactive session

USAGE:
    gh ai [CLAUDE_OPTIONS] run analyze <RUN_ID> [-d <DESCRIPTION>] [-i]

DESCRIPTION:
    Fetches GitHub Actions workflow run metadata and logs into a persistent
    session directory and renders an analysis prompt referencing those files.
    Uses --log-failed for failed runs and --log otherwise.

    Without -i, prints the analysis to stdout and exits.
    With -i, opens an interactive agent session that begins with the
    analysis and asks how you'd like to proceed.

    Context files persist under ~/.local/state/gh/ai/sessions/run-<ID>/state/
    and are refreshed on every invocation. Claude options (e.g. --model,
    --verbose) go before the subcommand.

    Configure the model: gh config set ai.run.model <model>

FLAGS:
    -d, --description string   Extra context or focus for the analysis (optional)
    -i, --interactive          Open an interactive agent session

EXAMPLES:
    gh ai run analyze 123456
    gh ai run analyze 123456 -i
    gh ai run analyze 123456 -d "focus on test failures" -i
    gh ai --model sonnet run analyze 123456 -i
EOF
}

# Run Analyze implementation
#
# Fetches a GitHub Actions workflow run's metadata and logs into a persistent
# session directory, renders the analyze template, and either prints the
# analysis (one-shot) or opens an interactive agent session (-i).
#
# Usage: _gh_run_analyze <RUN_ID> [-d <DESCRIPTION>] [-i]
_gh_run_analyze() {
	case "${1:-}" in
	--help | -h | help)
		_show_run_analyze_help
		return 0
		;;
	esac

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_ai_source_dir/templates/gh_run_analyze.tmpl"

	local gh_run_id="" gh_run_description="" gh_run_interactive=""
	_parse_run_analyze_args gh_run_id gh_run_description gh_run_interactive "$@" || return 1

	if [[ -z "$gh_run_id" ]]; then
		gum log --level error "No run ID provided"
		gum log --level info "Usage: gh ai run analyze <RUN_ID> [-d <DESCRIPTION>] [-i]"
		return 1
	fi

	local gh_run_focus=""
	if [[ -n "$gh_run_description" ]]; then
		gh_run_focus="<focus>${gh_run_description}</focus>"
	fi

	local gh_run_dir="" gh_run_title="" gh_run_conclusion="" gh_run_url="" gh_run_event="" gh_run_branch="" gh_run_sha=""
	_prepare_run_analyze_context "$gh_run_id" gh_run_dir gh_run_title gh_run_conclusion gh_run_url gh_run_event gh_run_branch gh_run_sha || return 1

	local gh_run_interactive_instruction=""
	if [[ "$gh_run_interactive" == "true" ]]; then
		gh_run_interactive_instruction="Then ask the user how they'd like to proceed — investigate a specific failure, draft a fix, retry the run, or open an issue."
	fi

	local gh_run_prompt
	gh_run_prompt=$(
		GH_RUN_ID="$gh_run_id" \
			GH_RUN_TITLE="$gh_run_title" \
			GH_RUN_CONCLUSION="$gh_run_conclusion" \
			GH_RUN_FOCUS="$gh_run_focus" \
			GH_RUN_URL="$gh_run_url" \
			GH_RUN_EVENT="$gh_run_event" \
			GH_RUN_BRANCH="$gh_run_branch" \
			GH_RUN_SHA="$gh_run_sha" \
			GH_AI_SESSION_DIR="$gh_run_dir" \
			GH_AI_INTERACTIVE_INSTRUCTION="$gh_run_interactive_instruction" \
			"$_gh_ai_source_dir/scripts/gh_cmd.sh" render "$template_file"
	)

	if [[ "$gh_run_interactive" == "true" ]]; then
		_cmd_chat "$gh_run_prompt"
		return $?
	fi

	local gh_run_agent_model
	gh_run_agent_model=$(_gh_config_ai_model "run")

	local gh_run_analysis
	gh_run_analysis=$(
		gum spin --title "Analyzing GitHub workflow run #$gh_run_id..." -- \
			"$_gh_ai_source_dir/scripts/gh_cmd.sh" ask "$gh_run_agent_model" <<<"$gh_run_prompt"
	)

	if [[ -z "$gh_run_analysis" ]]; then
		gum log --level error "Failed to generate run analysis"
		gum log --level info "Run with DEBUG=1 for detailed diagnostics"
		return 1
	fi

	printf '%s\n' "$gh_run_analysis"
}

# Run help function
#
# Displays comprehensive help information for all run subcommands
# including usage examples and available options.
_show_run_help() {
	cat <<'EOF'
gh ai run - Workflow run commands with AI assistance

USAGE:
    gh ai [CLAUDE_OPTIONS] run analyze <RUN_ID> [-d <DESCRIPTION>] [-i]

DESCRIPTION:
    Analyzes GitHub Actions workflow runs. Use -i for an interactive session.
    Claude options (e.g. --model) go before the subcommand.

COMMANDS:
    analyze     Analyze a workflow run (use -i for an interactive session)

SEE ALSO:
    gh ai run analyze --help    # Run analyze usage
EOF
}

# Run subcommand handler
#
# Routes run subcommands to their appropriate handler functions.
# Shows help for unknown commands.
#
# Usage: _gh_run <subcommand> [OPTIONS]
# Subcommands: analyze, help
_gh_run() {
	local subcommand="${1:-}"
	shift || true

	case $subcommand in
	analyze)
		_gh_run_analyze "$@"
		;;
	--help | -h | help | "")
		_show_run_help
		;;
	*)
		gum log --level error "unknown run command '$subcommand'"
		gum log --level info "Available commands: analyze"
		gum log --level info "Run 'gh ai run --help' for usage information"
		return 1
		;;
	esac
}
