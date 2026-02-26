#!/usr/bin/env bats

# Unit and integration tests for gh ai pr review -d/--description flag
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_pr_review.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _gh_ai_source_dir="$REPO_ROOT"

	# Mock external commands not under test
	gum() { :; }
	gh() { echo ""; }
	git() { echo ""; }
	export -f gum gh git

	# Source gh_pr.sh inside a subshell and import only the function
	# definitions.  This prevents the `set -euo pipefail` at the top of
	# gh_pr.sh from leaking into the bats test runner, which would
	# cause pipefail-triggered deadlocks when a test assertion fails.
	# shellcheck disable=SC2155
	eval "$(
		export _gh_ai_source_dir="$REPO_ROOT"
		# shellcheck source=../scripts/gh_pr.sh
		source "$REPO_ROOT/scripts/gh_pr.sh"
		declare -f _parse_pr_review_args _show_pr_review_help _gh_pr_review
	)"
}

# ---------------------------------------------------------------------------
# T001: Flag parsing — -d/--description captured, excluded from passthrough
# ---------------------------------------------------------------------------

@test "T001: -d flag captures description and excludes it from passthrough args" {
	local number=""
	local description=""
	local args=()
	_parse_pr_review_args number description args -d "focus on security"

	[[ "$description" == "focus on security" ]]
	[[ ${#args[@]} -eq 0 ]]
}

@test "T001: --description flag captures description and excludes it from passthrough args" {
	local number=""
	local description=""
	local args=()
	_parse_pr_review_args number description args --description "improve readability"

	[[ "$description" == "improve readability" ]]
	[[ ${#args[@]} -eq 0 ]]
}

@test "T001: --description=value form captures description" {
	local number=""
	local description=""
	local args=()
	_parse_pr_review_args number description args --description="use imperative mood"

	[[ "$description" == "use imperative mood" ]]
	[[ ${#args[@]} -eq 0 ]]
}

@test "T001: -d flag does not bleed into passthrough args" {
	local number=""
	local description=""
	local args=()
	_parse_pr_review_args number description args --approve -d "context" --comment

	[[ "$description" == "context" ]]
	[[ ${#args[@]} -eq 2 ]]
	[[ "${args[0]}" == "--approve" ]]
	[[ "${args[1]}" == "--comment" ]]
}

@test "T001: PR number and -d flag both captured correctly" {
	local number=""
	local description=""
	local args=()
	_parse_pr_review_args number description args 42 -d "focus on security" --approve

	[[ "$number" == "42" ]]
	[[ "$description" == "focus on security" ]]
	[[ ${#args[@]} -eq 1 ]]
	[[ "${args[0]}" == "--approve" ]]
}

# ---------------------------------------------------------------------------
# T005: Existing AI-managed flags still stripped
# ---------------------------------------------------------------------------

@test "T005: --body flag is still stripped" {
	local number=""
	local description=""
	local args=()
	_parse_pr_review_args number description args --body "ignored body" --approve

	[[ -z "$description" ]]
	[[ ${#args[@]} -eq 1 ]]
	[[ "${args[0]}" == "--approve" ]]
}

@test "T005: -b flag is still stripped" {
	local number=""
	local description=""
	local args=()
	_parse_pr_review_args number description args -b "ignored" --comment

	[[ -z "$description" ]]
	[[ ${#args[@]} -eq 1 ]]
	[[ "${args[0]}" == "--comment" ]]
}

@test "T005: --body-file flag is still stripped" {
	local number=""
	local description=""
	local args=()
	_parse_pr_review_args number description args --body-file review.md --approve

	[[ -z "$description" ]]
	[[ ${#args[@]} -eq 1 ]]
	[[ "${args[0]}" == "--approve" ]]
}

@test "T005: -F flag is still stripped" {
	local number=""
	local description=""
	local args=()
	_parse_pr_review_args number description args -F review.md --comment

	[[ -z "$description" ]]
	[[ ${#args[@]} -eq 1 ]]
	[[ "${args[0]}" == "--comment" ]]
}

@test "T005: --body=value form is still stripped" {
	local number=""
	local description=""
	local args=()
	_parse_pr_review_args number description args --body="ignored" --approve

	[[ -z "$description" ]]
	[[ ${#args[@]} -eq 1 ]]
	[[ "${args[0]}" == "--approve" ]]
}

# ---------------------------------------------------------------------------
# T006: Edge cases
# ---------------------------------------------------------------------------

@test "T006: empty description leaves variable empty" {
	local number=""
	local description=""
	local args=()
	_parse_pr_review_args number description args -d ""

	[[ -z "$description" ]]
	[[ ${#args[@]} -eq 0 ]]
}

@test "T006: description with special characters is preserved" {
	local number=""
	local description=""
	local args=()
	_parse_pr_review_args number description args -d "fix: handle \$HOME and 'quotes' & <html>"

	[[ "$description" == 'fix: handle $HOME and '"'"'quotes'"'"' & <html>' ]]
}

@test "T006: no description flag leaves variable empty and passes all args" {
	local number=""
	local description=""
	local args=()
	_parse_pr_review_args number description args --approve --comment

	[[ -z "$description" ]]
	[[ ${#args[@]} -eq 2 ]]
	[[ "${args[0]}" == "--approve" ]]
	[[ "${args[1]}" == "--comment" ]]
}

@test "T006: -d and --description=value both work in same invocation (last wins)" {
	local number=""
	local description=""
	local args=()
	_parse_pr_review_args number description args -d "first" --description="second"

	[[ "$description" == "second" ]]
}

@test "T007: -d without value returns error" {
	local number=""
	local description=""
	local args=()
	run _parse_pr_review_args number description args -d

	[[ "$status" -eq 1 ]]
}

@test "T007: --description without value returns error" {
	local number=""
	local description=""
	local args=()
	run _parse_pr_review_args number description args --description

	[[ "$status" -eq 1 ]]
}
