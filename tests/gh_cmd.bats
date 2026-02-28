#!/usr/bin/env bats

# Unit tests for _split_on_separator in gh_cmd.sh
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_cmd.bats

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
		declare -f _split_on_separator _cmd_render _get_title _get_body \
			_get_repo_name _get_git_repo_path
	)"
}

@test "_split_on_separator: places all args in before when no -- present" {
	local before=()
	local after=()
	_split_on_separator before after -d "desc" --flag

	[[ ${#before[@]} -eq 3 ]]
	[[ "${before[0]}" == "-d" ]]
	[[ "${before[1]}" == "desc" ]]
	[[ "${before[2]}" == "--flag" ]]
	[[ ${#after[@]} -eq 0 ]]
}

@test "_split_on_separator: splits args into before and after on --" {
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

@test "_split_on_separator: handles empty before when -- is first arg" {
	local before=()
	local after=()
	_split_on_separator before after -- --signoff

	[[ ${#before[@]} -eq 0 ]]
	[[ ${#after[@]} -eq 1 ]]
	[[ "${after[0]}" == "--signoff" ]]
}

@test "_split_on_separator: handles empty after when -- is last arg" {
	local before=()
	local after=()
	_split_on_separator before after -d "desc" --

	[[ ${#before[@]} -eq 2 ]]
	[[ ${#after[@]} -eq 0 ]]
}

@test "_split_on_separator: returns two empty arrays for no arguments" {
	local before=()
	local after=()
	_split_on_separator before after

	[[ ${#before[@]} -eq 0 ]]
	[[ ${#after[@]} -eq 0 ]]
}

@test "_split_on_separator: passes second -- through as passthrough arg" {
	local before=()
	local after=()
	_split_on_separator before after -d "desc" -- --signoff -- --extra

	[[ ${#before[@]} -eq 2 ]]
	[[ ${#after[@]} -eq 3 ]]
	[[ "${after[0]}" == "--signoff" ]]
	[[ "${after[1]}" == "--" ]]
	[[ "${after[2]}" == "--extra" ]]
}

@test "_split_on_separator: preserves special characters across the split" {
	local before=()
	local after=()
	_split_on_separator before after -d 'fix: handle $HOME & "quotes"' -- --message='hello world'

	[[ "${before[1]}" == 'fix: handle $HOME & "quotes"' ]]
	[[ "${after[0]}" == "--message=hello world" ]]
}

@test "_split_on_separator: returns two empty arrays when only -- given" {
	local before=()
	local after=()
	_split_on_separator before after --

	[[ ${#before[@]} -eq 0 ]]
	[[ ${#after[@]} -eq 0 ]]
}

# ---------------------------------------------------------------------------
# _get_repo_name
# ---------------------------------------------------------------------------

@test "_get_repo_name: sets nameref when gh repo view succeeds" {
	gh() { echo "owner/repo"; }
	export -f gh

	local repo=""
	_get_repo_name repo

	[[ "$repo" == "owner/repo" ]]
}

@test "_get_repo_name: returns error when gh repo view returns empty" {
	gh() { :; }
	export -f gh

	local repo=""
	run _get_repo_name repo

	[[ "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# _get_git_repo_path
# ---------------------------------------------------------------------------

@test "_get_git_repo_path: sets nameref when git rev-parse succeeds" {
	git() { echo "/home/user/myrepo"; }
	export -f git

	local dir=""
	_get_git_repo_path dir

	[[ "$dir" == "/home/user/myrepo" ]]
}

@test "_get_git_repo_path: returns error when git rev-parse returns empty" {
	git() { :; }
	export -f git

	local dir=""
	run _get_git_repo_path dir

	[[ "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# _cmd_render
# ---------------------------------------------------------------------------

@test "_cmd_render: substitutes env vars in template" {
	local tmpdir="$BATS_TMPDIR/render-test-$$"
	mkdir -p "$tmpdir"
	printf 'Hello ${MY_NAME}, welcome to ${MY_PLACE}.\n' >"$tmpdir/test.tmpl"

	local output
	output=$(MY_NAME="Alice" MY_PLACE="Wonderland" _cmd_render "$tmpdir/test.tmpl")

	[[ "$output" == *"Hello Alice, welcome to Wonderland."* ]]
}

@test "_cmd_render: leaves unset vars as empty strings" {
	local tmpdir="$BATS_TMPDIR/render-unset-test-$$"
	mkdir -p "$tmpdir"
	printf 'Value: [${UNSET_VAR}]\n' >"$tmpdir/test.tmpl"

	local output
	output=$(_cmd_render "$tmpdir/test.tmpl")

	[[ "$output" == *"Value: []"* ]]
}

@test "_cmd_render: does not re-expand vars inside substituted values" {
	local tmpdir="$BATS_TMPDIR/render-safe-test-$$"
	mkdir -p "$tmpdir"
	printf 'Diff: ${GIT_DIFF}\n' >"$tmpdir/test.tmpl"

	local output
	output=$(GIT_DIFF='contains ${SECRET} token' _cmd_render "$tmpdir/test.tmpl")

	[[ "$output" == *'contains ${SECRET} token'* ]]
}

@test "_cmd_render: returns error for missing template file" {
	run _cmd_render "/nonexistent/template.tmpl"

	[[ "$status" -eq 1 ]]
}

@test "_cmd_render: preserves multiline content in substituted values" {
	local tmpdir="$BATS_TMPDIR/render-multiline-test-$$"
	mkdir -p "$tmpdir"
	printf 'Log:\n${MY_LOG}\nEnd.\n' >"$tmpdir/test.tmpl"

	local output
	output=$(MY_LOG=$'line one\nline two\nline three' _cmd_render "$tmpdir/test.tmpl")

	[[ "$output" == *"line one"* ]]
	[[ "$output" == *"line two"* ]]
	[[ "$output" == *"line three"* ]]
}

# ---------------------------------------------------------------------------
# _get_title
# ---------------------------------------------------------------------------

@test "_get_title: extracts title from markdown heading" {
	local output
	output=$(_get_title "# Fix bug in parser

Description of the fix.")

	[[ "$output" == "Fix bug in parser" ]]
}

@test "_get_title: extracts title without heading prefix" {
	local output
	output=$(_get_title "Add new feature

Body text here.")

	[[ "$output" == "Add new feature" ]]
}

@test "_get_title: returns error for empty content" {
	run _get_title ""

	[[ "$status" -eq 1 ]]
}

@test "_get_title: strips only the first heading hash" {
	local output
	output=$(_get_title "## Sub heading title")

	[[ "$output" == "# Sub heading title" ]]
}

# ---------------------------------------------------------------------------
# _get_body
# ---------------------------------------------------------------------------

@test "_get_body: extracts body after title line with footer" {
	local output
	output=$(_get_body "# Title

Body paragraph one.

Body paragraph two.")

	[[ "$output" == *"Body paragraph one."* ]]
	[[ "$output" == *"Body paragraph two."* ]]
	[[ "$output" == *"markdownlint-disable-file"* ]]
}

@test "_get_body: strips leading blank lines" {
	local output
	output=$(_get_body "# Title


Actual body.")

	# First char of output should not be a newline
	[[ "${output:0:1}" != $'\n' ]]
	[[ "$output" == *"Actual body."* ]]
}

@test "_get_body: returns only footer for title-only content" {
	local output
	output=$(_get_body "# Title only")

	[[ "$output" == *"markdownlint-disable-file"* ]]
}
