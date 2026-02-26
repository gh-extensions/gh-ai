#!/usr/bin/env bats

# Unit tests for gh ai issue create arg parsing and incompatible flag rejection
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_issue_create.bats

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
		# shellcheck source=../scripts/gh_issue.sh
		source "$REPO_ROOT/scripts/gh_issue.sh"
		declare -f _parse_issue_create_args _show_issue_create_help _gh_issue_create
	)"
}

# ---------------------------------------------------------------------------
# T001: -d/--description captured and excluded from passthrough
# ---------------------------------------------------------------------------

@test "T001: -d flag captures description and excludes it from passthrough args" {
	local description=""
	local labels=""
	local args=()
	_parse_issue_create_args description labels args -d "Login page crashes"

	[[ "$description" == "Login page crashes" ]]
	[[ ${#args[@]} -eq 0 ]]
}

@test "T001: --description flag captures description and excludes it from passthrough args" {
	local description=""
	local labels=""
	local args=()
	_parse_issue_create_args description labels args --description "Login page crashes"

	[[ "$description" == "Login page crashes" ]]
	[[ ${#args[@]} -eq 0 ]]
}

@test "T001: --description=value form captures description" {
	local description=""
	local labels=""
	local args=()
	_parse_issue_create_args description labels args --description="Login page crashes"

	[[ "$description" == "Login page crashes" ]]
	[[ ${#args[@]} -eq 0 ]]
}

@test "T001: -d flag does not bleed into passthrough args" {
	local description=""
	local labels=""
	local args=()
	_parse_issue_create_args description labels args -d "crash" --assignee @me

	[[ "$description" == "crash" ]]
	[[ ${#args[@]} -eq 2 ]]
	[[ "${args[0]}" == "--assignee" ]]
	[[ "${args[1]}" == "@me" ]]
}

# ---------------------------------------------------------------------------
# T002: --label/-l captured into labels string AND passed through
# ---------------------------------------------------------------------------

@test "T002: --label flag captured into labels and passed through" {
	local description=""
	local labels=""
	local args=()
	_parse_issue_create_args description labels args --label bug

	[[ "$labels" == "bug" ]]
	[[ "${args[0]}" == "--label" ]]
	[[ "${args[1]}" == "bug" ]]
}

@test "T002: -l flag captured into labels and passed through" {
	local description=""
	local labels=""
	local args=()
	_parse_issue_create_args description labels args -l bug

	[[ "$labels" == "bug" ]]
	[[ "${args[0]}" == "-l" ]]
	[[ "${args[1]}" == "bug" ]]
}

@test "T002: --label=value form captured into labels and passed through" {
	local description=""
	local labels=""
	local args=()
	_parse_issue_create_args description labels args --label=bug

	[[ "$labels" == "bug" ]]
	[[ "${args[0]}" == "--label=bug" ]]
}

@test "T002: multiple labels are comma-separated in labels string" {
	local description=""
	local labels=""
	local args=()
	_parse_issue_create_args description labels args --label bug --label enhancement

	[[ "$labels" == "bug, enhancement" ]]
	[[ ${#args[@]} -eq 4 ]]
}

# ---------------------------------------------------------------------------
# T005: AI-managed flags stripped silently
# ---------------------------------------------------------------------------

@test "T005: -t flag is stripped" {
	local description=""
	local labels=""
	local args=()
	_parse_issue_create_args description labels args -t "ignored title" --assignee @me

	[[ ${#args[@]} -eq 2 ]]
	[[ "${args[0]}" == "--assignee" ]]
}

@test "T005: --title flag is stripped" {
	local description=""
	local labels=""
	local args=()
	_parse_issue_create_args description labels args --title "ignored" --assignee @me

	[[ ${#args[@]} -eq 2 ]]
	[[ "${args[0]}" == "--assignee" ]]
}

@test "T005: --title=value form is stripped" {
	local description=""
	local labels=""
	local args=()
	_parse_issue_create_args description labels args --title="ignored" --assignee @me

	[[ ${#args[@]} -eq 2 ]]
	[[ "${args[0]}" == "--assignee" ]]
}

@test "T005: -b flag is stripped" {
	local description=""
	local labels=""
	local args=()
	_parse_issue_create_args description labels args -b "ignored body" --assignee @me

	[[ ${#args[@]} -eq 2 ]]
	[[ "${args[0]}" == "--assignee" ]]
}

@test "T005: --body flag is stripped" {
	local description=""
	local labels=""
	local args=()
	_parse_issue_create_args description labels args --body "ignored" --assignee @me

	[[ ${#args[@]} -eq 2 ]]
	[[ "${args[0]}" == "--assignee" ]]
}

@test "T005: --body=value form is stripped" {
	local description=""
	local labels=""
	local args=()
	_parse_issue_create_args description labels args --body="ignored" --assignee @me

	[[ ${#args[@]} -eq 2 ]]
	[[ "${args[0]}" == "--assignee" ]]
}

@test "T005: -F flag is stripped" {
	local description=""
	local labels=""
	local args=()
	_parse_issue_create_args description labels args -F body.md --assignee @me

	[[ ${#args[@]} -eq 2 ]]
	[[ "${args[0]}" == "--assignee" ]]
}

@test "T005: --body-file flag is stripped" {
	local description=""
	local labels=""
	local args=()
	_parse_issue_create_args description labels args --body-file body.md --assignee @me

	[[ ${#args[@]} -eq 2 ]]
	[[ "${args[0]}" == "--assignee" ]]
}

@test "T005: --body-file=value form is stripped" {
	local description=""
	local labels=""
	local args=()
	_parse_issue_create_args description labels args --body-file=body.md --assignee @me

	[[ ${#args[@]} -eq 2 ]]
	[[ "${args[0]}" == "--assignee" ]]
}

# ---------------------------------------------------------------------------
# T006: Edge cases
# ---------------------------------------------------------------------------

@test "T006: no flags leaves description empty and passes all args" {
	local description=""
	local labels=""
	local args=()
	_parse_issue_create_args description labels args --assignee @me --milestone v1.0

	[[ -z "$description" ]]
	[[ -z "$labels" ]]
	[[ ${#args[@]} -eq 4 ]]
}

@test "T006: description with special characters is preserved" {
	local description=""
	local labels=""
	local args=()
	local expected='fix: handle $HOME and '"'"'quotes'"'"' & <html>'
	_parse_issue_create_args description labels args -d "$expected"

	[[ "$description" == "$expected" ]]
}

# ---------------------------------------------------------------------------
# T008: Incompatible flags rejected by _gh_issue_create
# ---------------------------------------------------------------------------

@test "T008: -T is rejected" {
	run _gh_issue_create -d "some issue" -T my-template.md

	[[ "$status" -eq 1 ]]
}

@test "T008: --template is rejected" {
	run _gh_issue_create -d "some issue" --template my-template.md

	[[ "$status" -eq 1 ]]
}

@test "T008: --template=value form is rejected" {
	run _gh_issue_create -d "some issue" --template=my-template.md

	[[ "$status" -eq 1 ]]
}
