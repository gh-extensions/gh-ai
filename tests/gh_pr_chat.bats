#!/usr/bin/env bats

# Unit tests for gh ai pr chat arg parsing and integration
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_pr_chat.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _gh_ai_source_dir="$REPO_ROOT"
	export HOME="$BATS_TEST_TMPDIR"
	unset XDG_STATE_HOME

	# Initialize global AI args array (set per-test when needed)
	_GH_AI_ARGS=()

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
		export _gh_ai_source_dir="$REPO_ROOT"
		# shellcheck source=../scripts/gh_cmd.sh
		source "$REPO_ROOT/scripts/gh_cmd.sh"
		# shellcheck source=../scripts/gh_pr.sh
		source "$REPO_ROOT/scripts/gh_pr.sh"
		declare -f _extract_pr_number _parse_chat_args _parse_pr_chat_args _extract_ai_arg _show_pr_chat_help _gh_pr_chat _detect_pr_number \
			_prepare_pr_chat_context _prepare_pr_diff_context \
			_cmd_chat _cmd_render _get_agent _git_repo_path _gh_session_base_dir _resolve_context_dir _create_context_dir _save_context_file \
			_chat_claude _chat_codex _chat_gemini _ask_claude _ask_codex _ask_gemini _gh_config_ai_model
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
		printf 'PROMPT:%s\n' "$1"
		shift 1
		printf 'ARGS:%s\n' "$*"
	}
	export -f _cmd_chat

	run _gh_pr_chat 42

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"PROMPT:"* ]]
	[[ "$output" == *"/.local/state/gh/ai/sessions/pull-42"* ]]
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

@test "_gh_pr_chat: always renders prompt" {
	_setup_chat_mocks

	_cmd_chat() {
		printf 'PROMPT:%s\n' "$1"
		shift 1
		printf 'ARGS:%s\n' "$*"
	}
	export -f _cmd_chat

	run _gh_pr_chat 42

	[[ "$status" -eq 0 ]]
	# Prompt should be rendered
	[[ "$output" == *"PROMPT:"* ]]
	[[ "$output" == *"Test PR"* ]]
}

@test "_gh_pr_chat: shows help with --help flag" {
	run _gh_pr_chat --help

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"pr chat"* ]]
}

# ---------------------------------------------------------------------------
# Passthrough parsing and forwarding
# ---------------------------------------------------------------------------

@test "_gh_pr_chat: forwards _GH_AI_ARGS to _cmd_chat via claude" {
	_setup_chat_mocks

	# Mock claude to capture args
	claude() { printf 'CLAUDE_ARGS:%s\n' "$*"; }
	export -f claude

	_GH_AI_ARGS=(--model sonnet --verbose)
	run _gh_pr_chat 42

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"--model sonnet --verbose"* ]]
}
