#!/usr/bin/env bats

# Unit tests for gh ai pr explain arg parsing and integration
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_pr_explain.bats

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
		declare -f _parse_pr_args _detect_pr_number _parse_pr_explain_args _show_pr_explain_help _gh_pr_explain \
			_prepare_pr_diff_context _prepare_pr_explain_context _resolve_context_dir _create_context_dir _save_context_file \
			_split_on_separator _cmd_render _cmd_ask _get_agent
	)"
}

# ---------------------------------------------------------------------------
# _parse_pr_explain_args
# ---------------------------------------------------------------------------

@test "_parse_pr_explain_args: captures PR number from positional arg" {
	local number=""
	_parse_pr_explain_args number 42

	[[ "$number" == "42" ]]
}

@test "_parse_pr_explain_args: strips leading # from PR number" {
	local number=""
	_parse_pr_explain_args number "#42"

	[[ "$number" == "42" ]]
}

@test "_parse_pr_explain_args: returns error for unknown flags" {
	local number=""
	run _parse_pr_explain_args number --draft

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unknown flag '--draft'"* ]]
}

@test "_parse_pr_explain_args: returns error for unexpected non-numeric arg" {
	local number=""
	run _parse_pr_explain_args number foo

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unexpected argument 'foo'"* ]]
}

@test "_parse_pr_explain_args: returns error for second positional arg" {
	local number=""
	run _parse_pr_explain_args number 42 99

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unexpected argument '99'"* ]]
}

# ---------------------------------------------------------------------------
# Helpers shared by _gh_pr_explain integration tests
# ---------------------------------------------------------------------------

_setup_explain_mocks() {
	gh() {
		case "$1 $2" in
		"pr diff") echo "diff --git a/file.txt b/file.txt" ;;
		"pr view") printf '{"title":"Test PR Title","body":"PR body","headRefName":"feature-branch","commits":[{"messageHeadline":"Test commit"}]}' ;;
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
			case "${1:-}" in
			*/gh_cmd.sh) printf '## Summary\n\nThis PR does things.\n\n## What Changed\n\n- Changed stuff\n' ;;
			*) "$@" ;;
			esac
			;;
		log) ;;
		esac
	}
	export -f gum
}

@test "_gh_pr_explain: prints explanation to stdout" {
	_setup_explain_mocks

	run _gh_pr_explain 42

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"Summary"* ]]
	[[ "$output" == *"Changed stuff"* ]]
}

@test "_gh_pr_explain: errors when no PR number provided" {
	_setup_explain_mocks

	# Override gh to return empty for auto-detect
	gh() {
		case "$1 $2" in
		"pr view") ;;
		"config get") ;;
		esac
	}
	export -f gh

	run _gh_pr_explain

	[[ "$status" -eq 1 ]]
}

@test "_gh_pr_explain: errors when diff is empty" {
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

	run _gh_pr_explain 42

	[[ "$status" -eq 1 ]]
}

@test "_gh_pr_explain: errors when AI output is empty" {
	gh() {
		case "$1 $2" in
		"pr diff") echo "diff --git a/file.txt b/file.txt" ;;
		"pr view") printf '{"title":"Test PR Title","body":"PR body","headRefName":"feature-branch","commits":[]}' ;;
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
			case "${1:-}" in
			*/gh_cmd.sh) ;;
			*) "$@" ;;
			esac
			;;
		log) ;;
		esac
	}
	export -f gum

	run _gh_pr_explain 42

	[[ "$status" -eq 1 ]]
}
