#!/usr/bin/env bats

# Unit tests for gh ai issue create arg parsing
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_issue_create.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _gh_ai_source_dir="$REPO_ROOT"

	gum() { :; }
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
		declare -f _parse_issue_create_args _show_issue_create_help _gh_issue_create _split_on_separator
	)"
}

# ---------------------------------------------------------------------------
# T001: -d/--description captured
# ---------------------------------------------------------------------------

@test "T001: -d flag captures description" {
	local description=""
	_parse_issue_create_args description -d "Login page crashes"

	[[ "$description" == "Login page crashes" ]]
}

@test "T001: --description flag captures description" {
	local description=""
	_parse_issue_create_args description --description "Login page crashes"

	[[ "$description" == "Login page crashes" ]]
}

@test "T001: --description=value form captures description" {
	local description=""
	_parse_issue_create_args description --description="Login page crashes"

	[[ "$description" == "Login page crashes" ]]
}

# ---------------------------------------------------------------------------
# T006: Edge cases
# ---------------------------------------------------------------------------

@test "T006: no flags leaves description empty" {
	local description=""
	_parse_issue_create_args description

	[[ -z "$description" ]]
}

@test "T006: description with special characters is preserved" {
	local description=""
	local expected='fix: handle $HOME and '"'"'quotes'"'"' & <html>'
	_parse_issue_create_args description -d "$expected"

	[[ "$description" == "$expected" ]]
}

@test "T006: -d and --description=value both work (last wins)" {
	local description=""
	_parse_issue_create_args description -d "first" --description="second"

	[[ "$description" == "second" ]]
}

# ---------------------------------------------------------------------------
# T007: Missing value errors
# ---------------------------------------------------------------------------

@test "T007: -d without value returns error" {
	local description=""
	run _parse_issue_create_args description -d

	[[ "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# Unknown flags before -- produce an error
# ---------------------------------------------------------------------------

@test "unknown flag before -- returns error with hint" {
	local description=""
	run _parse_issue_create_args description --label bug

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"use -- to pass flags to gh issue create"* ]]
}
