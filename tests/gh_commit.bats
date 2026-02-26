#!/usr/bin/env bats

# Unit and integration tests for gh ai commit -d/--description flag
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

	# Source the commit script to expose its functions
	# shellcheck source=../scripts/gh_commit.sh
	source "$REPO_ROOT/scripts/gh_commit.sh"
}

# ---------------------------------------------------------------------------
# T001 / T005: Integration — flag is recognised and captured
# ---------------------------------------------------------------------------

@test "T001: -d flag captures description and excludes it from git args" {
	local description=""
	local args=()
	_parse_commit_args description args -d "focus on security"

	[[ "$description" == "focus on security" ]]
	[[ ${#args[@]} -eq 0 ]]
}

@test "T001: --description flag captures description and excludes it from git args" {
	local description=""
	local args=()
	_parse_commit_args description args --description "improve readability"

	[[ "$description" == "improve readability" ]]
	[[ ${#args[@]} -eq 0 ]]
}

@test "T001: --description=value form captures description" {
	local description=""
	local args=()
	_parse_commit_args description args --description="use imperative mood"

	[[ "$description" == "use imperative mood" ]]
	[[ ${#args[@]} -eq 0 ]]
}

@test "T001: -d flag does not bleed into git passthrough args" {
	local description=""
	local args=()
	_parse_commit_args description args --signoff -d "context" --no-verify

	[[ "$description" == "context" ]]
	[[ ${#args[@]} -eq 2 ]]
	[[ "${args[0]}" == "--signoff" ]]
	[[ "${args[1]}" == "--no-verify" ]]
}

@test "T005: existing AI-managed flags (-m) are still stripped" {
	local description=""
	local args=()
	_parse_commit_args description args -m "ignored message" --signoff

	[[ -z "$description" ]]
	[[ ${#args[@]} -eq 1 ]]
	[[ "${args[0]}" == "--signoff" ]]
}

@test "T005: existing AI-managed flag (-F) is still stripped" {
	local description=""
	local args=()
	_parse_commit_args description args -F file.txt --no-verify

	[[ -z "$description" ]]
	[[ ${#args[@]} -eq 1 ]]
	[[ "${args[0]}" == "--no-verify" ]]
}

@test "T005: --message=value form is still stripped" {
	local description=""
	local args=()
	_parse_commit_args description args --message="ignored" --signoff

	[[ -z "$description" ]]
	[[ ${#args[@]} -eq 1 ]]
	[[ "${args[0]}" == "--signoff" ]]
}

# ---------------------------------------------------------------------------
# T006: Edge cases
# ---------------------------------------------------------------------------

@test "T006: empty description leaves variable empty" {
	local description=""
	local args=()
	_parse_commit_args description args -d ""

	[[ -z "$description" ]]
	[[ ${#args[@]} -eq 0 ]]
}

@test "T006: description with special characters is preserved" {
	local description=""
	local args=()
	_parse_commit_args description args -d "fix: handle \$HOME and 'quotes' & <html>"

	[[ "$description" == 'fix: handle $HOME and '"'"'quotes'"'"' & <html>' ]]
}

@test "T006: long description is preserved verbatim" {
	local long_desc
	long_desc="$(printf 'word%.0s ' {1..100})"
	local description=""
	local args=()
	_parse_commit_args description args -d "$long_desc"

	[[ "$description" == "$long_desc" ]]
}

@test "T006: no description flag leaves variable empty and passes all args" {
	local description=""
	local args=()
	_parse_commit_args description args --signoff --no-verify

	[[ -z "$description" ]]
	[[ ${#args[@]} -eq 2 ]]
}

@test "T006: -d and --description=value both work in same invocation (last wins)" {
	local description=""
	local args=()
	_parse_commit_args description args -d "first" --description="second"

	[[ "$description" == "second" ]]
}
