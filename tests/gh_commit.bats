#!/usr/bin/env bats

# Unit and integration tests for gh ai commit
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_commit.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _gh_ai_source_dir="$REPO_ROOT"

	# Mock external commands not under test
	gum() { :; }
	gh() { echo ""; }
	git() { echo ""; }
	export -f gum gh git

	# Source gh_commit.sh inside a subshell and import only the function
	# definitions.  This prevents the `set -euo pipefail` at the top of
	# gh_commit.sh from leaking into the bats test runner, which would
	# cause pipefail-triggered deadlocks when a test assertion fails.
	# shellcheck disable=SC2155
	eval "$(
		export _gh_ai_source_dir="$REPO_ROOT"
		# shellcheck source=../scripts/gh_cmd.sh
		source "$REPO_ROOT/scripts/gh_cmd.sh"
		# shellcheck source=../scripts/gh_commit.sh
		source "$REPO_ROOT/scripts/gh_commit.sh"
		declare -f _parse_commit_args _show_commit_help _gh_commit _split_on_separator
	)"
}

# ---------------------------------------------------------------------------
# T001: -d/--description captured
# ---------------------------------------------------------------------------

@test "T001: -d flag captures description" {
	local description=""
	_parse_commit_args description -d "focus on security"

	[[ "$description" == "focus on security" ]]
}

@test "T001: --description flag captures description" {
	local description=""
	_parse_commit_args description --description "improve readability"

	[[ "$description" == "improve readability" ]]
}

@test "T001: --description=value form captures description" {
	local description=""
	_parse_commit_args description --description="use imperative mood"

	[[ "$description" == "use imperative mood" ]]
}

# ---------------------------------------------------------------------------
# T006: Edge cases
# ---------------------------------------------------------------------------

@test "T006: empty description leaves variable empty" {
	local description=""
	_parse_commit_args description -d ""

	[[ -z "$description" ]]
}

@test "T006: description with special characters is preserved" {
	local description=""
	_parse_commit_args description -d "fix: handle \$HOME and 'quotes' & <html>"

	[[ "$description" == 'fix: handle $HOME and '"'"'quotes'"'"' & <html>' ]]
}

@test "T006: long description is preserved verbatim" {
	local long_desc
	long_desc="$(printf 'word%.0s ' {1..100})"
	local description=""
	_parse_commit_args description -d "$long_desc"

	[[ "$description" == "$long_desc" ]]
}

@test "T006: no flags leaves description empty" {
	local description=""
	_parse_commit_args description

	[[ -z "$description" ]]
}

@test "T006: -d and --description=value both work in same invocation (last wins)" {
	local description=""
	_parse_commit_args description -d "first" --description="second"

	[[ "$description" == "second" ]]
}

@test "T007: -d without value returns error" {
	local description=""
	run _parse_commit_args description -d

	[[ "$status" -eq 1 ]]
}

@test "T007: --description without value returns error" {
	local description=""
	run _parse_commit_args description --description

	[[ "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# Unknown flags before -- produce an error
# ---------------------------------------------------------------------------

@test "unknown flag before -- returns error with hint" {
	local description=""
	run _parse_commit_args description --signoff

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"use -- to pass flags to git commit"* ]]
}
