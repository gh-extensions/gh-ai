#!/usr/bin/env bats

# Unit tests for gh ai pr edit arg parsing
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_pr_edit.bats

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
		# shellcheck source=../scripts/gh_pr.sh
		source "$REPO_ROOT/scripts/gh_pr.sh"
		declare -f _parse_pr_edit_args _show_pr_edit_help _gh_pr_edit
	)"
}

# ---------------------------------------------------------------------------
# T001: -d/--description captured and excluded from passthrough
# ---------------------------------------------------------------------------

@test "T001: -d flag captures description and excludes it from passthrough args" {
	local number=""
	local description=""
	local args=()
	_parse_pr_edit_args number description args -d "add testing section"

	[[ "$description" == "add testing section" ]]
	[[ ${#args[@]} -eq 0 ]]
}

@test "T001: --description flag captures description and excludes it from passthrough args" {
	local number=""
	local description=""
	local args=()
	_parse_pr_edit_args number description args --description "fix summary"

	[[ "$description" == "fix summary" ]]
	[[ ${#args[@]} -eq 0 ]]
}

@test "T001: --description=value form captures description" {
	local number=""
	local description=""
	local args=()
	_parse_pr_edit_args number description args --description="improve wording"

	[[ "$description" == "improve wording" ]]
	[[ ${#args[@]} -eq 0 ]]
}

@test "T001: -d flag does not bleed into passthrough args" {
	local number=""
	local description=""
	local args=()
	_parse_pr_edit_args number description args -d "context" --add-label bug

	[[ "$description" == "context" ]]
	[[ ${#args[@]} -eq 2 ]]
	[[ "${args[0]}" == "--add-label" ]]
	[[ "${args[1]}" == "bug" ]]
}

# ---------------------------------------------------------------------------
# T002: PR number captured from positional arg
# ---------------------------------------------------------------------------

@test "T002: PR number captured as first numeric arg" {
	local number=""
	local description=""
	local args=()
	_parse_pr_edit_args number description args 42 -d "fix summary"

	[[ "$number" == "42" ]]
	[[ "$description" == "fix summary" ]]
	[[ ${#args[@]} -eq 0 ]]
}

@test "T002: PR number does not bleed into passthrough args" {
	local number=""
	local description=""
	local args=()
	_parse_pr_edit_args number description args 42 --add-label bug

	[[ "$number" == "42" ]]
	[[ ${#args[@]} -eq 2 ]]
	[[ "${args[0]}" == "--add-label" ]]
	[[ "${args[1]}" == "bug" ]]
}

@test "T002: non-numeric arg is not captured as PR number" {
	local number=""
	local description=""
	local args=()
	_parse_pr_edit_args number description args --add-label bug

	[[ -z "$number" ]]
	[[ ${#args[@]} -eq 2 ]]
}

# ---------------------------------------------------------------------------
# T005: AI-managed flags stripped silently
# ---------------------------------------------------------------------------

@test "T005: -t flag is stripped" {
	local number=""
	local description=""
	local args=()
	_parse_pr_edit_args number description args -t "ignored title" --add-label bug

	[[ ${#args[@]} -eq 2 ]]
	[[ "${args[0]}" == "--add-label" ]]
	[[ "${args[1]}" == "bug" ]]
}

@test "T005: --title flag is stripped" {
	local number=""
	local description=""
	local args=()
	_parse_pr_edit_args number description args --title "ignored" --add-label bug

	[[ ${#args[@]} -eq 2 ]]
	[[ "${args[0]}" == "--add-label" ]]
}

@test "T005: --title=value form is stripped" {
	local number=""
	local description=""
	local args=()
	_parse_pr_edit_args number description args --title="ignored" --add-label bug

	[[ ${#args[@]} -eq 2 ]]
	[[ "${args[0]}" == "--add-label" ]]
}

@test "T005: -b flag is stripped" {
	local number=""
	local description=""
	local args=()
	_parse_pr_edit_args number description args -b "ignored body" --add-label bug

	[[ ${#args[@]} -eq 2 ]]
	[[ "${args[0]}" == "--add-label" ]]
}

@test "T005: --body flag is stripped" {
	local number=""
	local description=""
	local args=()
	_parse_pr_edit_args number description args --body "ignored" --add-label bug

	[[ ${#args[@]} -eq 2 ]]
	[[ "${args[0]}" == "--add-label" ]]
}

@test "T005: --body=value form is stripped" {
	local number=""
	local description=""
	local args=()
	_parse_pr_edit_args number description args --body="ignored" --add-label bug

	[[ ${#args[@]} -eq 2 ]]
	[[ "${args[0]}" == "--add-label" ]]
}

@test "T005: -F flag is stripped" {
	local number=""
	local description=""
	local args=()
	_parse_pr_edit_args number description args -F body.md --add-label bug

	[[ ${#args[@]} -eq 2 ]]
	[[ "${args[0]}" == "--add-label" ]]
}

@test "T005: --body-file flag is stripped" {
	local number=""
	local description=""
	local args=()
	_parse_pr_edit_args number description args --body-file body.md --add-label bug

	[[ ${#args[@]} -eq 2 ]]
	[[ "${args[0]}" == "--add-label" ]]
}

@test "T005: --body-file=value form is stripped" {
	local number=""
	local description=""
	local args=()
	_parse_pr_edit_args number description args --body-file=body.md --add-label bug

	[[ ${#args[@]} -eq 2 ]]
	[[ "${args[0]}" == "--add-label" ]]
}

# ---------------------------------------------------------------------------
# T006: Edge cases
# ---------------------------------------------------------------------------

@test "T006: no flags leaves description empty and passes all args" {
	local number=""
	local description=""
	local args=()
	_parse_pr_edit_args number description args --add-label bug --remove-label wip

	[[ -z "$description" ]]
	[[ ${#args[@]} -eq 4 ]]
}

@test "T006: -d and --description=value both work in same invocation (last wins)" {
	local number=""
	local description=""
	local args=()
	_parse_pr_edit_args number description args -d "first" --description="second"

	[[ "$description" == "second" ]]
}

@test "T006: description with special characters is preserved" {
	local number=""
	local description=""
	local args=()
	local expected='fix: handle $HOME and '"'"'quotes'"'"' & <html>'
	_parse_pr_edit_args number description args -d "$expected"

	[[ "$description" == "$expected" ]]
}

# ---------------------------------------------------------------------------
# T007: Missing value errors
# ---------------------------------------------------------------------------

@test "T007: -d without value returns error" {
	local number=""
	local description=""
	local args=()
	run _parse_pr_edit_args number description args -d

	[[ "$status" -eq 1 ]]
}

@test "T007: --description without value returns error" {
	local number=""
	local description=""
	local args=()
	run _parse_pr_edit_args number description args --description

	[[ "$status" -eq 1 ]]
}
