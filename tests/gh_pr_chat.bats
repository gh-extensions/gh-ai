#!/usr/bin/env bats

# Unit tests for gh ai pr chat arg parsing and integration
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_pr_chat.bats

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
		# shellcheck source=../scripts/gh_cmd.sh
		source "$REPO_ROOT/scripts/gh_cmd.sh"
		# shellcheck source=../scripts/gh_pr.sh
		source "$REPO_ROOT/scripts/gh_pr.sh"
		declare -f _parse_pr_chat_args _show_pr_chat_help _gh_pr_chat _cmd_chat _cmd_render _split_on_separator _get_agent _uuidv5 _git_repo_path _resolve_session_state _try_resume_chat_session _resolve_chat_session _gh_repo_name
	)"
}

# ---------------------------------------------------------------------------
# _parse_pr_chat_args
# ---------------------------------------------------------------------------

@test "_parse_pr_chat_args: captures PR number from positional arg" {
	local number="" description="" reset=""
	_parse_pr_chat_args number description reset 42

	[[ "$number" == "42" ]]
	[[ -z "$description" ]]
	[[ -z "$reset" ]]
}

@test "_parse_pr_chat_args: strips leading # from PR number" {
	local number="" description="" reset=""
	_parse_pr_chat_args number description reset "#42"

	[[ "$number" == "42" ]]
}

@test "_parse_pr_chat_args: sets description from -d flag" {
	local number="" description="" reset=""
	_parse_pr_chat_args number description reset 42 -d "focus on security"

	[[ "$number" == "42" ]]
	[[ "$description" == "focus on security" ]]
}

@test "_parse_pr_chat_args: sets description from --description flag" {
	local number="" description="" reset=""
	_parse_pr_chat_args number description reset 42 --description "focus on security"

	[[ "$description" == "focus on security" ]]
}

@test "_parse_pr_chat_args: sets description from --description=value" {
	local number="" description="" reset=""
	_parse_pr_chat_args number description reset 42 --description="focus on security"

	[[ "$description" == "focus on security" ]]
}

@test "_parse_pr_chat_args: captures --new-session flag" {
	local number="" description="" new_session=""
	_parse_pr_chat_args number description new_session 42 --new-session

	[[ "$number" == "42" ]]
	[[ "$new_session" == "1" ]]
}

@test "_parse_pr_chat_args: captures -n flag" {
	local number="" description="" new_session=""
	_parse_pr_chat_args number description new_session 42 -n

	[[ "$number" == "42" ]]
	[[ "$new_session" == "1" ]]
}

@test "_parse_pr_chat_args: --new-session defaults to empty" {
	local number="" description="" new_session=""
	_parse_pr_chat_args number description new_session 42

	[[ -z "$new_session" ]]
}

@test "_parse_pr_chat_args: returns error when -d has no value" {
	local number="" description="" reset=""
	run _parse_pr_chat_args number description reset 42 -d

	[[ "$status" -eq 1 ]]
}

@test "_parse_pr_chat_args: returns error for unknown flags" {
	local number="" description="" reset=""
	run _parse_pr_chat_args number description reset --draft

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unknown flag '--draft'"* ]]
}

@test "_parse_pr_chat_args: returns error for unexpected non-numeric args" {
	local number="" description="" reset=""
	run _parse_pr_chat_args number description reset foo

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unexpected argument 'foo'"* ]]
}

@test "_parse_pr_chat_args: returns error for second positional arg" {
	local number="" description="" reset=""
	run _parse_pr_chat_args number description reset 42 99

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unexpected argument '99'"* ]]
}

@test "_parse_pr_chat_args: auto-detects PR number from current branch" {
	gh() {
		case "$1 $2" in
		"pr view") echo "7" ;;
		esac
	}
	export -f gh

	local number="" description="" reset=""
	_parse_pr_chat_args number description reset

	[[ "$number" == "7" ]]
}

# ---------------------------------------------------------------------------
# _show_pr_chat_help
# ---------------------------------------------------------------------------

@test "_show_pr_chat_help: prints help text" {
	run _show_pr_chat_help

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"pr chat"* ]]
	[[ "$output" == *"PR_NUMBER"* ]]
}

# ---------------------------------------------------------------------------
# Helpers shared by _gh_pr_chat integration tests
# ---------------------------------------------------------------------------

_setup_chat_mocks() {
	gh() {
		case "$1 $2" in
		"repo view") echo "owner/repo" ;;
		"pr diff") echo "diff --git a/file.txt b/file.txt" ;;
		"pr view") printf "gh_pr_title='Test PR Title'\ngh_pr_body='PR body'\ngh_pr_head='feature-branch'\ngh_pr_commits='- Test commit'" ;;
		"config get") ;;
		esac
	}
	export -f gh

	git() {
		case "$1 $2" in
		"rev-parse --show-toplevel") echo "$BATS_TEST_TMPDIR" ;;
		"rev-parse --abbrev-ref") echo "" ;;
		"apply --stat") echo " file.txt | 1 +" ;;
		*) ;;
		esac
	}
	export -f git

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

@test "_gh_pr_chat: calls _cmd_chat with rendered preamble and session args" {
	_setup_chat_mocks

	_cmd_chat() {
		printf 'PREAMBLE:%s\n' "$1"
		shift
		printf 'ARGS:%s\n' "$*"
	}

	run _gh_pr_chat 42

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"PREAMBLE:"* ]]
	[[ "$output" == *"--session-id"* ]]
	[[ "$output" == *"--worktree pull-42"* ]]
}

@test "_gh_pr_chat: passes session args before passthrough args" {
	_setup_chat_mocks

	_cmd_chat() {
		printf 'PREAMBLE:%s\n' "$1"
		shift
		printf 'ALLARGS:%s\n' "$*"
	}

	run _gh_pr_chat 42 -- --model sonnet

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"--session-id"* ]]
	[[ "$output" == *"--model sonnet"* ]]
}

@test "_gh_pr_chat: errors when no PR number provided" {
	gh() {
		case "$1 $2" in
		"pr view") ;;
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

	run _gh_pr_chat

	[[ "$status" -eq 1 ]]
}

@test "_gh_pr_chat: errors when diff is empty" {
	gh() {
		case "$1 $2" in
		"repo view") echo "owner/repo" ;;
		"pr diff") ;;
		"pr view") echo "Test PR Title" ;;
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

	run _gh_pr_chat 42

	[[ "$status" -eq 1 ]]
}

@test "_gh_pr_chat: resumes session without fetching metadata on second call" {
	_setup_chat_mocks

	local fetch_count=0
	_cmd_chat() {
		printf 'PREAMBLE:%s\n' "$1"
		shift
		printf 'ARGS:%s\n' "$*"
	}

	# First call creates session
	run _gh_pr_chat 42
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"--session-id"* ]]

	# Second call should resume with empty preamble
	_cmd_chat() {
		printf 'PREAMBLE:%s\n' "$1"
		shift
		printf 'ARGS:%s\n' "$*"
	}

	run _gh_pr_chat 42
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"--resume"* ]]
	[[ "$output" == *"PREAMBLE:"* ]]
	# Preamble should be empty on resume
	[[ "$output" != *"Test PR Title"* ]]
}

@test "_gh_pr_chat: shows help with --help flag" {
	run _gh_pr_chat --help

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"pr chat"* ]]
}
