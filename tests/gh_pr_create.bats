#!/usr/bin/env bats

# Unit tests for gh ai pr create arg parsing
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_pr_create.bats

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
		declare -f _parse_pr_create_args _show_pr_create_help _gh_pr_create _split_on_separator
	)"
}

@test "_parse_pr_create_args: sets description from -d flag" {
	local base=""
	local description=""
	_parse_pr_create_args base description -d "focus on security"

	[[ "$description" == "focus on security" ]]
}

@test "_parse_pr_create_args: sets description from --description flag" {
	local base=""
	local description=""
	_parse_pr_create_args base description --description "improve readability"

	[[ "$description" == "improve readability" ]]
}

@test "_parse_pr_create_args: sets description from --description=value" {
	local base=""
	local description=""
	_parse_pr_create_args base description --description="use imperative mood"

	[[ "$description" == "use imperative mood" ]]
}

@test "_parse_pr_create_args: sets base from --base flag" {
	local base=""
	local description=""
	_parse_pr_create_args base description --base develop

	[[ "$base" == "develop" ]]
}

@test "_parse_pr_create_args: sets base from -B flag" {
	local base=""
	local description=""
	_parse_pr_create_args base description -B main

	[[ "$base" == "main" ]]
}

@test "_parse_pr_create_args: sets base from --base=value" {
	local base=""
	local description=""
	_parse_pr_create_args base description --base=develop

	[[ "$base" == "develop" ]]
}

@test "_parse_pr_create_args: defaults description and base to empty" {
	local base=""
	local description=""
	_parse_pr_create_args base description

	[[ -z "$description" ]]
	[[ -z "$base" ]]
}

@test "_parse_pr_create_args: last value wins when -d and --description both given" {
	local base=""
	local description=""
	_parse_pr_create_args base description -d "first" --description="second"

	[[ "$description" == "second" ]]
}

@test "_parse_pr_create_args: preserves special characters in description" {
	local base=""
	local description=""
	local expected='fix: handle $HOME and '"'"'quotes'"'"' & <html>'
	_parse_pr_create_args base description -d "$expected"

	[[ "$description" == "$expected" ]]
}

@test "_parse_pr_create_args: returns error when -d has no value" {
	local base=""
	local description=""
	run _parse_pr_create_args base description -d

	[[ "$status" -eq 1 ]]
}

@test "_parse_pr_create_args: returns error when --description has no value" {
	local base=""
	local description=""
	run _parse_pr_create_args base description --description

	[[ "$status" -eq 1 ]]
}

@test "_parse_pr_create_args: returns error when --base has no value" {
	local base=""
	local description=""
	run _parse_pr_create_args base description --base

	[[ "$status" -eq 1 ]]
}

@test "_parse_pr_create_args: returns error when -B has no value" {
	local base=""
	local description=""
	run _parse_pr_create_args base description -B

	[[ "$status" -eq 1 ]]
}

@test "_parse_pr_create_args: returns error with hint for unknown flags" {
	local base=""
	local description=""
	run _parse_pr_create_args base description --draft

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"use -- to pass flags to gh pr create"* ]]
}
