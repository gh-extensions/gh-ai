#!/usr/bin/env bats

# Unit tests for gh ai issue plan arg parsing and integration
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_issue_plan.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _gh_ai_source_dir="$REPO_ROOT"

	gum() { :; }
	gh() { echo ""; }
	export -f gum gh

	# shellcheck disable=SC2155
	eval "$(
		export _gh_ai_source_dir="$REPO_ROOT"
		# shellcheck source=../scripts/gh_issue.sh
		source "$REPO_ROOT/scripts/gh_issue.sh"
		# shellcheck source=../scripts/gh_cmd.sh
		source "$REPO_ROOT/scripts/gh_cmd.sh"
		declare -f _parse_issue_plan_args _show_issue_plan_help _gh_issue_plan _get_title _get_body
	)"
}

@test "_parse_issue_plan_args: captures issue number from positional arg" {
	local number="" description=""
	_parse_issue_plan_args number description 42

	[[ "$number" == "42" ]]
	[[ -z "$description" ]]
}

@test "_parse_issue_plan_args: sets description from -d flag" {
	local number="" description=""
	_parse_issue_plan_args number description 42 -d "focus on auth"

	[[ "$number" == "42" ]]
	[[ "$description" == "focus on auth" ]]
}

@test "_parse_issue_plan_args: sets description from --description flag" {
	local number="" description=""
	_parse_issue_plan_args number description 42 --description "focus on auth"

	[[ "$description" == "focus on auth" ]]
}

@test "_parse_issue_plan_args: sets description from --description=value" {
	local number="" description=""
	_parse_issue_plan_args number description 42 --description="focus on auth"

	[[ "$description" == "focus on auth" ]]
}

@test "_parse_issue_plan_args: returns error when -d has no value" {
	local number="" description=""
	run _parse_issue_plan_args number description 42 -d

	[[ "$status" -eq 1 ]]
}

@test "_parse_issue_plan_args: returns error for unknown flags" {
	local number="" description=""
	run _parse_issue_plan_args number description --draft

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unknown flag '--draft'"* ]]
}

@test "_parse_issue_plan_args: returns error for unexpected non-numeric args" {
	local number="" description=""
	run _parse_issue_plan_args number description foo

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unexpected argument 'foo'"* ]]
}

@test "_parse_issue_plan_args: returns error for second positional arg" {
	local number="" description=""
	run _parse_issue_plan_args number description 42 99

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unexpected argument '99'"* ]]
}

# ---------------------------------------------------------------------------
# Helpers shared by _gh_issue_plan integration tests
# ---------------------------------------------------------------------------

# _setup_plan_mocks sets up gh/gum mocks that return appropriate fake values
# for the full plan workflow.
#
# Usage: _setup_plan_mocks
_setup_plan_mocks() {
	gh() {
		case "$1 $2" in
		"issue view") printf "gh_issue_title='Test Issue'\ngh_issue_body='Issue body'\ngh_issue_labels=''\ngh_issue_comments=''";;
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
			*/gh_cmd.sh) printf '# Test Plan Title\n\n## Plan\n\n- [ ] T001 - Step 1\n';;
			*) "$@";;
			esac
			;;
		log) ;;
		esac
	}
	export -f gum
}

@test "_gh_issue_plan: prints plan to stdout" {
	_setup_plan_mocks

	run _gh_issue_plan 42

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"# Test Plan Title"* ]]
	[[ "$output" == *"T001"* ]]
}

@test "_gh_issue_plan: errors when no issue number provided" {
	_setup_plan_mocks

	run _gh_issue_plan

	[[ "$status" -eq 1 ]]
}

@test "_gh_issue_plan: errors when issue fetch fails" {
	gh() {
		case "$1 $2" in
		"issue view") ;;
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

	run _gh_issue_plan 42

	[[ "$status" -eq 1 ]]
}

@test "_gh_issue_plan: errors when AI output is empty" {
	gh() {
		case "$1 $2" in
		"issue view") printf "gh_issue_title='Test Issue'\ngh_issue_body='Issue body'\ngh_issue_labels=''\ngh_issue_comments=''";;
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
			*) "$@";;
			esac
			;;
		log) ;;
		esac
	}
	export -f gum

	run _gh_issue_plan 42

	[[ "$status" -eq 1 ]]
}
