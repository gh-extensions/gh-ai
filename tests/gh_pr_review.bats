#!/usr/bin/env bats

# Unit tests for gh ai pr review arg parsing
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

	# shellcheck disable=SC2155
	eval "$(
		export _gh_ai_source_dir="$REPO_ROOT"
		# shellcheck source=../scripts/gh_cmd.sh
		source "$REPO_ROOT/scripts/gh_cmd.sh"
		# shellcheck source=../scripts/gh_pr.sh
		source "$REPO_ROOT/scripts/gh_pr.sh"
		declare -f _parse_pr_review_args _show_pr_review_help _gh_pr_review _split_on_separator
	)"
}

# ---------------------------------------------------------------------------
# T001: -d/--description captured
# ---------------------------------------------------------------------------

@test "T001: -d flag captures description" {
	local number=""
	local description=""
	_parse_pr_review_args number description -d "focus on security"

	[[ "$description" == "focus on security" ]]
}

@test "T001: --description flag captures description" {
	local number=""
	local description=""
	_parse_pr_review_args number description --description "improve readability"

	[[ "$description" == "improve readability" ]]
}

@test "T001: --description=value form captures description" {
	local number=""
	local description=""
	_parse_pr_review_args number description --description="use imperative mood"

	[[ "$description" == "use imperative mood" ]]
}

@test "T001: PR number and -d flag both captured correctly" {
	local number=""
	local description=""
	_parse_pr_review_args number description 42 -d "focus on security"

	[[ "$number" == "42" ]]
	[[ "$description" == "focus on security" ]]
}

# ---------------------------------------------------------------------------
# T006: Edge cases
# ---------------------------------------------------------------------------

@test "T006: empty description leaves variable empty" {
	local number=""
	local description=""
	_parse_pr_review_args number description -d ""

	[[ -z "$description" ]]
}

@test "T006: description with special characters is preserved" {
	local number=""
	local description=""
	local expected='fix: handle $HOME and '"'"'quotes'"'"' & <html>'
	_parse_pr_review_args number description -d "$expected"

	[[ "$description" == "$expected" ]]
}

@test "T006: no description flag leaves variable empty" {
	local number=""
	local description=""
	_parse_pr_review_args number description

	[[ -z "$description" ]]
}

@test "T006: -d and --description=value both work in same invocation (last wins)" {
	local number=""
	local description=""
	_parse_pr_review_args number description -d "first" --description="second"

	[[ "$description" == "second" ]]
}

@test "T007: -d without value returns error" {
	local number=""
	local description=""
	run _parse_pr_review_args number description -d

	[[ "$status" -eq 1 ]]
}

@test "T007: --description without value returns error" {
	local number=""
	local description=""
	run _parse_pr_review_args number description --description

	[[ "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# Unknown flags before -- produce an error
# ---------------------------------------------------------------------------

@test "unknown flag before -- returns error with hint" {
	local number=""
	local description=""
	run _parse_pr_review_args number description --approve

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"use -- to pass flags to gh pr review"* ]]
}
