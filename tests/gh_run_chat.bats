#!/usr/bin/env bats

# Unit tests for gh claude run chat arg parsing and integration
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_run_chat.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _gh_claude_source_dir="$REPO_ROOT"
	export HOME="$BATS_TEST_TMPDIR"

	mkdir -p "$BATS_TEST_TMPDIR/.git"
	gum() { if [[ "$1" == "log" ]]; then shift; shift; shift; echo "$@"; fi; }
	gh() { echo ""; }
	git() {
		case "$1 $2" in
		"rev-parse --show-toplevel") echo "$BATS_TEST_TMPDIR" ;;
		"rev-parse --abbrev-ref") echo "" ;;
		"rev-parse --git-common-dir") echo "$BATS_TEST_TMPDIR/.git" ;;
		esac
	}
	export -f gum gh git

	# shellcheck disable=SC2155
	eval "$(
		export _gh_claude_source_dir="$REPO_ROOT"
		# shellcheck source=../scripts/gh_run.sh
		source "$REPO_ROOT/scripts/gh_run.sh"
		# shellcheck source=../scripts/gh_cmd.sh
		source "$REPO_ROOT/scripts/gh_cmd.sh"
		declare -f _parse_chat_args _parse_run_chat_args _validate_chat_passthrough _show_run_chat_help _gh_run_chat \
			_cmd_chat _cmd_render _split_on_separator _get_agent _git_repo_path _resolve_chat_session \
			_prepare_run_chat_context _prepare_run_context _resolve_context_dir _create_context_dir _save_context_file \
			_parse_run_args _gh_session_base_dir
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

@test "_parse_run_chat_args: captures --new-session flag" {
	local id="" description="" new_session=""
	_parse_run_chat_args id description new_session 12345678 --new-session

	[[ "$id" == "12345678" ]]
	[[ "$new_session" == "1" ]]
}

@test "_parse_run_chat_args: captures -n flag" {
	local id="" description="" new_session=""
	_parse_run_chat_args id description new_session 12345678 -n

	[[ "$id" == "12345678" ]]
	[[ "$new_session" == "1" ]]
}

@test "_parse_run_chat_args: --new-session defaults to empty" {
	local id="" description="" new_session=""
	_parse_run_chat_args id description new_session 12345678

	[[ -z "$new_session" ]]
}

@test "_parse_run_chat_args: returns error when -d has no value" {
	local id="" description="" reset=""
	run _parse_run_chat_args id description reset 12345678 -d

	[[ "$status" -eq 1 ]]
}

@test "_parse_run_chat_args: error message includes flag name when --description has no value" {
	local id="" description="" reset=""
	run _parse_run_chat_args id description reset 12345678 --description

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"--description requires a value"* ]]
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
		# First call: --json metadata; second call: --log / --log-failed (returns same JSON but non-empty is sufficient)
		"run view") printf '{"displayTitle":"Test Run","conclusion":"failure","url":"https://github.com/owner/repo/actions/runs/123","event":"push","headBranch":"main","headSha":"abc123def456","jobs":[]}' ;;
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

@test "_gh_run_chat: calls _cmd_chat with rendered prompt and session args" {
	_setup_chat_mocks

	_cmd_chat() {
		printf 'URL:%s\n' "$1"
		printf 'PROMPT:%s\n' "$2"
		shift 2
		printf 'ARGS:%s\n' "$*"
	}

	run _gh_run_chat 12345678

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"PROMPT:"* ]]
	[[ "$output" == *"Test Run"* ]]
	[[ "$output" == *"--session-id"* ]]
}


@test "_gh_run_chat: errors when no run ID provided" {
	_setup_chat_mocks

	run _gh_run_chat

	[[ "$status" -eq 1 ]]
}

@test "_gh_run_chat: errors when metadata fetch fails" {
	gh() {
		case "$1 $2" in
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

@test "_gh_run_chat: resumes previous session on second call" {
	_setup_chat_mocks

	_cmd_chat() {
		printf 'URL:%s\n' "$1"
		printf 'PROMPT:%s\n' "$2"
		shift 2
		printf 'ARGS:%s\n' "$*"
	}

	# First call creates session
	run _gh_run_chat 12345678
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"--session-id"* ]]

	# Second call should resume with empty prompt
	_cmd_chat() {
		printf 'URL:%s\n' "$1"
		printf 'PROMPT:%s\n' "$2"
		shift 2
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

# ---------------------------------------------------------------------------
# Passthrough parsing and forwarding
# ---------------------------------------------------------------------------

@test "_gh_run_chat: forwards passthrough args to _cmd_chat" {
	_setup_chat_mocks

	_cmd_chat() {
		printf 'URL:%s\n' "$1"
		printf 'PROMPT:%s\n' "$2"
		shift 2
		printf 'ARGS:%s\n' "$*"
	}

	run _gh_run_chat 12345678 -- --model sonnet --verbose

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"--model sonnet --verbose"* ]]
}

@test "_gh_run_chat: rejects managed flags in passthrough" {
	run _gh_run_chat 12345678 -- --session-id custom

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"--session-id is managed by gh-claude"* ]]
}
