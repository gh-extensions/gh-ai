#!/usr/bin/env bats

# Unit tests for gh ai pr edit arg parsing
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_pr_edit.bats

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
		# shellcheck source=../scripts/gh_pr.sh
		source "$REPO_ROOT/scripts/gh_pr.sh"
		declare -f _parse_pr_edit_args _show_pr_edit_help _gh_pr_edit _split_on_separator
	)"
}

# ---------------------------------------------------------------------------
# T001: -d/--description captured
# ---------------------------------------------------------------------------

@test "T001: -d flag captures description" {
	local number=""
	local description=""
	_parse_pr_edit_args number description -d "add testing section"

	[[ "$description" == "add testing section" ]]
}

@test "T001: --description flag captures description" {
	local number=""
	local description=""
	_parse_pr_edit_args number description --description "fix summary"

	[[ "$description" == "fix summary" ]]
}

@test "T001: --description=value form captures description" {
	local number=""
	local description=""
	_parse_pr_edit_args number description --description="improve wording"

	[[ "$description" == "improve wording" ]]
}

# ---------------------------------------------------------------------------
# T002: PR number captured from positional arg
# ---------------------------------------------------------------------------

@test "T002: PR number captured as first numeric arg" {
	local number=""
	local description=""
	_parse_pr_edit_args number description 42 -d "fix summary"

	[[ "$number" == "42" ]]
	[[ "$description" == "fix summary" ]]
}

@test "T002: PR number alone is captured" {
	local number=""
	local description=""
	_parse_pr_edit_args number description 42

	[[ "$number" == "42" ]]
}

# ---------------------------------------------------------------------------
# T006: Edge cases
# ---------------------------------------------------------------------------

@test "T006: no flags leaves description empty" {
	local number=""
	local description=""
	_parse_pr_edit_args number description

	[[ -z "$description" ]]
	[[ -z "$number" ]]
}

@test "T006: -d and --description=value both work in same invocation (last wins)" {
	local number=""
	local description=""
	_parse_pr_edit_args number description -d "first" --description="second"

	[[ "$description" == "second" ]]
}

@test "T006: description with special characters is preserved" {
	local number=""
	local description=""
	local expected='fix: handle $HOME and '"'"'quotes'"'"' & <html>'
	_parse_pr_edit_args number description -d "$expected"

	[[ "$description" == "$expected" ]]
}

# ---------------------------------------------------------------------------
# T007: Missing value errors
# ---------------------------------------------------------------------------

@test "T007: -d without value returns error" {
	local number=""
	local description=""
	run _parse_pr_edit_args number description -d

	[[ "$status" -eq 1 ]]
}

@test "T007: --description without value returns error" {
	local number=""
	local description=""
	run _parse_pr_edit_args number description --description

	[[ "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# Unknown flags before -- produce an error
# ---------------------------------------------------------------------------

@test "unknown flag before -- returns error with hint" {
	local number=""
	local description=""
	run _parse_pr_edit_args number description --add-label bug

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"use -- to pass flags to gh pr edit"* ]]
}
