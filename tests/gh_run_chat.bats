#!/usr/bin/env bats

# Unit tests for gh ai run chat arg parsing and integration
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_run_chat.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _gh_ai_source_dir="$REPO_ROOT"

	gum() { if [[ "$1" == "log" ]]; then shift; shift; shift; echo "$@"; fi; }
	gh() { echo ""; }
	git() { echo ""; }
	uuid() { echo "aaaabbbb-1234-5678-abcd-ef0123456789"; }
	claude() { :; }
	export -f gum gh git uuid claude

	# shellcheck disable=SC2155
	eval "$(
		export _gh_ai_source_dir="$REPO_ROOT"
		# shellcheck source=../scripts/gh_run.sh
		source "$REPO_ROOT/scripts/gh_run.sh"
		# shellcheck source=../scripts/gh_cmd.sh
		source "$REPO_ROOT/scripts/gh_cmd.sh"
		declare -f _parse_run_chat_args _show_run_chat_help _gh_run_chat \
			_get_repo_name _get_git_repo_path _init_claude_session \
			_git_worktree_sync _cmd_chat _cmd_render
	)"
}

# ---------------------------------------------------------------------------
# _parse_run_chat_args
# ---------------------------------------------------------------------------

@test "_parse_run_chat_args: captures run ID from positional arg" {
	local id=""
	_parse_run_chat_args id 12345678

	[[ "$id" == "12345678" ]]
}

@test "_parse_run_chat_args: strips leading # from run ID" {
	local id=""
	_parse_run_chat_args id "#12345678"

	[[ "$id" == "12345678" ]]
}

@test "_parse_run_chat_args: defaults to empty when no args given" {
	local id=""
	_parse_run_chat_args id

	[[ -z "$id" ]]
}

@test "_parse_run_chat_args: stops at -- separator" {
	local id=""
	_parse_run_chat_args id 12345678 -- --extra-flag

	[[ "$id" == "12345678" ]]
}

@test "_parse_run_chat_args: returns error for unknown flags" {
	local id=""
	run _parse_run_chat_args id --failed

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unknown flag '--failed'"* ]]
}

@test "_parse_run_chat_args: returns error for unexpected non-numeric arg" {
	local id=""
	run _parse_run_chat_args id foo

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unexpected argument 'foo'"* ]]
}

@test "_parse_run_chat_args: returns error for second positional arg" {
	local id=""
	run _parse_run_chat_args id 12345678 99999999

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unexpected argument '99999999'"* ]]
}

# ---------------------------------------------------------------------------
# _gh_run_chat integration
# ---------------------------------------------------------------------------

# Sets up mocks for a successful _gh_run_chat run.
_setup_run_chat_mocks() {
	export _test_git_dir="$BATS_TMPDIR/gh-ai-run-test-$$"
	mkdir -p "$_test_git_dir/.claude/sessions"

	git() {
		case "$1 $2" in
		"rev-parse --show-toplevel") echo "$_test_git_dir" ;;
		"fetch origin") ;;
		"worktree add") mkdir -p "$_test_git_dir/.claude/worktrees/run-12345678" ;;
		*) ;;
		esac
	}
	export -f git

	gh() {
		case "$1 $2" in
		"repo view") echo "owner/repo" ;;
		"run view") echo "main" ;;
		"ai run") echo "# Run Explanation" ;;
		*) ;;
		esac
	}
	export -f gh

	uuid() { echo "aaaabbbb-1234-5678-abcd-ef0123456789"; }
	export -f uuid

	claude() { :; }
	export -f claude

	gum() {
		case "$1" in
		spin)
			while [[ $# -gt 0 && "$1" != "--" ]]; do shift; done
			[[ $# -gt 0 ]] && shift
			"$@" || true
			;;
		log) shift; echo "$@" ;;
		esac
	}
	export -f gum
}

@test "_gh_run_chat: errors when no run ID provided" {
	_setup_run_chat_mocks

	run _gh_run_chat

	[[ "$status" -eq 1 ]]
}

@test "_gh_run_chat: errors when repo resolution fails" {
	_setup_run_chat_mocks

	gh() {
		case "$1 $2" in
		"repo view") ;;
		*) ;;
		esac
	}
	export -f gh

	run _gh_run_chat 12345678

	[[ "$status" -eq 1 ]]
}

@test "_gh_run_chat: errors when run head branch fetch fails" {
	_setup_run_chat_mocks

	gh() {
		case "$1 $2" in
		"repo view") echo "owner/repo" ;;
		"run view") ;;
		*) ;;
		esac
	}
	export -f gh

	run _gh_run_chat 12345678

	[[ "$status" -eq 1 ]]
}

@test "_gh_run_chat: creates worktree and starts session when sentinel absent" {
	_setup_run_chat_mocks

	run _gh_run_chat 12345678

	[[ "$status" -eq 0 ]]
}

@test "_gh_run_chat: resumes session when sentinel file exists" {
	_setup_run_chat_mocks

	# Pre-create the worktree dir and session sentinel
	mkdir -p "$_test_git_dir/.claude/worktrees/run-12345678"
	local session_id="aaaabbbb-1234-5678-abcd-ef0123456789"
	touch "$_test_git_dir/.claude/sessions/$session_id"

	claude() { :; }
	export -f claude

	run _gh_run_chat 12345678

	[[ "$status" -eq 0 ]]
}

@test "_gh_run_chat: errors when preamble rendering fails" {
	_setup_run_chat_mocks

	# Pre-create worktree so we skip worktree setup
	mkdir -p "$_test_git_dir/.claude/worktrees/run-12345678"

	_cmd_render() { :; }

	run _gh_run_chat 12345678

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"Failed to render chat preamble"* ]]
}

@test "_gh_run_chat: shows help with --help flag" {
	run _gh_run_chat --help

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"gh ai run chat"* ]]
	[[ "$output" == *"debug"* ]]
}
