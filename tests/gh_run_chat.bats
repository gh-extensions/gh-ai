#!/usr/bin/env bats

# Unit tests for gh claude run chat arg parsing and integration
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_run_chat.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _gh_claude_source_dir="$REPO_ROOT"
	export HOME="$BATS_TEST_TMPDIR"
	unset XDG_STATE_HOME

	# Initialize global claude args array (set per-test when needed)
	_GH_CLAUDE_ARGS=()

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
		declare -f _parse_chat_args _parse_run_chat_args _extract_claude_arg _show_run_chat_help _gh_run_chat \
			_cmd_chat _cmd_render _get_agent _git_repo_path _resolve_context_dir _create_context_dir _save_context_file \
			_parse_run_args
	)"
}

# ---------------------------------------------------------------------------
# _parse_run_chat_args
# ---------------------------------------------------------------------------

@test "_parse_run_chat_args: captures run ID from positional arg" {
	local id="" description=""
	_parse_run_chat_args id description 12345678

	[[ "$id" == "12345678" ]]
	[[ -z "$description" ]]
}

@test "_parse_run_chat_args: strips leading # from run ID" {
	local id="" description=""
	_parse_run_chat_args id description "#12345678"

	[[ "$id" == "12345678" ]]
}

@test "_parse_run_chat_args: sets description from -d flag" {
	local id="" description=""
	_parse_run_chat_args id description 12345678 -d "focus on test failures"

	[[ "$id" == "12345678" ]]
	[[ "$description" == "focus on test failures" ]]
}

@test "_parse_run_chat_args: sets description from --description flag" {
	local id="" description=""
	_parse_run_chat_args id description 12345678 --description "focus on test failures"

	[[ "$description" == "focus on test failures" ]]
}

@test "_parse_run_chat_args: sets description from --description=value" {
	local id="" description=""
	_parse_run_chat_args id description 12345678 --description="focus on test failures"

	[[ "$description" == "focus on test failures" ]]
}

@test "_parse_run_chat_args: returns error when -d has no value" {
	local id="" description=""
	run _parse_run_chat_args id description 12345678 -d

	[[ "$status" -eq 1 ]]
}

@test "_parse_run_chat_args: error message includes flag name when --description has no value" {
	local id="" description=""
	run _parse_run_chat_args id description 12345678 --description

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"--description requires a value"* ]]
}

@test "_parse_run_chat_args: returns error for unknown flags" {
	local id="" description=""
	run _parse_run_chat_args id description --failed

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unknown flag '--failed'"* ]]
}

@test "_parse_run_chat_args: returns error for unexpected non-numeric arg" {
	local id="" description=""
	run _parse_run_chat_args id description foo

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unexpected argument 'foo'"* ]]
}

@test "_parse_run_chat_args: returns error for second positional arg" {
	local id="" description=""
	run _parse_run_chat_args id description 12345678 99999999

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unexpected argument '99999999'"* ]]
}

@test "_parse_run_chat_args: defaults to empty when no args given" {
	local id="" description=""
	_parse_run_chat_args id description

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

@test "_gh_run_chat: always renders prompt" {
	_setup_chat_mocks

	_cmd_chat() {
		printf 'URL:%s\n' "$1"
		printf 'PROMPT:%s\n' "$2"
		shift 2
		printf 'ARGS:%s\n' "$*"
	}

	run _gh_run_chat 12345678

	[[ "$status" -eq 0 ]]
	# Prompt should be rendered
	[[ "$output" == *"PROMPT:"* ]]
	[[ "$output" == *"Test Run"* ]]
}

@test "_gh_run_chat: shows help with --help flag" {
	run _gh_run_chat --help

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"run chat"* ]]
}

# ---------------------------------------------------------------------------
# Passthrough parsing and forwarding
# ---------------------------------------------------------------------------

@test "_gh_run_chat: forwards _GH_CLAUDE_ARGS to _cmd_chat via claude" {
	_setup_chat_mocks

	# Mock claude to capture args
	claude() { printf 'CLAUDE_ARGS:%s\n' "$*"; }
	export -f claude

	_GH_CLAUDE_ARGS=(--model sonnet --verbose)
	run _gh_run_chat 12345678

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"--model sonnet --verbose"* ]]
}
