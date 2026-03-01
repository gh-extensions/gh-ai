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
		declare -f _split_on_separator _cmd_render _parse_title _parse_body \
			_gh_repo_name _git_repo_path _git_branch_diff _uuidv5
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
# _gh_repo_name
# ---------------------------------------------------------------------------

@test "_gh_repo_name: sets nameref when gh repo view succeeds" {
	gh() { echo "owner/repo"; }
	export -f gh

	local repo=""
	_gh_repo_name repo

	[[ "$repo" == "owner/repo" ]]
}

@test "_gh_repo_name: returns error when gh repo view returns empty" {
	gh() { :; }
	export -f gh

	local repo=""
	run _gh_repo_name repo

	[[ "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# _git_repo_path
# ---------------------------------------------------------------------------

@test "_git_repo_path: sets nameref when git rev-parse succeeds" {
	git() { echo "/home/user/myrepo"; }
	export -f git

	local dir=""
	_git_repo_path dir

	[[ "$dir" == "/home/user/myrepo" ]]
}

@test "_git_repo_path: returns error when git rev-parse returns empty" {
	git() { :; }
	export -f git

	local dir=""
	run _git_repo_path dir

	[[ "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# _git_branch_diff
# ---------------------------------------------------------------------------

@test "_git_branch_diff: populates all four namerefs" {
	git() {
		case "$1 $2" in
		"diff origin/main...feature")
			if [[ "${*}" == *"--stat"* ]]; then
				echo " file.sh | 2 +-"
			else
				echo "diff --git a/file.sh b/file.sh"
			fi
			;;
		"log --oneline") echo "abc1234 first commit" ;;
		esac
	}
	export -f git

	local diff="" stat="" log="" commits=""
	_git_branch_diff main feature diff stat log commits

	[[ "$diff" == "diff --git a/file.sh b/file.sh" ]]
	[[ "$stat" == " file.sh | 2 +-" ]]
	[[ "$log" == "abc1234 first commit" ]]
	[[ "$commits" == "- first commit" ]]
}

@test "_git_branch_diff: falls back to bare branch when origin fails" {
	git() {
		case "$*" in
		*origin/main*)
			return 1
			;;
		"diff main...feature")
			echo "diff --git a/file.sh b/file.sh"
			;;
		"diff main...feature --stat")
			echo " file.sh | 2 +-"
			;;
		"log --oneline main..feature")
			echo "abc1234 first commit"
			;;
		esac
	}
	export -f git

	local diff="" stat="" log="" commits=""
	_git_branch_diff main feature diff stat log commits

	[[ "$diff" == "diff --git a/file.sh b/file.sh" ]]
}

