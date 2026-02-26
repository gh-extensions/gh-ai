#!/usr/bin/env bats

# Unit tests for gh ai pr create arg parsing and incompatible flag rejection
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_pr_create.bats

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
		declare -f _parse_pr_create_args _show_pr_create_help _gh_pr_create
	)"
}

# ---------------------------------------------------------------------------
# T001: -d/--description captured and excluded from passthrough
# ---------------------------------------------------------------------------

@test "T001: -d flag captures description and excludes it from passthrough args" {
	local base=""
	local description=""
	local args=()
	_parse_pr_create_args base description args -d "focus on security"

	[[ "$description" == "focus on security" ]]
	[[ ${#args[@]} -eq 0 ]]
}

@test "T001: --description flag captures description and excludes it from passthrough args" {
	local base=""
	local description=""
	local args=()
	_parse_pr_create_args base description args --description "improve readability"

	[[ "$description" == "improve readability" ]]
	[[ ${#args[@]} -eq 0 ]]
}

@test "T001: --description=value form captures description" {
	local base=""
	local description=""
	local args=()
	_parse_pr_create_args base description args --description="use imperative mood"

	[[ "$description" == "use imperative mood" ]]
	[[ ${#args[@]} -eq 0 ]]
}

@test "T001: -d flag does not bleed into passthrough args" {
	local base=""
	local description=""
	local args=()
	_parse_pr_create_args base description args --draft -d "context" --no-maintainer-edit

	[[ "$description" == "context" ]]
	[[ ${#args[@]} -eq 2 ]]
	[[ "${args[0]}" == "--draft" ]]
	[[ "${args[1]}" == "--no-maintainer-edit" ]]
}

# ---------------------------------------------------------------------------
# T002: --base/-B captured AND passed through
# ---------------------------------------------------------------------------

@test "T002: --base captures branch and passes through" {
	local base=""
	local description=""
	local args=()
	_parse_pr_create_args base description args --base develop --draft

	[[ "$base" == "develop" ]]
	[[ "${args[0]}" == "--base" ]]
	[[ "${args[1]}" == "develop" ]]
	[[ "${args[2]}" == "--draft" ]]
}

@test "T002: -B captures branch and passes through" {
	local base=""
	local description=""
	local args=()
	_parse_pr_create_args base description args -B main

	[[ "$base" == "main" ]]
	[[ "${args[0]}" == "-B" ]]
	[[ "${args[1]}" == "main" ]]
}

@test "T002: --base=value captures branch and passes through" {
	local base=""
	local description=""
	local args=()
	_parse_pr_create_args base description args --base=develop

	[[ "$base" == "develop" ]]
	[[ "${args[0]}" == "--base=develop" ]]
}

# ---------------------------------------------------------------------------
# T005: AI-managed flags stripped silently
# ---------------------------------------------------------------------------

@test "T005: -t flag is stripped" {
	local base=""
	local description=""
	local args=()
	_parse_pr_create_args base description args -t "ignored title" --draft

	[[ ${#args[@]} -eq 1 ]]
	[[ "${args[0]}" == "--draft" ]]
}

@test "T005: --title flag is stripped" {
	local base=""
	local description=""
	local args=()
	_parse_pr_create_args base description args --title "ignored" --draft

	[[ ${#args[@]} -eq 1 ]]
	[[ "${args[0]}" == "--draft" ]]
}

@test "T005: --title=value form is stripped" {
	local base=""
	local description=""
	local args=()
	_parse_pr_create_args base description args --title="ignored" --draft

	[[ ${#args[@]} -eq 1 ]]
	[[ "${args[0]}" == "--draft" ]]
}

@test "T005: -b flag is stripped" {
	local base=""
	local description=""
	local args=()
	_parse_pr_create_args base description args -b "ignored body" --draft

	[[ ${#args[@]} -eq 1 ]]
	[[ "${args[0]}" == "--draft" ]]
}

@test "T005: --body flag is stripped" {
	local base=""
	local description=""
	local args=()
	_parse_pr_create_args base description args --body "ignored" --draft

	[[ ${#args[@]} -eq 1 ]]
	[[ "${args[0]}" == "--draft" ]]
}

@test "T005: --body=value form is stripped" {
	local base=""
	local description=""
	local args=()
	_parse_pr_create_args base description args --body="ignored" --draft

	[[ ${#args[@]} -eq 1 ]]
	[[ "${args[0]}" == "--draft" ]]
}

@test "T005: -F flag is stripped" {
	local base=""
	local description=""
	local args=()
	_parse_pr_create_args base description args -F body.md --draft

	[[ ${#args[@]} -eq 1 ]]
	[[ "${args[0]}" == "--draft" ]]
}

@test "T005: --body-file flag is stripped" {
	local base=""
	local description=""
	local args=()
	_parse_pr_create_args base description args --body-file body.md --draft

	[[ ${#args[@]} -eq 1 ]]
	[[ "${args[0]}" == "--draft" ]]
}

@test "T005: --body-file=value form is stripped" {
	local base=""
	local description=""
	local args=()
	_parse_pr_create_args base description args --body-file=body.md --draft

	[[ ${#args[@]} -eq 1 ]]
	[[ "${args[0]}" == "--draft" ]]
}

# ---------------------------------------------------------------------------
# T006: Edge cases
# ---------------------------------------------------------------------------

@test "T006: no flags passes all args through" {
	local base=""
	local description=""
	local args=()
	_parse_pr_create_args base description args --draft --label bug

	[[ -z "$description" ]]
	[[ -z "$base" ]]
	[[ ${#args[@]} -eq 3 ]]
	[[ "${args[0]}" == "--draft" ]]
	[[ "${args[1]}" == "--label" ]]
	[[ "${args[2]}" == "bug" ]]
}

@test "T006: -d and --description=value both work in same invocation (last wins)" {
	local base=""
	local description=""
	local args=()
	_parse_pr_create_args base description args -d "first" --description="second"

	[[ "$description" == "second" ]]
}

@test "T006: description with special characters is preserved" {
	local base=""
	local description=""
	local args=()
	local expected='fix: handle $HOME and '"'"'quotes'"'"' & <html>'
	_parse_pr_create_args base description args -d "$expected"

	[[ "$description" == "$expected" ]]
}

# ---------------------------------------------------------------------------
# T007: Missing value errors
# ---------------------------------------------------------------------------

@test "T007: -d without value returns error" {
	local base=""
	local description=""
	local args=()
	run _parse_pr_create_args base description args -d

	[[ "$status" -eq 1 ]]
}

@test "T007: --description without value returns error" {
	local base=""
	local description=""
	local args=()
	run _parse_pr_create_args base description args --description

	[[ "$status" -eq 1 ]]
}

@test "T007: --base without value returns error" {
	local base=""
	local description=""
	local args=()
	run _parse_pr_create_args base description args --base

	[[ "$status" -eq 1 ]]
}

@test "T007: -B without value returns error" {
	local base=""
	local description=""
	local args=()
	run _parse_pr_create_args base description args -B

	[[ "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# T008: Incompatible flags rejected by _gh_pr_create
# ---------------------------------------------------------------------------

@test "T008: --fill is rejected" {
	run _gh_pr_create --fill

	[[ "$status" -eq 1 ]]
}

@test "T008: --fill-first is rejected" {
	run _gh_pr_create --fill-first

	[[ "$status" -eq 1 ]]
}

@test "T008: --fill-verbose is rejected" {
	run _gh_pr_create --fill-verbose

	[[ "$status" -eq 1 ]]
}

@test "T008: -T is rejected" {
	run _gh_pr_create -T my-template.md

	[[ "$status" -eq 1 ]]
}

@test "T008: --template is rejected" {
	run _gh_pr_create --template my-template.md

	[[ "$status" -eq 1 ]]
}

@test "T008: --template=value form is rejected" {
	run _gh_pr_create --template=my-template.md

	[[ "$status" -eq 1 ]]
}
