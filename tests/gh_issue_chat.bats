#!/usr/bin/env bats

# Unit tests for gh ai issue chat arg parsing and integration
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_issue_chat.bats

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
		# shellcheck source=../scripts/gh_issue.sh
		source "$REPO_ROOT/scripts/gh_issue.sh"
		# shellcheck source=../scripts/gh_cmd.sh
		source "$REPO_ROOT/scripts/gh_cmd.sh"
		declare -f _parse_chat_args _parse_issue_chat_args _show_issue_chat_help _gh_issue_chat \
			_cmd_chat _cmd_render _split_on_separator _get_agent _git_repo_path _resolve_chat_session \
			_prepare_issue_chat_context _prepare_issue_context _resolve_context_dir _create_context_dir _save_context_file
	)"
}

# ---------------------------------------------------------------------------
# _parse_issue_chat_args
# ---------------------------------------------------------------------------

@test "_parse_issue_chat_args: captures issue number from positional arg" {
	local number="" description="" reset=""
	_parse_issue_chat_args number description reset 42

	[[ "$number" == "42" ]]
	[[ -z "$description" ]]
	[[ -z "$reset" ]]
}

@test "_parse_issue_chat_args: strips leading # from issue number" {
	local number="" description="" reset=""
	_parse_issue_chat_args number description reset "#42"

	[[ "$number" == "42" ]]
}

@test "_parse_issue_chat_args: sets description from -d flag" {
	local number="" description="" reset=""
	_parse_issue_chat_args number description reset 42 -d "focus on auth"

	[[ "$number" == "42" ]]
	[[ "$description" == "focus on auth" ]]
}

@test "_parse_issue_chat_args: sets description from --description flag" {
	local number="" description="" reset=""
	_parse_issue_chat_args number description reset 42 --description "focus on auth"

	[[ "$description" == "focus on auth" ]]
}

@test "_parse_issue_chat_args: sets description from --description=value" {
	local number="" description="" reset=""
	_parse_issue_chat_args number description reset 42 --description="focus on auth"

	[[ "$description" == "focus on auth" ]]
}

@test "_parse_issue_chat_args: captures --new-session flag" {
	local number="" description="" new_session=""
	_parse_issue_chat_args number description new_session 42 --new-session

	[[ "$number" == "42" ]]
	[[ "$new_session" == "1" ]]
}

@test "_parse_issue_chat_args: captures -n flag" {
	local number="" description="" new_session=""
	_parse_issue_chat_args number description new_session 42 -n

	[[ "$number" == "42" ]]
	[[ "$new_session" == "1" ]]
}

@test "_parse_issue_chat_args: --new-session defaults to empty" {
	local number="" description="" new_session=""
	_parse_issue_chat_args number description new_session 42

	[[ -z "$new_session" ]]
}

@test "_parse_issue_chat_args: returns error when -d has no value" {
	local number="" description="" reset=""
	run _parse_issue_chat_args number description reset 42 -d

	[[ "$status" -eq 1 ]]
}

@test "_parse_issue_chat_args: returns error for unknown flags" {
	local number="" description="" reset=""
	run _parse_issue_chat_args number description reset --draft

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unknown flag '--draft'"* ]]
}

@test "_parse_issue_chat_args: returns error for unexpected non-numeric args" {
	local number="" description="" reset=""
	run _parse_issue_chat_args number description reset foo

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unexpected argument 'foo'"* ]]
}

@test "_parse_issue_chat_args: returns error for second positional arg" {
	local number="" description="" reset=""
	run _parse_issue_chat_args number description reset 42 99

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unexpected argument '99'"* ]]
}

# ---------------------------------------------------------------------------
# _show_issue_chat_help
# ---------------------------------------------------------------------------

@test "_show_issue_chat_help: prints help text" {
	run _show_issue_chat_help

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"issue chat"* ]]
	[[ "$output" == *"ISSUE_NUMBER"* ]]
}

# ---------------------------------------------------------------------------
# Helpers shared by _gh_issue_chat integration tests
# ---------------------------------------------------------------------------

_setup_chat_mocks() {
	gh() {
		case "$1 $2" in
		"issue view") printf '{"title":"Test Issue","body":"Issue body","labels":[],"comments":[]}' ;;
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

	_save_worktree_state() { :; }
}

@test "_gh_issue_chat: calls _cmd_chat with rendered preamble and session args" {
	_setup_chat_mocks

	# Mock _cmd_chat to capture what it receives
	_cmd_chat() {
		printf 'PREAMBLE:%s\n' "$1"
		shift
		printf 'ARGS:%s\n' "$*"
	}

	run _gh_issue_chat 42

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"PREAMBLE:"* ]]
	[[ "$output" == *"Test Issue"* ]]
	[[ "$output" == *"--session-id"* ]]
	[[ "$output" == *"--worktree issue-42"* ]]
}


@test "_gh_issue_chat: errors when no issue number provided" {
	_setup_chat_mocks

	run _gh_issue_chat

	[[ "$status" -eq 1 ]]
}

@test "_gh_issue_chat: errors when issue fetch fails" {
	gh() {
		case "$1 $2" in
		"issue view") ;;
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

	run _gh_issue_chat 42

	[[ "$status" -eq 1 ]]
}

@test "_gh_issue_chat: resumes previous session on second call" {
	_setup_chat_mocks

	_cmd_chat() {
		printf 'PREAMBLE:%s\n' "$1"
		shift
		printf 'ARGS:%s\n' "$*"
	}

	# First call creates session
	run _gh_issue_chat 42
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"--session-id"* ]]

	# Second call should resume with empty preamble
	_cmd_chat() {
		printf 'PREAMBLE:%s\n' "$1"
		shift
		printf 'ARGS:%s\n' "$*"
	}

	run _gh_issue_chat 42
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"--resume"* ]]
	[[ "$output" != *"Test Issue"* ]]
}

@test "_gh_issue_chat: shows help with --help flag" {
	run _gh_issue_chat --help

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"issue chat"* ]]
}
