#!/usr/bin/env bats

# Unit tests for gh ai run explain arg parsing and integration
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_run_explain.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _gh_ai_source_dir="$REPO_ROOT"

	gum() { if [[ "$1" == "log" ]]; then shift; shift; shift; echo "$@"; fi; }
	gh() { echo ""; }
	export -f gum gh

	# shellcheck disable=SC2155
	eval "$(
		export _gh_ai_source_dir="$REPO_ROOT"
		# shellcheck source=../scripts/gh_run.sh
		source "$REPO_ROOT/scripts/gh_run.sh"
		# shellcheck source=../scripts/gh_cmd.sh
		source "$REPO_ROOT/scripts/gh_cmd.sh"
		declare -f _parse_run_args _parse_run_explain_args _show_run_explain_help _gh_run_explain \
			_prepare_run_context _prepare_run_explain_context _resolve_context_dir _create_context_dir _save_context_file \
			_cmd_render _cmd_ask _get_agent
	)"
}

# ---------------------------------------------------------------------------
# _parse_run_explain_args
# ---------------------------------------------------------------------------

@test "_parse_run_explain_args: captures run ID from positional arg" {
	local id=""
	_parse_run_explain_args id 12345678

	[[ "$id" == "12345678" ]]
}

@test "_parse_run_explain_args: strips leading # from run ID" {
	local id=""
	_parse_run_explain_args id "#12345678"

	[[ "$id" == "12345678" ]]
}

@test "_parse_run_explain_args: defaults to empty when no args given" {
	local id=""
	_parse_run_explain_args id

	[[ -z "$id" ]]
}

@test "_parse_run_explain_args: returns error for unknown flags" {
	local id=""
	run _parse_run_explain_args id --failed

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unknown flag '--failed'"* ]]
}

@test "_parse_run_explain_args: returns error for unexpected non-numeric arg" {
	local id=""
	run _parse_run_explain_args id foo

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unexpected argument 'foo'"* ]]
}

@test "_parse_run_explain_args: returns error for second positional arg" {
	local id=""
	run _parse_run_explain_args id 12345678 99999999

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unexpected argument '99999999'"* ]]
}

# ---------------------------------------------------------------------------
# Helpers shared by _gh_run_explain integration tests
# ---------------------------------------------------------------------------

_setup_explain_mocks() {
	gh() {
		case "$1 $2" in
		# First call: metadata JSON; second call: log (also returns this non-empty string)
		"run view") printf '{"displayTitle":"Test Run","conclusion":"failure","url":"https://github.com/owner/repo/actions/runs/123","event":"push","headBranch":"main","headSha":"abc123def456","jobs":[]}' ;;
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
			*/gh_cmd.sh) printf '## Root Cause\n\nTest failure in build step.\n\n## Fix\n\n- Fix the test\n' ;;
			*) "$@" ;;
			esac
			;;
		log) ;;
		esac
	}
	export -f gum
}

@test "_gh_run_explain: prints explanation to stdout" {
	_setup_explain_mocks

	run _gh_run_explain 12345678

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"Root Cause"* ]]
	[[ "$output" == *"Fix the test"* ]]
}

@test "_gh_run_explain: errors when no run ID provided" {
	_setup_explain_mocks

	run _gh_run_explain

	[[ "$status" -eq 1 ]]
}

@test "_gh_run_explain: errors when metadata fetch fails" {
	gh() {
		case "$1 $2" in
		"run view") ;;
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

	run _gh_run_explain 12345678

	[[ "$status" -eq 1 ]]
}

@test "_gh_run_explain: errors when AI output is empty" {
	gh() {
		case "$1 $2" in
		"run view") printf '{"displayTitle":"Test Run","conclusion":"failure","url":"https://github.com/owner/repo/actions/runs/123","event":"push","headBranch":"main","headSha":"abc123def456","jobs":[]}' ;;
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
			*/gh_cmd.sh) ;;
			*) "$@" ;;
			esac
			;;
		log) ;;
		esac
	}
	export -f gum

	run _gh_run_explain 12345678

	[[ "$status" -eq 1 ]]
}
