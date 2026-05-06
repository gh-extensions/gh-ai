#!/usr/bin/env bats

# Unit tests for gh ai issue create arg parsing
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_issue_create.bats

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
		# shellcheck source=../scripts/gh_issue.sh
		source "$REPO_ROOT/scripts/gh_issue.sh"
		declare -f _parse_issue_create_args _show_issue_create_help _gh_issue_create
	)"
}

@test "_parse_issue_create_args: sets description from -d flag" {
	local description=""
	local passthrough=()
	_parse_issue_create_args description passthrough -d "Login page crashes"

	[[ "$description" == "Login page crashes" ]]
}

@test "_parse_issue_create_args: sets description from --description flag" {
	local description=""
	local passthrough=()
	_parse_issue_create_args description passthrough --description "Login page crashes"

	[[ "$description" == "Login page crashes" ]]
}

@test "_parse_issue_create_args: sets description from --description=value" {
	local description=""
	local passthrough=()
	_parse_issue_create_args description passthrough --description="Login page crashes"

	[[ "$description" == "Login page crashes" ]]
}

@test "_parse_issue_create_args: defaults description to empty when no flags given" {
	local description=""
	local passthrough=()
	_parse_issue_create_args description passthrough

	[[ -z "$description" ]]
}

@test "_parse_issue_create_args: preserves special characters in description" {
	local description=""
	local passthrough=()
	local expected='fix: handle $HOME and '"'"'quotes'"'"' & <html>'
	_parse_issue_create_args description passthrough -d "$expected"

	[[ "$description" == "$expected" ]]
}

@test "_parse_issue_create_args: last value wins when -d and --description both given" {
	local description=""
	local passthrough=()
	_parse_issue_create_args description passthrough -d "first" --description="second"

	[[ "$description" == "second" ]]
}

@test "_parse_issue_create_args: returns error when -d has no value" {
	local description=""
	local passthrough=()
	run _parse_issue_create_args description passthrough -d

	[[ "$status" -eq 1 ]]
}

@test "_parse_issue_create_args: error message includes flag name when --description has no value" {
	local description=""
	local passthrough=()
	run _parse_issue_create_args description passthrough --description

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"--description requires a value"* ]]
}

@test "_parse_issue_create_args: collects unknown flags as passthrough" {
	local description=""
	local passthrough=()
	_parse_issue_create_args description passthrough --label bug

	[[ "${passthrough[0]}" == "--label" ]]
	[[ "${passthrough[1]}" == "bug" ]]
}

@test "_parse_issue_create_args: known flag before unknown flag works correctly" {
	local description=""
	local passthrough=()
	_parse_issue_create_args description passthrough -d "crash report" --label bug --assignee @me

	[[ "$description" == "crash report" ]]
	[[ "${passthrough[0]}" == "--label" ]]
	[[ "${passthrough[1]}" == "bug" ]]
	[[ "${passthrough[2]}" == "--assignee" ]]
	[[ "${passthrough[3]}" == "@me" ]]
}
