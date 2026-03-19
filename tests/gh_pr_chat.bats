#!/usr/bin/env bats

# Unit tests for gh claude pr chat arg parsing and integration
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_pr_chat.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _gh_claude_source_dir="$REPO_ROOT"
	export HOME="$BATS_TEST_TMPDIR"
	unset XDG_STATE_HOME

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
		# shellcheck source=../scripts/gh_cmd.sh
		source "$REPO_ROOT/scripts/gh_cmd.sh"
		# shellcheck source=../scripts/gh_pr.sh
		source "$REPO_ROOT/scripts/gh_pr.sh"
		declare -f _extract_pr_number _parse_chat_args _parse_pr_chat_args _extract_chat_passthrough _show_pr_chat_help _gh_pr_chat _detect_pr_number \
			_cmd_chat _cmd_render _split_on_separator _get_agent _git_repo_path _resolve_chat_session \
			_prepare_pr_chat_context _prepare_pr_diff_context _resolve_context_dir _create_context_dir _save_context_file \
			_gh_session_base_dir
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

@test "_parse_pr_chat_args: extracts PR number from canonical GitHub URL" {
	local number="" description=""
	_parse_pr_chat_args number description "https://github.com/owner/repo/pull/42"

	[[ "$number" == "42" ]]
	[[ -z "$description" ]]
}

@test "_parse_pr_chat_args: extracts PR number from URL with query string" {
	local number="" description=""
	_parse_pr_chat_args number description "https://github.com/owner/repo/pull/42?tab=files" -d "focus on security"

	[[ "$number" == "42" ]]
	[[ "$description" == "focus on security" ]]
}

@test "_parse_pr_chat_args: returns error for non-GitHub URL" {
	local number="" description=""
	run _parse_pr_chat_args number description "https://gitlab.com/owner/repo/merge_requests/42"

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unexpected argument"* ]]
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
		"pr view") printf '{"title":"Test PR Title","body":"PR body","headRefName":"feature-branch","commits":[{"messageHeadline":"Test commit"}],"url":"https://github.com/owner/repo/pull/42"}' ;;
		"config get") ;;
		esac
	}
	export -f gh

	git() {
		case "$1 $2" in
		"rev-parse --show-toplevel") echo "$BATS_TEST_TMPDIR" ;;
		"rev-parse --abbrev-ref") echo "" ;;
		"rev-parse --git-common-dir") echo "$BATS_TEST_TMPDIR/.git" ;;
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

	uuidgen() { echo "00000000-0000-0000-0000-000000000042"; }
	export -f uuidgen

}

@test "_gh_pr_chat: calls _cmd_chat with rendered prompt and session args" {
	_setup_chat_mocks

	_cmd_chat() {
		printf 'URL:%s\n' "$1"
		printf 'PROMPT:%s\n' "$2"
		shift 2
		printf 'ARGS:%s\n' "$*"
	}
	export -f _cmd_chat

	run _gh_pr_chat 42

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"PROMPT:"* ]]
	[[ "$output" == *"--session-id"* ]]
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
		"pr view") printf '{"title":"Test PR Title","body":"PR body","headRefName":"feature-branch","commits":[]}' ;;
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

@test "_gh_pr_chat: resumes session when -- --resume is passed" {
	_setup_chat_mocks

	# Create a valid session dir so --resume finds it
	local base="$BATS_TEST_TMPDIR/.local/state/gh/claude/sessions"
	mkdir -p "$base/abc123"
	printf 'pull-42' >"$base/abc123/chat.id"

	_cmd_chat() {
		printf 'URL:%s\n' "$1"
		printf 'PROMPT:%s\n' "$2"
		shift 2
		printf 'ARGS:%s\n' "$*"
	}
	export -f _cmd_chat

	run _gh_pr_chat 42 -- --resume abc123

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"--resume"* ]]
	# No prompt rendered on resume
	[[ "$output" != *"Test PR Title"* ]]
}

@test "_gh_pr_chat: resumes session when -- --session-id is reused" {
	_setup_chat_mocks

	# Pre-create session dir so --session-id triggers resume (is_new="")
	local base="$BATS_TEST_TMPDIR/.local/state/gh/claude/sessions"
	mkdir -p "$base/my-review"
	printf 'pull-42' >"$base/my-review/chat.id"

	_cmd_chat() {
		printf 'URL:%s\n' "$1"
		printf 'PROMPT:%s\n' "$2"
		shift 2
		printf 'ARGS:%s\n' "$*"
	}
	export -f _cmd_chat

	run _gh_pr_chat 42 -- --session-id my-review

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"--session-id my-review"* ]]
	# No prompt rendered on resume
	[[ "$output" != *"Test PR Title"* ]]
}

@test "_gh_pr_chat: shows help with --help flag" {
	run _gh_pr_chat --help

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"pr chat"* ]]
}

# ---------------------------------------------------------------------------
# Passthrough parsing and forwarding
# ---------------------------------------------------------------------------

@test "_gh_pr_chat: forwards passthrough args to _cmd_chat" {
	_setup_chat_mocks

	_cmd_chat() {
		printf 'URL:%s\n' "$1"
		printf 'PROMPT:%s\n' "$2"
		shift 2
		printf 'ARGS:%s\n' "$*"
	}
	export -f _cmd_chat

	run _gh_pr_chat 42 -- --model sonnet --verbose

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"--model sonnet --verbose"* ]]
}

@test "_gh_pr_chat: accepts --session-id in passthrough for new session" {
	_setup_chat_mocks

	_cmd_chat() {
		printf 'URL:%s\n' "$1"
		shift 2
		printf 'ARGS:%s\n' "$*"
	}
	export -f _cmd_chat

	run _gh_pr_chat 42 -- --session-id my-review

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"--session-id my-review"* ]]
}
