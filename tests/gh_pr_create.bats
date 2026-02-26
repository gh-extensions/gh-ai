#!/usr/bin/env bats

# Unit tests for gh ai pr create arg parsing
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_pr_create.bats

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
		declare -f _parse_pr_create_args _show_pr_create_help _gh_pr_create _split_on_separator
	)"
}

# ---------------------------------------------------------------------------
# T001: -d/--description captured
# ---------------------------------------------------------------------------

@test "T001: -d flag captures description" {
	local base=""
	local description=""
	_parse_pr_create_args base description -d "focus on security"

	[[ "$description" == "focus on security" ]]
}

@test "T001: --description flag captures description" {
	local base=""
	local description=""
	_parse_pr_create_args base description --description "improve readability"

	[[ "$description" == "improve readability" ]]
}

@test "T001: --description=value form captures description" {
	local base=""
	local description=""
	_parse_pr_create_args base description --description="use imperative mood"

	[[ "$description" == "use imperative mood" ]]
}

# ---------------------------------------------------------------------------
# T002: --base/-B captured
# ---------------------------------------------------------------------------

@test "T002: --base captures branch" {
	local base=""
	local description=""
	_parse_pr_create_args base description --base develop

	[[ "$base" == "develop" ]]
}

@test "T002: -B captures branch" {
	local base=""
	local description=""
	_parse_pr_create_args base description -B main

	[[ "$base" == "main" ]]
}

@test "T002: --base=value captures branch" {
	local base=""
	local description=""
	_parse_pr_create_args base description --base=develop

	[[ "$base" == "develop" ]]
}

# ---------------------------------------------------------------------------
# T006: Edge cases
# ---------------------------------------------------------------------------

@test "T006: no flags leaves description and base empty" {
	local base=""
	local description=""
	_parse_pr_create_args base description

	[[ -z "$description" ]]
	[[ -z "$base" ]]
}

@test "T006: -d and --description=value both work in same invocation (last wins)" {
	local base=""
	local description=""
	_parse_pr_create_args base description -d "first" --description="second"

	[[ "$description" == "second" ]]
}

@test "T006: description with special characters is preserved" {
	local base=""
	local description=""
	local expected='fix: handle $HOME and '"'"'quotes'"'"' & <html>'
	_parse_pr_create_args base description -d "$expected"

	[[ "$description" == "$expected" ]]
}

# ---------------------------------------------------------------------------
# T007: Missing value errors
# ---------------------------------------------------------------------------

@test "T007: -d without value returns error" {
	local base=""
	local description=""
	run _parse_pr_create_args base description -d

	[[ "$status" -eq 1 ]]
}

@test "T007: --description without value returns error" {
	local base=""
	local description=""
	run _parse_pr_create_args base description --description

	[[ "$status" -eq 1 ]]
}

@test "T007: --base without value returns error" {
	local base=""
	local description=""
	run _parse_pr_create_args base description --base

	[[ "$status" -eq 1 ]]
}

@test "T007: -B without value returns error" {
	local base=""
	local description=""
	run _parse_pr_create_args base description -B

	[[ "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# Unknown flags before -- produce an error
# ---------------------------------------------------------------------------

@test "unknown flag before -- returns error with hint" {
	local base=""
	local description=""
	run _parse_pr_create_args base description --draft

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"use -- to pass flags to gh pr create"* ]]
}
