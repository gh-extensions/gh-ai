#!/usr/bin/env bats

# Unit tests for gh ai run chat arg parsing and integration
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_run_chat.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _gh_ai_source_dir="$REPO_ROOT"
	export HOME="$BATS_TEST_TMPDIR"

	gum() { if [[ "$1" == "log" ]]; then shift; shift; shift; echo "$@"; fi; }
	gh() { echo ""; }
	git() {
		case "$1 $2" in
		"rev-parse --show-toplevel") echo "$BATS_TEST_TMPDIR" ;;
		"rev-parse --abbrev-ref") echo "" ;;
		esac
	}
	export -f gum gh git

	# shellcheck disable=SC2155
	eval "$(
		export _gh_ai_source_dir="$REPO_ROOT"
		# shellcheck source=../scripts/gh_run.sh
		source "$REPO_ROOT/scripts/gh_run.sh"
		# shellcheck source=../scripts/gh_cmd.sh
		source "$REPO_ROOT/scripts/gh_cmd.sh"
		declare -f _parse_run_chat_args _show_run_chat_help _gh_run_chat _cmd_chat _cmd_render _split_on_separator _get_agent _uuidv5 _git_repo_path _resolve_session_state _try_resume_chat_session _resolve_chat_session _gh_repo_name
	)"
}

# ---------------------------------------------------------------------------
# _parse_run_chat_args
# ---------------------------------------------------------------------------

@test "_parse_run_chat_args: captures run ID from positional arg" {
	local id="" description="" reset=""
	_parse_run_chat_args id description reset 12345678

	[[ "$id" == "12345678" ]]
	[[ -z "$description" ]]
	[[ -z "$reset" ]]
}

@test "_parse_run_chat_args: strips leading # from run ID" {
	local id="" description="" reset=""
	_parse_run_chat_args id description reset "#12345678"

	[[ "$id" == "12345678" ]]
}

@test "_parse_run_chat_args: sets description from -d flag" {
	local id="" description="" reset=""
	_parse_run_chat_args id description reset 12345678 -d "focus on test failures"

	[[ "$id" == "12345678" ]]
	[[ "$description" == "focus on test failures" ]]
}

@test "_parse_run_chat_args: sets description from --description flag" {
	local id="" description="" reset=""
	_parse_run_chat_args id description reset 12345678 --description "focus on test failures"

	[[ "$description" == "focus on test failures" ]]
}

@test "_parse_run_chat_args: sets description from --description=value" {
	local id="" description="" reset=""
	_parse_run_chat_args id description reset 12345678 --description="focus on test failures"

	[[ "$description" == "focus on test failures" ]]
}

@test "_parse_run_chat_args: captures --reset flag" {
	local id="" description="" reset=""
	_parse_run_chat_args id description reset 12345678 --reset

	[[ "$id" == "12345678" ]]
	[[ "$reset" == "1" ]]
}

@test "_parse_run_chat_args: --reset defaults to empty" {
	local id="" description="" reset=""
	_parse_run_chat_args id description reset 12345678

	[[ -z "$reset" ]]
}

@test "_parse_run_chat_args: returns error when -d has no value" {
	local id="" description="" reset=""
	run _parse_run_chat_args id description reset 12345678 -d

	[[ "$status" -eq 1 ]]
}

@test "_parse_run_chat_args: returns error for unknown flags" {
	local id="" description="" reset=""
	run _parse_run_chat_args id description reset --failed

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unknown flag '--failed'"* ]]
}

@test "_parse_run_chat_args: returns error for unexpected non-numeric arg" {
	local id="" description="" reset=""
	run _parse_run_chat_args id description reset foo

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unexpected argument 'foo'"* ]]
}

@test "_parse_run_chat_args: returns error for second positional arg" {
	local id="" description="" reset=""
	run _parse_run_chat_args id description reset 12345678 99999999

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unexpected argument '99999999'"* ]]
}

@test "_parse_run_chat_args: defaults to empty when no args given" {
	local id="" description="" reset=""
	_parse_run_chat_args id description reset

	[[ -z "$id" ]]
}

# ---------------------------------------------------------------------------
# _show_run_chat_help
# ---------------------------------------------------------------------------

@test "_show_run_chat_help: prints help text" {
	run _show_run_chat_help

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"run chat"* ]]
	[[ "$output" == *"RUN_ID"* ]]
}

# ---------------------------------------------------------------------------
# Helpers shared by _gh_run_chat integration tests
# ---------------------------------------------------------------------------

_setup_chat_mocks() {
	gh() {
		case "$1 $2" in
		"repo view") echo "owner/repo" ;;
		"run view") printf "gh_run_title='Test Run'\ngh_run_conclusion='failure'\ngh_run_event='push'\ngh_run_branch='main'\ngh_run_jobs='build'" ;;
		"config get") ;;
		esac
	}
	export -f gh

	gum() {
		case "$1" in
		spin)
			while [[ $# -gt 0 && "$1" != "--" ]]; do shift; done
			[[ $# -gt 0 ]] && shift
			"$@"
			;;
		log) ;;
		esac
	}
	export -f gum
}

@test "_gh_run_chat: calls _cmd_chat with rendered preamble and session args" {
	_setup_chat_mocks

	_cmd_chat() {
		printf 'PREAMBLE:%s\n' "$1"
		shift
		printf 'ARGS:%s\n' "$*"
	}

	run _gh_run_chat 12345678

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"PREAMBLE:"* ]]
	[[ "$output" == *"Test Run"* ]]
	[[ "$output" == *"--session-id"* ]]
	[[ "$output" == *"--worktree run-12345678"* ]]
}

@test "_gh_run_chat: passes session args before passthrough args" {
	_setup_chat_mocks

	_cmd_chat() {
		printf 'PREAMBLE:%s\n' "$1"
		shift
		printf 'ALLARGS:%s\n' "$*"
	}

	run _gh_run_chat 12345678 -- --model sonnet

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"--session-id"* ]]
	[[ "$output" == *"--model sonnet"* ]]
}

@test "_gh_run_chat: errors when no run ID provided" {
	_setup_chat_mocks

	run _gh_run_chat

	[[ "$status" -eq 1 ]]
}

@test "_gh_run_chat: errors when metadata fetch fails" {
	gh() {
		case "$1 $2" in
		"repo view") echo "owner/repo" ;;
		"run view") ;;
		"config get") ;;
		esac
	}
	export -f gh

	gum() {
		case "$1" in
		spin)
			while [[ $# -gt 0 && "$1" != "--" ]]; do shift; done
			[[ $# -gt 0 ]] && shift
			"$@"
			;;
		log) ;;
		esac
	}
	export -f gum

	run _gh_run_chat 12345678

	[[ "$status" -eq 1 ]]
}

@test "_gh_run_chat: resumes session without fetching metadata on second call" {
	_setup_chat_mocks

	_cmd_chat() {
		printf 'PREAMBLE:%s\n' "$1"
		shift
		printf 'ARGS:%s\n' "$*"
	}

	# First call creates session
	run _gh_run_chat 12345678
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"--session-id"* ]]

	# Second call should resume with empty preamble
	_cmd_chat() {
		printf 'PREAMBLE:%s\n' "$1"
		shift
		printf 'ARGS:%s\n' "$*"
	}

	run _gh_run_chat 12345678
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"--resume"* ]]
	[[ "$output" != *"Test Run"* ]]
}

@test "_gh_run_chat: shows help with --help flag" {
	run _gh_run_chat --help

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"run chat"* ]]
}
