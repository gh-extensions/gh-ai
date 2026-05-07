#!/usr/bin/env bats

# Unit tests for gh ai run analyze arg parsing and integration
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_run_analyze.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _gh_ai_source_dir="$REPO_ROOT"
	export HOME="$BATS_TEST_TMPDIR"
	unset XDG_STATE_HOME

	_GH_AI_ARGS=()

	gum() { if [[ "$1" == "log" ]]; then shift; shift; shift; echo "$@"; fi; }
	gh() { echo ""; }
	git() { echo ""; }
	export -f gum gh git

	# shellcheck disable=SC2155
	eval "$(
		export _gh_ai_source_dir="$REPO_ROOT"
		# shellcheck source=../scripts/gh_cmd.sh
		source "$REPO_ROOT/scripts/gh_cmd.sh"
		# shellcheck source=../scripts/gh_run.sh
		source "$REPO_ROOT/scripts/gh_run.sh"
		declare -f _parse_analyze_args _parse_run_analyze_args _parse_run_args _extract_ai_arg \
			_show_run_analyze_help _show_run_help _gh_run_analyze _gh_run \
			_prepare_run_analyze_context _prepare_run_context \
			_cmd_chat _cmd_ask _cmd_render _get_agent \
			_gh_context_base_dir _resolve_context_dir _create_context_dir _save_context_file \
			_chat_claude _chat_codex _chat_gemini _ask_claude _ask_codex _ask_gemini _gh_config_ai_model
	)"
}

# ---------------------------------------------------------------------------
# _parse_run_analyze_args
# ---------------------------------------------------------------------------

@test "_parse_run_analyze_args: captures run ID from positional arg" {
	local id="" description="" interactive=""
	_parse_run_analyze_args id description interactive 123456

	[[ "$id" == "123456" ]]
}

@test "_parse_run_analyze_args: sets description from -d flag" {
	local id="" description="" interactive=""
	_parse_run_analyze_args id description interactive 123456 -d "focus on test failures"

	[[ "$description" == "focus on test failures" ]]
}

@test "_parse_run_analyze_args: sets interactive from -i flag" {
	local id="" description="" interactive=""
	_parse_run_analyze_args id description interactive 123456 -i

	[[ "$interactive" == "true" ]]
}

@test "_parse_run_analyze_args: returns error for unknown flags" {
	local id="" description="" interactive=""
	run _parse_run_analyze_args id description interactive --bogus

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unknown flag"* ]]
}

# ---------------------------------------------------------------------------
# _show_run_analyze_help
# ---------------------------------------------------------------------------

@test "_show_run_analyze_help: prints help text" {
	run _show_run_analyze_help

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"run analyze"* ]]
	[[ "$output" == *"-i, --interactive"* ]]
}

# ---------------------------------------------------------------------------
# Helpers shared by _gh_run_analyze integration tests
# ---------------------------------------------------------------------------

_setup_run_mocks() {
	gh() {
		case "$1 $2" in
		"run view")
			printf '{"displayTitle":"CI","conclusion":"failure","url":"https://github.com/owner/repo/actions/runs/123456","event":"push","headBranch":"main","headSha":"abc","jobs":[]}'
			;;
		"config get") ;;
		esac
	}
	export -f gh

	gum() {
		case "$1" in
		spin)
			while [[ $# -gt 0 && "$1" != "--" ]]; do shift; done
			[[ $# -gt 0 ]] && shift
			case "${1:-}" in
			*/gh_cmd.sh)
				if [[ "$2" == "ask" ]]; then
					printf '## Summary\nRun failed.\n'
				else
					"$@"
				fi
				;;
			*) "$@" ;;
			esac
			;;
		log) ;;
		esac
	}
	export -f gum
}

@test "_gh_run_analyze: errors when no run ID provided" {
	run _gh_run_analyze

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"No run ID"* ]]
}

@test "_gh_run_analyze: routes through _cmd_chat with -i" {
	_setup_run_mocks

	# The "fetch logs" gum spin will execute "gh run view --log-failed" — mock that
	gh() {
		case "$1 $2" in
		"run view")
			if [[ "${*}" == *"--log-failed"* || "${*}" == *"--log"* ]]; then
				echo "fake log content"
			else
				printf '{"displayTitle":"CI","conclusion":"failure","url":"https://github.com/owner/repo/actions/runs/123456","event":"push","headBranch":"main","headSha":"abc","jobs":[]}'
			fi
			;;
		"config get") ;;
		esac
	}
	export -f gh

	_cmd_chat() {
		printf '%s' "$1"
	}
	export -f _cmd_chat

	run _gh_run_analyze 123456 -i

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"how they'd like to proceed"* ]]
	[[ "$output" == *"/.local/state/gh/ai/context/run-123456/run_log.txt"* ]]
}

@test "_gh_run_analyze: shows help with --help flag" {
	run _gh_run_analyze --help

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"run analyze"* ]]
}

# ---------------------------------------------------------------------------
# Removed subcommands route to "unknown command"
# ---------------------------------------------------------------------------

@test "_gh_run: rejects removed 'explain' subcommand" {
	gum() { echo "GUM:$*"; }
	export -f gum

	run _gh_run explain 123456

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unknown run command"* ]]
}

@test "_gh_run: rejects removed 'chat' subcommand" {
	gum() { echo "GUM:$*"; }
	export -f gum

	run _gh_run chat 123456

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unknown run command"* ]]
}
