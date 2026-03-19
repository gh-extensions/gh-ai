#!/usr/bin/env bats

# Unit tests for _split_on_separator in gh_cmd.sh
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_cmd.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _gh_claude_source_dir="$REPO_ROOT"

	# Initialize global claude args array (set per-test when needed)
	_GH_CLAUDE_ARGS=()

	gum() { if [[ "$1" == "log" ]]; then shift; shift; shift; echo "$@"; fi; }
	gh() { echo ""; }
	git() { echo ""; }
	export -f gum gh git

	# shellcheck disable=SC2155
	eval "$(
		export _gh_claude_source_dir="$REPO_ROOT"
		# shellcheck source=../scripts/gh_cmd.sh
		source "$REPO_ROOT/scripts/gh_cmd.sh"
		printf '_gh_cmd_dir=%q\n' "$_gh_cmd_dir"
		declare -f _split_on_separator _cmd_render _parse_title _parse_body \
			_gh_repo_name _git_repo_path _git_branch_diff _trust_workspace \
			_gh_config_claude_model _extract_claude_arg
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
# _trust_workspace
# ---------------------------------------------------------------------------

@test "_trust_workspace: creates ~/.claude.json when absent" {
	export HOME="$BATS_TEST_TMPDIR"
	rm -f "$HOME/.claude.json"

	_trust_workspace "/tmp/test-workspace"

	[[ -f "$HOME/.claude.json" ]]
	local accepted
	accepted=$(jq -r '.projects["/tmp/test-workspace"].hasTrustDialogAccepted' "$HOME/.claude.json")
	[[ "$accepted" == "true" ]]
}

@test "_trust_workspace: merges into existing ~/.claude.json" {
	export HOME="$BATS_TEST_TMPDIR"
	printf '%s\n' '{"existingKey": "existingValue"}' >"$HOME/.claude.json"

	_trust_workspace "/tmp/new-workspace"

	local existing
	existing=$(jq -r '.existingKey' "$HOME/.claude.json")
	[[ "$existing" == "existingValue" ]]

	local accepted
	accepted=$(jq -r '.projects["/tmp/new-workspace"].hasTrustDialogAccepted' "$HOME/.claude.json")
	[[ "$accepted" == "true" ]]
}

@test "_trust_workspace: preserves existing workspace entries" {
	export HOME="$BATS_TEST_TMPDIR"
	jq -n '{projects: {"/tmp/other": {hasTrustDialogAccepted: true, customSetting: "keep"}}}' >"$HOME/.claude.json"

	_trust_workspace "/tmp/new-workspace"

	local other_accepted
	other_accepted=$(jq -r '.projects["/tmp/other"].hasTrustDialogAccepted' "$HOME/.claude.json")
	[[ "$other_accepted" == "true" ]]

	local custom
	custom=$(jq -r '.projects["/tmp/other"].customSetting' "$HOME/.claude.json")
	[[ "$custom" == "keep" ]]

	local new_accepted
	new_accepted=$(jq -r '.projects["/tmp/new-workspace"].hasTrustDialogAccepted' "$HOME/.claude.json")
	[[ "$new_accepted" == "true" ]]
}

# ---------------------------------------------------------------------------
# _gh_config_claude_model
# ---------------------------------------------------------------------------

@test "_gh_config_claude_model: returns haiku by default with no scope" {
	gh() { :; }
	export -f gh

	local output
	output=$(_gh_config_claude_model)

	[[ "$output" == "haiku" ]]
}

@test "_gh_config_claude_model: returns claude.model when set, no scope" {
	gh() { echo "sonnet"; }
	export -f gh

	local output
	output=$(_gh_config_claude_model)

	[[ "$output" == "sonnet" ]]
}

@test "_gh_config_claude_model: returns claude.pr.model when set with pr scope" {
	gh() {
		case "$*" in
		*"claude.pr.model"*) echo "opus" ;;
		*) :; ;;
		esac
	}
	export -f gh

	local output
	output=$(_gh_config_claude_model "pr")

	[[ "$output" == "opus" ]]
}

@test "_gh_config_claude_model: falls back to claude.model when claude.pr.model unset" {
	gh() {
		case "$*" in
		*"claude.pr.model"*) :; ;;
		*"claude.model"*) echo "sonnet" ;;
		*) :; ;;
		esac
	}
	export -f gh

	local output
	output=$(_gh_config_claude_model "pr")

	[[ "$output" == "sonnet" ]]
}

@test "_gh_config_claude_model: falls back to haiku when neither claude.pr.model nor claude.model set" {
	gh() { :; }
	export -f gh

	local output
	output=$(_gh_config_claude_model "pr")

	[[ "$output" == "haiku" ]]
}

@test "_gh_config_claude_model: _GH_CLAUDE_ARGS --model overrides config" {
	gh() { echo "sonnet"; }
	export -f gh

	_GH_CLAUDE_ARGS=(--model opus)
	local output
	output=$(_gh_config_claude_model "pr")

	[[ "$output" == "opus" ]]
}

@test "_gh_config_claude_model: falls back to config when _GH_CLAUDE_ARGS has no --model" {
	gh() { echo "sonnet"; }
	export -f gh

	_GH_CLAUDE_ARGS=(--verbose)
	local output
	output=$(_gh_config_claude_model)

	[[ "$output" == "sonnet" ]]
}

# ---------------------------------------------------------------------------
# _extract_claude_arg
# ---------------------------------------------------------------------------

@test "_extract_claude_arg: returns value for present flag" {
	_GH_CLAUDE_ARGS=(--model sonnet)
	local output
	output=$(_extract_claude_arg --model)

	[[ "$output" == "sonnet" ]]
}

@test "_extract_claude_arg: returns empty for absent flag" {
	_GH_CLAUDE_ARGS=(--verbose)
	local output
	output=$(_extract_claude_arg --model)

	[[ -z "$output" ]]
}

@test "_extract_claude_arg: returns empty with empty array" {
	_GH_CLAUDE_ARGS=()
	local output
	output=$(_extract_claude_arg --model)

	[[ -z "$output" ]]
}

@test "_extract_claude_arg: handles flag at end without value" {
	_GH_CLAUDE_ARGS=(--model)
	local output
	output=$(_extract_claude_arg --model)

	[[ -z "$output" ]]
}
