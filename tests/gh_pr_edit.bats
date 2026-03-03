#!/usr/bin/env bats

# Unit tests for gh ai pr edit arg parsing
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_pr_edit.bats

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
		# shellcheck source=../scripts/gh_pr.sh
		source "$REPO_ROOT/scripts/gh_pr.sh"
		declare -f _detect_pr_number _parse_pr_args _parse_pr_edit_args _show_pr_edit_help _gh_pr_edit _split_on_separator
	)"
}

@test "_parse_pr_edit_args: sets description from -d flag" {
	local number=""
	local description=""
	_parse_pr_edit_args number description -d "add testing section"

	[[ "$description" == "add testing section" ]]
}

@test "_parse_pr_edit_args: sets description from --description flag" {
	local number=""
	local description=""
	_parse_pr_edit_args number description --description "fix summary"

	[[ "$description" == "fix summary" ]]
}

@test "_parse_pr_edit_args: sets description from --description=value" {
	local number=""
	local description=""
	_parse_pr_edit_args number description --description="improve wording"

	[[ "$description" == "improve wording" ]]
}

@test "_parse_pr_edit_args: captures PR number from first positional arg" {
	local number=""
	local description=""
	_parse_pr_edit_args number description 42 -d "fix summary"

	[[ "$number" == "42" ]]
	[[ "$description" == "fix summary" ]]
}

@test "_parse_pr_edit_args: strips leading # from PR number" {
	local number=""
	local description=""
	_parse_pr_edit_args number description "#42" -d "fix summary"

	[[ "$number" == "42" ]]
}

@test "_parse_pr_edit_args: captures PR number without other flags" {
	local number=""
	local description=""
	_parse_pr_edit_args number description 42

	[[ "$number" == "42" ]]
}

@test "_parse_pr_edit_args: defaults number and description to empty" {
	local number=""
	local description=""
	_parse_pr_edit_args number description

	[[ -z "$description" ]]
	[[ -z "$number" ]]
}

@test "_parse_pr_edit_args: last value wins when -d and --description both given" {
	local number=""
	local description=""
	_parse_pr_edit_args number description -d "first" --description="second"

	[[ "$description" == "second" ]]
}

@test "_parse_pr_edit_args: preserves special characters in description" {
	local number=""
	local description=""
	local expected='fix: handle $HOME and '"'"'quotes'"'"' & <html>'
	_parse_pr_edit_args number description -d "$expected"

	[[ "$description" == "$expected" ]]
}

@test "_parse_pr_edit_args: returns error when -d has no value" {
	local number=""
	local description=""
	run _parse_pr_edit_args number description -d

	[[ "$status" -eq 1 ]]
}

@test "_parse_pr_edit_args: returns error when --description has no value" {
	local number=""
	local description=""
	run _parse_pr_edit_args number description --description

	[[ "$status" -eq 1 ]]
}

@test "_parse_pr_edit_args: returns error with hint for unknown flags" {
	local number=""
	local description=""
	run _parse_pr_edit_args number description --add-label bug

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"use -- to pass flags to gh pr edit"* ]]
}
