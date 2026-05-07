#!/usr/bin/env bats

# Unit tests for gh ai pr analyze arg parsing and integration
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_pr_analyze.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _gh_ai_source_dir="$REPO_ROOT"
	export HOME="$BATS_TEST_TMPDIR"
	unset XDG_STATE_HOME

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
		declare -f _extract_pr_number _parse_analyze_args _parse_pr_analyze_args _extract_ai_arg \
			_show_pr_analyze_help _show_pr_help _gh_pr_analyze _gh_pr _detect_pr_number \
			_prepare_pr_analyze_context _prepare_pr_diff_context \
			_cmd_chat _cmd_ask _cmd_render _get_agent _git_repo_path \
			_gh_context_base_dir _resolve_context_dir _create_context_dir _save_context_file \
			_chat_claude _chat_codex _chat_gemini _ask_claude _ask_codex _ask_gemini _gh_config_ai_model
	)"
}

# ---------------------------------------------------------------------------
# _parse_pr_analyze_args
# ---------------------------------------------------------------------------

@test "_parse_pr_analyze_args: captures PR number from positional arg" {
	local number="" description="" interactive=""
	_parse_pr_analyze_args number description interactive 42

	[[ "$number" == "42" ]]
	[[ -z "$description" ]]
	[[ -z "$interactive" ]]
}

@test "_parse_pr_analyze_args: strips leading # from PR number" {
	local number="" description="" interactive=""
	_parse_pr_analyze_args number description interactive "#42"

	[[ "$number" == "42" ]]
}

@test "_parse_pr_analyze_args: sets description from -d flag" {
	local number="" description="" interactive=""
	_parse_pr_analyze_args number description interactive 42 -d "focus on security"

	[[ "$number" == "42" ]]
	[[ "$description" == "focus on security" ]]
}

@test "_parse_pr_analyze_args: sets interactive from -i flag" {
	local number="" description="" interactive=""
	_parse_pr_analyze_args number description interactive 42 -i

	[[ "$interactive" == "true" ]]
}

@test "_parse_pr_analyze_args: sets interactive from --interactive flag" {
	local number="" description="" interactive=""
	_parse_pr_analyze_args number description interactive 42 --interactive

	[[ "$interactive" == "true" ]]
}

@test "_parse_pr_analyze_args: combines -d and -i" {
	local number="" description="" interactive=""
	_parse_pr_analyze_args number description interactive 42 -d "review carefully" -i

	[[ "$number" == "42" ]]
	[[ "$description" == "review carefully" ]]
	[[ "$interactive" == "true" ]]
}

@test "_parse_pr_analyze_args: returns error for unknown flags" {
	local number="" description="" interactive=""
	run _parse_pr_analyze_args number description interactive --draft

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unknown flag '--draft'"* ]]
}

@test "_parse_pr_analyze_args: extracts PR number from canonical GitHub URL" {
	local number="" description="" interactive=""
	_parse_pr_analyze_args number description interactive "https://github.com/owner/repo/pull/42"

	[[ "$number" == "42" ]]
}

@test "_parse_pr_analyze_args: extracts PR number from URL with query string" {
	local number="" description="" interactive=""
	_parse_pr_analyze_args number description interactive "https://github.com/owner/repo/pull/42?tab=files" -i

	[[ "$number" == "42" ]]
	[[ "$interactive" == "true" ]]
}

# ---------------------------------------------------------------------------
# _show_pr_analyze_help
# ---------------------------------------------------------------------------

@test "_show_pr_analyze_help: prints help text" {
	run _show_pr_analyze_help

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"pr analyze"* ]]
	[[ "$output" == *"-i, --interactive"* ]]
}

# ---------------------------------------------------------------------------
# Helpers shared by _gh_pr_analyze integration tests
# ---------------------------------------------------------------------------

_setup_analyze_mocks() {
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
			case "${1:-}" in
			*/gh_cmd.sh)
				if [[ "$2" == "ask" ]]; then
					printf '## Summary\nThis PR does things.\n'
				else
					"$@"
				fi
				;;
			*) "$@" ;;
			esac
			;;
		log) ;;
		esac
	}
	export -f gum
}

@test "_gh_pr_analyze: prints analysis to stdout in one-shot mode" {
	_setup_analyze_mocks

	run _gh_pr_analyze 42

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"Summary"* ]]
}

@test "_gh_pr_analyze: routes through _cmd_chat with -i" {
	_setup_analyze_mocks

	_cmd_chat() {
		printf 'CHAT_PROMPT_LEN:%d\n' "${#1}"
		printf 'PROMPT_HEAD:%.20s\n' "$1"
	}
	export -f _cmd_chat

	run _gh_pr_analyze 42 -i

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"CHAT_PROMPT_LEN:"* ]]
}

@test "_gh_pr_analyze: -i sets GH_AI_INTERACTIVE_INSTRUCTION in prompt" {
	_setup_analyze_mocks

	_cmd_chat() {
		printf '%s' "$1"
	}
	export -f _cmd_chat

	run _gh_pr_analyze 42 -i

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"how they'd like to proceed"* ]]
}

@test "_gh_pr_analyze: prompt references persistent session dir path" {
	_setup_analyze_mocks

	_cmd_chat() {
		printf '%s' "$1"
	}
	export -f _cmd_chat

	run _gh_pr_analyze 42 -i

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"/.local/state/gh/ai/context/pull-42/pr_diff.patch"* ]]
}

@test "_gh_pr_analyze: errors when no PR number provided and none auto-detectable" {
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

	run _gh_pr_analyze

	[[ "$status" -eq 1 ]]
}

@test "_gh_pr_analyze: shows help with --help flag" {
	run _gh_pr_analyze --help

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"pr analyze"* ]]
}

# ---------------------------------------------------------------------------
# Removed subcommands route to "unknown command"
# ---------------------------------------------------------------------------

@test "_gh_pr: rejects removed 'explain' subcommand" {
	gum() { echo "GUM:$*"; }
	export -f gum

	run _gh_pr explain 42

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unknown pr command"* ]]
}

@test "_gh_pr: rejects removed 'chat' subcommand" {
	gum() { echo "GUM:$*"; }
	export -f gum

	run _gh_pr chat 42

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unknown pr command"* ]]
}