@test "_git_branch_diff: returns error when diff is empty" {
	git() { return 1; }
	export -f git

	local diff="" stat="" log="" commits=""
	run _git_branch_diff main feature diff stat log commits

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
	printf 'Diff: ${GH_PR_DIFF}\n' >"$tmpdir/test.tmpl"

	local output
	output=$(GH_PR_DIFF='contains ${SECRET} token' _cmd_render "$tmpdir/test.tmpl")

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

# File-backed _cmd_render tests
# These test the *_FILE env var support for bypassing ARG_MAX

@test "_cmd_render: reads file content from VAR_FILE env var" {
	local tmpdir="$BATS_TMPDIR/render-file-test-$$"
	mkdir -p "$tmpdir"
	printf 'Diff:\n${GH_PR_DIFF}\nEnd.\n' >"$tmpdir/test.tmpl"
	printf 'line one\nline two\nline three' >"$tmpdir/diff.patch"

	local output
	output=$(GH_PR_DIFF_FILE="$tmpdir/diff.patch" _cmd_render "$tmpdir/test.tmpl")

	[[ "$output" == *"line one"* ]]
	[[ "$output" == *"line two"* ]]
	[[ "$output" == *"line three"* ]]
}

@test "_cmd_render: direct env var takes priority over _FILE" {
	local tmpdir="$BATS_TMPDIR/render-priority-test-$$"
	mkdir -p "$tmpdir"
	printf 'Value: ${MY_VAR}\n' >"$tmpdir/test.tmpl"
	printf 'from file' >"$tmpdir/value.txt"

	local output
	output=$(MY_VAR="from env" MY_VAR_FILE="$tmpdir/value.txt" _cmd_render "$tmpdir/test.tmpl")

	[[ "$output" == *"Value: from env"* ]]
	[[ "$output" != *"from file"* ]]
}

@test "_cmd_render: nonexistent _FILE path produces empty string" {
	local tmpdir="$BATS_TMPDIR/render-missing-test-$$"
	mkdir -p "$tmpdir"
	printf 'Value: [${MY_VAR}]\n' >"$tmpdir/test.tmpl"

	local output
	output=$(MY_VAR_FILE="/nonexistent/file.txt" _cmd_render "$tmpdir/test.tmpl")

	[[ "$output" == *"Value: []"* ]]
}

@test "_cmd_render: multiline file content preserved in _FILE" {
	local tmpdir="$BATS_TMPDIR/render-multiline-file-test-$$"
	mkdir -p "$tmpdir"
	printf 'Content:\n${MY_CONTENT}\nEnd.\n' >"$tmpdir/test.tmpl"
	printf 'line one\nline two\nline three' >"$tmpdir/content.txt"

	local output
	output=$(MY_CONTENT_FILE="$tmpdir/content.txt" _cmd_render "$tmpdir/test.tmpl")

	[[ "$output" == *"line one"* ]]
	[[ "$output" == *"line two"* ]]
	[[ "$output" == *"line three"* ]]
}

@test "_cmd_render: patterns in file content not re-expanded" {
	local tmpdir="$BATS_TMPDIR/render-safety-file-test-$$"
	mkdir -p "$tmpdir"
	printf 'Diff:\n${GH_DIFF}\nEnd.\n' >"$tmpdir/test.tmpl"
	printf 'contains ${SECRET_TOKEN} and ${OTHER} patterns' >"$tmpdir/diff.patch"

	local output
	output=$(GH_DIFF_FILE="$tmpdir/diff.patch" _cmd_render "$tmpdir/test.tmpl")

	# Patterns from file should be preserved as-is, not re-expanded
	[[ "$output" == *'contains ${SECRET_TOKEN} and ${OTHER} patterns'* ]]
}

# ---------------------------------------------------------------------------
# _parse_title
# ---------------------------------------------------------------------------

@test "_parse_title: extracts title from markdown heading" {
	local output
	output=$(_parse_title "# Fix bug in parser

Description of the fix.")

	[[ "$output" == "Fix bug in parser" ]]
}

@test "_parse_title: extracts title without heading prefix" {
	local output
	output=$(_parse_title "Add new feature

Body text here.")

	[[ "$output" == "Add new feature" ]]
}

@test "_parse_title: returns error for empty content" {
	run _parse_title ""

	[[ "$status" -eq 1 ]]
}

@test "_parse_title: strips only the first heading hash" {
	local output
	output=$(_parse_title "## Sub heading title")

	[[ "$output" == "# Sub heading title" ]]
}

# ---------------------------------------------------------------------------
# _parse_body
# ---------------------------------------------------------------------------

@test "_parse_body: extracts body after title line with footer" {
	local output
	output=$(_parse_body "# Title

Body paragraph one.

Body paragraph two.")

	[[ "$output" == *"Body paragraph one."* ]]
	[[ "$output" == *"Body paragraph two."* ]]
	[[ "$output" == *"markdownlint-disable-file"* ]]
}

@test "_parse_body: strips leading blank lines" {
	local output
	output=$(_parse_body "# Title


Actual body.")

	# First char of output should not be a newline
	[[ "${output:0:1}" != $'\n' ]]
	[[ "$output" == *"Actual body."* ]]
}

@test "_parse_body: returns only footer for title-only content" {
	local output
	output=$(_parse_body "# Title only")

	[[ "$output" == *"markdownlint-disable-file"* ]]
}

# ---------------------------------------------------------------------------
# _uuidv5
# ---------------------------------------------------------------------------

@test "_uuidv5: correct UUID for known issue URL" {
	local output
	output=$(_uuidv5 "https://github.com/owner/repo/issues/42")

	[[ "$output" == "3c177fbc-2912-59eb-b754-8ff8b6e3021b" ]]
}

@test "_uuidv5: correct UUID for known PR URL" {
	local output
	output=$(_uuidv5 "https://github.com/gh-extensions/gh-ai/pull/7")

	[[ "$output" == "06aecb08-6f37-5c60-807f-2d88b3f2cd2c" ]]
}

@test "_uuidv5: correct UUID for known run URL" {
	local output
	output=$(_uuidv5 "https://github.com/gh-extensions/gh-ai/actions/runs/123456")

	[[ "$output" == "728ca934-ac63-5822-9504-56becd76d3e0" ]]
}

@test "_uuidv5: different inputs produce different UUIDs" {
	local uuid1 uuid2
	uuid1=$(_uuidv5 "https://github.com/owner/repo/issues/1")
	uuid2=$(_uuidv5 "https://github.com/owner/repo/issues/2")

	[[ "$uuid1" != "$uuid2" ]]
}

@test "_uuidv5: same input always produces same UUID" {
	local uuid1 uuid2
	uuid1=$(_uuidv5 "https://github.com/owner/repo/issues/42")
	uuid2=$(_uuidv5 "https://github.com/owner/repo/issues/42")

	[[ "$uuid1" == "$uuid2" ]]
}
