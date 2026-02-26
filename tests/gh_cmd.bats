#!/usr/bin/env bats

# Unit tests for _split_on_separator in gh_cmd.sh
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_cmd.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _gh_ai_source_dir="$REPO_ROOT"

	# shellcheck disable=SC2155
	eval "$(
		export _gh_ai_source_dir="$REPO_ROOT"
		# shellcheck source=../scripts/gh_cmd.sh
		source "$REPO_ROOT/scripts/gh_cmd.sh"
		declare -f _split_on_separator
	)"
}

# ---------------------------------------------------------------------------
# Basic splitting
# ---------------------------------------------------------------------------

@test "no separator puts all args in before, after is empty" {
	local before=()
	local after=()
	_split_on_separator before after -d "desc" --flag

	[[ ${#before[@]} -eq 3 ]]
	[[ "${before[0]}" == "-d" ]]
	[[ "${before[1]}" == "desc" ]]
	[[ "${before[2]}" == "--flag" ]]
	[[ ${#after[@]} -eq 0 ]]
}

@test "clean split on --" {
	local before=()
	local after=()
	_split_on_separator before after -d "desc" -- --signoff --no-verify

	[[ ${#before[@]} -eq 2 ]]
	[[ "${before[0]}" == "-d" ]]
	[[ "${before[1]}" == "desc" ]]
	[[ ${#after[@]} -eq 2 ]]
	[[ "${after[0]}" == "--signoff" ]]
	[[ "${after[1]}" == "--no-verify" ]]
}

@test "empty before separator" {
	local before=()
	local after=()
	_split_on_separator before after -- --signoff

	[[ ${#before[@]} -eq 0 ]]
	[[ ${#after[@]} -eq 1 ]]
	[[ "${after[0]}" == "--signoff" ]]
}

@test "empty after separator" {
	local before=()
	local after=()
	_split_on_separator before after -d "desc" --

	[[ ${#before[@]} -eq 2 ]]
	[[ ${#after[@]} -eq 0 ]]
}

@test "no arguments produces two empty arrays" {
	local before=()
	local after=()
	_split_on_separator before after

	[[ ${#before[@]} -eq 0 ]]
	[[ ${#after[@]} -eq 0 ]]
}

@test "second -- in tail is preserved as passthrough arg" {
	local before=()
	local after=()
	_split_on_separator before after -d "desc" -- --signoff -- --extra

	[[ ${#before[@]} -eq 2 ]]
	[[ ${#after[@]} -eq 3 ]]
	[[ "${after[0]}" == "--signoff" ]]
	[[ "${after[1]}" == "--" ]]
	[[ "${after[2]}" == "--extra" ]]
}

@test "special characters are preserved" {
	local before=()
	local after=()
	_split_on_separator before after -d 'fix: handle $HOME & "quotes"' -- --message='hello world'

	[[ "${before[1]}" == 'fix: handle $HOME & "quotes"' ]]
	[[ "${after[0]}" == "--message=hello world" ]]
}

@test "only -- separator produces two empty arrays" {
	local before=()
	local after=()
	_split_on_separator before after --

	[[ ${#before[@]} -eq 0 ]]
	[[ ${#after[@]} -eq 0 ]]
}
