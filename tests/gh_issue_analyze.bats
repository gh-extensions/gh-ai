#!/usr/bin/env bats

# Unit tests for gh ai issue analyze arg parsing and integration
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_issue_analyze.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _gh_ai_source_dir="$REPO_ROOT"
	export HOME="$BATS_TEST_TMPDIR"
	unset XDG_STATE_HOME

	_GH_AI_ARGS=()

	gum() { if [[ "$1" == "log" ]]; then shift; shift; shift; echo "$@"; fi; }
	gh() { echo ""; }
	git() { echo ""; }
	export -f gum gh git

	# shellcheck disable=SC2155
	eval "$(
		export _gh_ai_source_dir="$REPO_ROOT"
		# shellcheck source=../scripts/gh_cmd.sh
		source "$REPO_ROOT/scripts/gh_cmd.sh"
		# shellcheck source=../scripts/gh_issue.sh
		source "$REPO_ROOT/scripts/gh_issue.sh"
		declare -f _extract_issue_number _parse_analyze_args _parse_issue_analyze_args _extract_ai_arg \
			_show_issue_analyze_help _show_issue_help _gh_issue_analyze _gh_issue \
			_prepare_issue_analyze_context _prepare_issue_context \
			_cmd_chat _cmd_ask _cmd_render _get_agent \
			_gh_context_base_dir _resolve_context_dir _create_context_dir _save_context_file \
			_chat_claude _chat_codex _chat_gemini _ask_claude _ask_codex _ask_gemini _gh_config_ai_model
	)"
}

# ---------------------------------------------------------------------------
# _parse_issue_analyze_args
# ---------------------------------------------------------------------------

@test "_parse_issue_analyze_args: captures issue number from positional arg" {
	local number="" description="" interactive=""
	_parse_issue_analyze_args number description interactive 42

	[[ "$number" == "42" ]]
}

@test "_parse_issue_analyze_args: sets description from -d flag" {
	local number="" description="" interactive=""
	_parse_issue_analyze_args number description interactive 42 -d "focus on auth"

	[[ "$description" == "focus on auth" ]]
}

@test "_parse_issue_analyze_args: sets interactive from -i flag" {
	local number="" description="" interactive=""
	_parse_issue_analyze_args number description interactive 42 -i

	[[ "$interactive" == "true" ]]
}

@test "_parse_issue_analyze_args: extracts issue number from canonical GitHub URL" {
	local number="" description="" interactive=""
	_parse_issue_analyze_args number description interactive "https://github.com/owner/repo/issues/42"

	[[ "$number" == "42" ]]
}

@test "_parse_issue_analyze_args: extracts issue number from URL with -i" {
	local number="" description="" interactive=""
	_parse_issue_analyze_args number description interactive "https://github.com/owner/repo/issues/42" -i

	[[ "$number" == "42" ]]
	[[ "$interactive" == "true" ]]
}

@test "_parse_issue_analyze_args: returns error for unknown flags" {
	local number="" description="" interactive=""
	run _parse_issue_analyze_args number description interactive --bogus

	[[ "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# _show_issue_analyze_help
# ---------------------------------------------------------------------------

@test "_show_issue_analyze_help: prints help text" {
	run _show_issue_analyze_help

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"issue analyze"* ]]
	[[ "$output" == *"-i, --interactive"* ]]
}

# ---------------------------------------------------------------------------
# Integration tests
# ---------------------------------------------------------------------------

_setup_issue_mocks() {
	gh() {
		case "$1 $2" in
		"issue view")
			printf '{"title":"Test Issue","body":"issue body","labels":[{"name":"bug"}],"comments":[],"url":"https://github.com/owner/repo/issues/42","updatedAt":"2024-01-01T00:00:00Z"}'
			;;
		"config get") ;;
		esac
	}
	export -f gh

	gum() {
		case "$1" in
		spin)
			while [[ $# -gt 0 && "$1" != "--" ]]; do shift; done
			[[ $# -gt 0 ]] && shift
			case "${1:-}" in
			*/gh_cmd.sh)
				if [[ "$2" == "ask" ]]; then
					printf '## Summary\nIssue summary.\n'
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

@test "_gh_issue_analyze: errors when no issue number provided" {
	run _gh_issue_analyze

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"No issue number"* ]]
}

@test "_gh_issue_analyze: routes through _cmd_chat with -i" {
	_setup_issue_mocks

	_cmd_chat() {
		printf '%s' "$1"
	}
	export -f _cmd_chat

	run _gh_issue_analyze 42 -i

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"how they'd like to proceed"* ]]
	[[ "$output" == *"/.local/state/gh/ai/context/issue-42/issue_body.md"* ]]
}

@test "_gh_issue_analyze: one-shot prompt does not include trailing question" {
	_setup_issue_mocks

	# Replace gum spin to capture the prompt sent to ask
	gum() {
		case "$1" in
		spin)
			while [[ $# -gt 0 && "$1" != "--" ]]; do shift; done
			[[ $# -gt 0 ]] && shift
			case "${1:-}" in
			*/gh_cmd.sh)
				if [[ "$2" == "ask" ]]; then
					cat
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

	run _gh_issue_analyze 42

	[[ "$status" -eq 0 ]]
	[[ "$output" != *"how they'd like to proceed"* ]]
}

@test "_gh_issue_analyze: shows help with --help flag" {
	run _gh_issue_analyze --help

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"issue analyze"* ]]
}

# ---------------------------------------------------------------------------
# Removed subcommands route to "unknown command"
# ---------------------------------------------------------------------------

@test "_gh_issue: rejects removed 'plan' subcommand" {
	gum() { echo "GUM:$*"; }
	export -f gum

	run _gh_issue plan 42

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unknown issue command"* ]]
}

@test "_gh_issue: rejects removed 'chat' subcommand" {
	gum() { echo "GUM:$*"; }
	export -f gum

	run _gh_issue chat 42

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unknown issue command"* ]]
}
