#!/usr/bin/env bats

# Unit tests for gh ai issue develop arg parsing and incompatible flag rejection
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_issue_develop.bats

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
		declare -f _parse_issue_develop_args _show_issue_develop_help _gh_issue_develop
	)"
}

# ---------------------------------------------------------------------------
# T002: Issue number captured from positional arg
# ---------------------------------------------------------------------------

@test "T002: issue number captured as first numeric arg" {
	local number=""
	local issue_args=()
	local pr_args=()
	_parse_issue_develop_args number issue_args pr_args 42

	[[ "$number" == "42" ]]
	[[ ${#issue_args[@]} -eq 0 ]]
	[[ ${#pr_args[@]} -eq 0 ]]
}

@test "T002: issue number does not bleed into passthrough args" {
	local number=""
	local issue_args=()
	local pr_args=()
	_parse_issue_develop_args number issue_args pr_args 42 --draft

	[[ "$number" == "42" ]]
	[[ ${#pr_args[@]} -eq 1 ]]
	[[ "${pr_args[0]}" == "--draft" ]]
}

# ---------------------------------------------------------------------------
# T003: gh issue develop flags go to issue args
# ---------------------------------------------------------------------------

@test "T003: --base flag goes to issue args" {
	local number=""
	local issue_args=()
	local pr_args=()
	_parse_issue_develop_args number issue_args pr_args 42 --base develop

	[[ "${issue_args[0]}" == "--base" ]]
	[[ "${issue_args[1]}" == "develop" ]]
	[[ ${#pr_args[@]} -eq 0 ]]
}

@test "T003: -b flag goes to issue args" {
	local number=""
	local issue_args=()
	local pr_args=()
	_parse_issue_develop_args number issue_args pr_args 42 -b develop

	[[ "${issue_args[0]}" == "-b" ]]
	[[ "${issue_args[1]}" == "develop" ]]
	[[ ${#pr_args[@]} -eq 0 ]]
}

@test "T003: --base=value goes to issue args" {
	local number=""
	local issue_args=()
	local pr_args=()
	_parse_issue_develop_args number issue_args pr_args 42 --base=develop

	[[ "${issue_args[0]}" == "--base=develop" ]]
	[[ ${#pr_args[@]} -eq 0 ]]
}

@test "T003: --name flag goes to issue args" {
	local number=""
	local issue_args=()
	local pr_args=()
	_parse_issue_develop_args number issue_args pr_args 42 --name my-branch

	[[ "${issue_args[0]}" == "--name" ]]
	[[ "${issue_args[1]}" == "my-branch" ]]
	[[ ${#pr_args[@]} -eq 0 ]]
}

@test "T003: -n flag goes to issue args" {
	local number=""
	local issue_args=()
	local pr_args=()
	_parse_issue_develop_args number issue_args pr_args 42 -n my-branch

	[[ "${issue_args[0]}" == "-n" ]]
	[[ "${issue_args[1]}" == "my-branch" ]]
	[[ ${#pr_args[@]} -eq 0 ]]
}

@test "T003: --branch-repo flag goes to issue args" {
	local number=""
	local issue_args=()
	local pr_args=()
	_parse_issue_develop_args number issue_args pr_args 42 --branch-repo owner/repo

	[[ "${issue_args[0]}" == "--branch-repo" ]]
	[[ "${issue_args[1]}" == "owner/repo" ]]
	[[ ${#pr_args[@]} -eq 0 ]]
}

# ---------------------------------------------------------------------------
# T004: Develop-only flags stripped (not relevant for gh pr create)
# ---------------------------------------------------------------------------

@test "T004: --checkout is stripped" {
	local number=""
	local issue_args=()
	local pr_args=()
	_parse_issue_develop_args number issue_args pr_args 42 --checkout --draft

	[[ ${#issue_args[@]} -eq 0 ]]
	[[ "${pr_args[0]}" == "--draft" ]]
}

@test "T004: -c is stripped" {
	local number=""
	local issue_args=()
	local pr_args=()
	_parse_issue_develop_args number issue_args pr_args 42 -c --draft

	[[ ${#issue_args[@]} -eq 0 ]]
	[[ "${pr_args[0]}" == "--draft" ]]
}

@test "T004: --head flag is stripped" {
	local number=""
	local issue_args=()
	local pr_args=()
	_parse_issue_develop_args number issue_args pr_args 42 --head my-branch --draft

	[[ ${#issue_args[@]} -eq 0 ]]
	[[ "${pr_args[0]}" == "--draft" ]]
}

@test "T004: -H flag is stripped" {
	local number=""
	local issue_args=()
	local pr_args=()
	_parse_issue_develop_args number issue_args pr_args 42 -H my-branch --draft

	[[ ${#issue_args[@]} -eq 0 ]]
	[[ "${pr_args[0]}" == "--draft" ]]
}

@test "T004: -B flag is stripped" {
	local number=""
	local issue_args=()
	local pr_args=()
	_parse_issue_develop_args number issue_args pr_args 42 -B main --draft

	[[ ${#issue_args[@]} -eq 0 ]]
	[[ "${pr_args[0]}" == "--draft" ]]
}

# ---------------------------------------------------------------------------
# T005: AI-managed flags stripped silently
# ---------------------------------------------------------------------------

@test "T005: -t flag is stripped" {
	local number=""
	local issue_args=()
	local pr_args=()
	_parse_issue_develop_args number issue_args pr_args 42 -t "ignored" --draft

	[[ ${#issue_args[@]} -eq 0 ]]
	[[ "${pr_args[0]}" == "--draft" ]]
}

@test "T005: --title flag is stripped" {
	local number=""
	local issue_args=()
	local pr_args=()
	_parse_issue_develop_args number issue_args pr_args 42 --title "ignored" --draft

	[[ ${#issue_args[@]} -eq 0 ]]
	[[ "${pr_args[0]}" == "--draft" ]]
}

@test "T005: --body flag is stripped" {
	local number=""
	local issue_args=()
	local pr_args=()
	_parse_issue_develop_args number issue_args pr_args 42 --body "ignored" --draft

	[[ ${#issue_args[@]} -eq 0 ]]
	[[ "${pr_args[0]}" == "--draft" ]]
}

@test "T005: -F flag is stripped" {
	local number=""
	local issue_args=()
	local pr_args=()
	_parse_issue_develop_args number issue_args pr_args 42 -F body.md --draft

	[[ ${#issue_args[@]} -eq 0 ]]
	[[ "${pr_args[0]}" == "--draft" ]]
}

@test "T005: --body-file flag is stripped" {
	local number=""
	local issue_args=()
	local pr_args=()
	_parse_issue_develop_args number issue_args pr_args 42 --body-file body.md --draft

	[[ ${#issue_args[@]} -eq 0 ]]
	[[ "${pr_args[0]}" == "--draft" ]]
}

# ---------------------------------------------------------------------------
# T006: Edge cases
# ---------------------------------------------------------------------------

@test "T006: PR passthrough flags go to pr args" {
	local number=""
	local issue_args=()
	local pr_args=()
	_parse_issue_develop_args number issue_args pr_args 42 --draft --label enhancement

	[[ ${#issue_args[@]} -eq 0 ]]
	[[ "${pr_args[0]}" == "--draft" ]]
	[[ "${pr_args[1]}" == "--label" ]]
	[[ "${pr_args[2]}" == "enhancement" ]]
}

@test "T006: issue and PR flags are correctly separated" {
	local number=""
	local issue_args=()
	local pr_args=()
	_parse_issue_develop_args number issue_args pr_args 42 --base develop --draft --label bug

	[[ "$number" == "42" ]]
	[[ "${issue_args[0]}" == "--base" ]]
	[[ "${issue_args[1]}" == "develop" ]]
	[[ "${pr_args[0]}" == "--draft" ]]
	[[ "${pr_args[1]}" == "--label" ]]
	[[ "${pr_args[2]}" == "bug" ]]
}

# ---------------------------------------------------------------------------
# T008: Incompatible flags rejected by _gh_issue_develop
# ---------------------------------------------------------------------------

@test "T008: --fill is rejected" {
	run _gh_issue_develop 42 --fill

	[[ "$status" -eq 1 ]]
}

@test "T008: --fill-first is rejected" {
	run _gh_issue_develop 42 --fill-first

	[[ "$status" -eq 1 ]]
}

@test "T008: --fill-verbose is rejected" {
	run _gh_issue_develop 42 --fill-verbose

	[[ "$status" -eq 1 ]]
}

@test "T008: -T is rejected" {
	run _gh_issue_develop 42 -T my-template.md

	[[ "$status" -eq 1 ]]
}

@test "T008: --template is rejected" {
	run _gh_issue_develop 42 --template my-template.md

	[[ "$status" -eq 1 ]]
}

@test "T008: --template=value form is rejected" {
	run _gh_issue_develop 42 --template=my-template.md

	[[ "$status" -eq 1 ]]
}
