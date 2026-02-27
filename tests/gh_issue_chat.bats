#!/usr/bin/env bats

# Unit tests for gh ai issue chat arg parsing and integration
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_issue_chat.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _gh_ai_source_dir="$REPO_ROOT"

	gum() { :; }
	gh() { echo ""; }
	git() { echo ""; }
	uuid() { echo "aaaabbbb-1234-5678-abcd-ef0123456789"; }
	claude() { :; }
	export -f gum gh git uuid claude

	# shellcheck disable=SC2155
	eval "$(
		export _gh_ai_source_dir="$REPO_ROOT"
		# shellcheck source=../scripts/gh_issue.sh
		source "$REPO_ROOT/scripts/gh_issue.sh"
		# shellcheck source=../scripts/gh_cmd.sh
		source "$REPO_ROOT/scripts/gh_cmd.sh"
		declare -f _parse_issue_chat_args _show_issue_chat_help _gh_issue_chat \
			_get_repo_name _get_git_repo_path _init_claude_session \
			_git_worktree_sync _cmd_chat
	)"
}

# ---------------------------------------------------------------------------
# _parse_issue_chat_args
# ---------------------------------------------------------------------------

@test "_parse_issue_chat_args: captures issue number from positional arg" {
	local number=""
	_parse_issue_chat_args number 42

	[[ "$number" == "42" ]]
}

@test "_parse_issue_chat_args: strips leading # from issue number" {
	local number=""
	_parse_issue_chat_args number "#42"

	[[ "$number" == "42" ]]
}

@test "_parse_issue_chat_args: defaults to empty when no args given" {
	local number=""
	_parse_issue_chat_args number

	[[ -z "$number" ]]
}

@test "_parse_issue_chat_args: stops at -- separator" {
	local number=""
	_parse_issue_chat_args number 42 -- --extra-flag

	[[ "$number" == "42" ]]
}

@test "_parse_issue_chat_args: returns error for unknown flags" {
	local number=""
	run _parse_issue_chat_args number --draft

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unknown flag '--draft'"* ]]
}

@test "_parse_issue_chat_args: returns error for unexpected non-numeric arg" {
	local number=""
	run _parse_issue_chat_args number foo

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unexpected argument 'foo'"* ]]
}

@test "_parse_issue_chat_args: returns error for second positional arg" {
	local number=""
	run _parse_issue_chat_args number 42 99

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unexpected argument '99'"* ]]
}

# ---------------------------------------------------------------------------
# _gh_issue_chat integration
# ---------------------------------------------------------------------------

# Sets up mocks for a successful _gh_issue_chat run.
# Callers can override individual functions after calling this.
_setup_issue_chat_mocks() {
	export _test_git_dir="$BATS_TMPDIR/gh-ai-test-$$"
	mkdir -p "$_test_git_dir/.claude/sessions"

	git() {
		case "$1 $2" in
		"rev-parse --show-toplevel") echo "$_test_git_dir" ;;
		"fetch origin") ;;
		"worktree add") mkdir -p "$_test_git_dir/.claude/worktrees/issue-42" ;;
		*) ;;
		esac
	}
	export -f git

	gh() {
		case "$1 $2" in
		"repo view") echo "owner/repo" ;;
		"issue develop") ;;
		"ai issue") echo "# Implementation Plan" ;;
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
		log) ;;
		esac
	}
	export -f gum
}

@test "_gh_issue_chat: errors when no issue number provided" {
	_setup_issue_chat_mocks

	run _gh_issue_chat

	[[ "$status" -eq 1 ]]
}

@test "_gh_issue_chat: errors when repo resolution fails" {
	_setup_issue_chat_mocks

	gh() {
		case "$1 $2" in
		"repo view") ;;
		*) ;;
		esac
	}
	export -f gh

	run _gh_issue_chat 42

	[[ "$status" -eq 1 ]]
}

@test "_gh_issue_chat: errors when git root resolution fails" {
	_setup_issue_chat_mocks

	git() {
		case "$1 $2" in
		"rev-parse --show-toplevel") ;;
		*) ;;
		esac
	}
	export -f git

	run _gh_issue_chat 42

	[[ "$status" -eq 1 ]]
}

@test "_gh_issue_chat: creates worktree and starts session when sentinel absent" {
	_setup_issue_chat_mocks

	claude() { :; }
	export -f claude

	run _gh_issue_chat 42

	[[ "$status" -eq 0 ]]
}

@test "_gh_issue_chat: resumes session when sentinel file exists" {
	_setup_issue_chat_mocks

	# Pre-create the worktree dir and session sentinel
	mkdir -p "$_test_git_dir/.claude/worktrees/issue-42"
	local session_id
	session_id="aaaabbbb-1234-5678-abcd-ef0123456789"
	touch "$_test_git_dir/.claude/sessions/$session_id"

	claude() { :; }
	export -f claude

	run _gh_issue_chat 42

	[[ "$status" -eq 0 ]]
}

@test "_gh_issue_chat: shows help with --help flag" {
	run _gh_issue_chat --help

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"gh ai issue chat"* ]]
}
