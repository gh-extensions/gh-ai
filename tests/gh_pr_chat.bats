#!/usr/bin/env bats

# Unit tests for gh ai pr chat arg parsing and integration
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_pr_chat.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _gh_ai_source_dir="$REPO_ROOT"

	gum() { if [[ "$1" == "log" ]]; then shift; shift; shift; echo "$@"; fi; }
	gh() { echo ""; }
	git() { echo ""; }
	export -f gum gh git

	# shellcheck disable=SC2155
	eval "$(
		export _gh_ai_source_dir="$REPO_ROOT"
		# shellcheck source=../scripts/gh_cmd.sh
		source "$REPO_ROOT/scripts/gh_cmd.sh"
		# shellcheck source=../scripts/gh_pr.sh
		source "$REPO_ROOT/scripts/gh_pr.sh"
		declare -f _parse_pr_chat_args _show_pr_chat_help _gh_pr_chat _cmd_chat _cmd_render _split_on_separator _get_agent
	)"
}

# ---------------------------------------------------------------------------
# _parse_pr_chat_args
# ---------------------------------------------------------------------------

@test "_parse_pr_chat_args: captures PR number from positional arg" {
	local number="" description=""
	_parse_pr_chat_args number description 42

	[[ "$number" == "42" ]]
	[[ -z "$description" ]]
}

@test "_parse_pr_chat_args: strips leading # from PR number" {
	local number="" description=""
	_parse_pr_chat_args number description "#42"

	[[ "$number" == "42" ]]
}

@test "_parse_pr_chat_args: sets description from -d flag" {
	local number="" description=""
	_parse_pr_chat_args number description 42 -d "focus on security"

	[[ "$number" == "42" ]]
	[[ "$description" == "focus on security" ]]
}

@test "_parse_pr_chat_args: sets description from --description flag" {
	local number="" description=""
	_parse_pr_chat_args number description 42 --description "focus on security"

	[[ "$description" == "focus on security" ]]
}

@test "_parse_pr_chat_args: sets description from --description=value" {
	local number="" description=""
	_parse_pr_chat_args number description 42 --description="focus on security"

	[[ "$description" == "focus on security" ]]
}

@test "_parse_pr_chat_args: returns error when -d has no value" {
	local number="" description=""
	run _parse_pr_chat_args number description 42 -d

	[[ "$status" -eq 1 ]]
}

@test "_parse_pr_chat_args: returns error for unknown flags" {
	local number="" description=""
	run _parse_pr_chat_args number description --draft

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unknown flag '--draft'"* ]]
}

@test "_parse_pr_chat_args: returns error for unexpected non-numeric args" {
	local number="" description=""
	run _parse_pr_chat_args number description foo

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unexpected argument 'foo'"* ]]
}

@test "_parse_pr_chat_args: returns error for second positional arg" {
	local number="" description=""
	run _parse_pr_chat_args number description 42 99

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

	local number="" description=""
	_parse_pr_chat_args number description

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
		"pr diff") echo "diff --git a/file.txt b/file.txt" ;;
		"pr view") echo "Test PR Title" ;;
		"config get") ;;
		esac
	}
	export -f gh

	git() {
		case "$1 $2" in
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

@test "_gh_pr_chat: calls _cmd_chat with rendered preamble" {
	_setup_chat_mocks

	_cmd_chat() {
		printf 'PREAMBLE:%s\n' "$1"
		shift
		printf 'ARGS:%s\n' "$*"
	}

	run _gh_pr_chat 42

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"PREAMBLE:"* ]]
}

@test "_gh_pr_chat: passes args after -- to _cmd_chat" {
	_setup_chat_mocks

	_cmd_chat() {
		printf 'PREAMBLE:%s\n' "$1"
		shift
		printf 'PASSTHROUGH:%s\n' "$*"
	}

	run _gh_pr_chat 42 -- --model sonnet

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"PASSTHROUGH:--model sonnet"* ]]
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

@test "_gh_pr_chat: shows help with --help flag" {
	run _gh_pr_chat --help

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"pr chat"* ]]
}
