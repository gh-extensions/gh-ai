#!/usr/bin/env bats

# Unit tests for gh claude issue comment arg parsing
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_issue_comment.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _gh_claude_source_dir="$REPO_ROOT"

	gum() { if [[ "$1" == "log" ]]; then shift; shift; shift; echo "$@"; fi; }
	gh() { echo ""; }
	git() { echo ""; }
	export -f gum gh git

	# shellcheck disable=SC2155
	eval "$(
		export _gh_claude_source_dir="$REPO_ROOT"
		# shellcheck source=../scripts/gh_cmd.sh
		source "$REPO_ROOT/scripts/gh_cmd.sh"
		# shellcheck source=../scripts/gh_issue.sh
		source "$REPO_ROOT/scripts/gh_issue.sh"
		declare -f _extract_issue_number _parse_issue_args _parse_issue_comment_args _show_issue_comment_help _gh_issue_comment
	)"
}

@test "_parse_issue_comment_args: sets description from -d flag" {
	local number=""
	local description=""
	local passthrough=()
	_parse_issue_comment_args number description passthrough -d "post a status update"

	[[ "$description" == "post a status update" ]]
}

@test "_parse_issue_comment_args: sets description from --description flag" {
	local number=""
	local description=""
	local passthrough=()
	_parse_issue_comment_args number description passthrough --description "acknowledge the report"

	[[ "$description" == "acknowledge the report" ]]
}

@test "_parse_issue_comment_args: sets description from --description=value" {
	local number=""
	local description=""
	local passthrough=()
	_parse_issue_comment_args number description passthrough --description="acknowledge the report"

	[[ "$description" == "acknowledge the report" ]]
}

@test "_parse_issue_comment_args: captures issue number from first positional arg" {
	local number=""
	local description=""
	local passthrough=()
	_parse_issue_comment_args number description passthrough 42 -d "post a status update"

	[[ "$number" == "42" ]]
	[[ "$description" == "post a status update" ]]
}

@test "_parse_issue_comment_args: strips leading # from issue number" {
	local number=""
	local description=""
	local passthrough=()
	_parse_issue_comment_args number description passthrough "#42" -d "post a status update"

	[[ "$number" == "42" ]]
}

@test "_parse_issue_comment_args: captures issue number without other flags" {
	local number=""
	local description=""
	local passthrough=()
	_parse_issue_comment_args number description passthrough 42

	[[ "$number" == "42" ]]
}

@test "_parse_issue_comment_args: defaults number and description to empty" {
	local number=""
	local description=""
	local passthrough=()
	_parse_issue_comment_args number description passthrough

	[[ -z "$description" ]]
	[[ -z "$number" ]]
}

@test "_parse_issue_comment_args: preserves special characters in description" {
	local number=""
	local description=""
	local passthrough=()
	local expected='fix: handle $HOME and '"'"'quotes'"'"' & <html>'
	_parse_issue_comment_args number description passthrough -d "$expected"

	[[ "$description" == "$expected" ]]
}

@test "_parse_issue_comment_args: last value wins when -d and --description both given" {
	local number=""
	local description=""
	local passthrough=()
	_parse_issue_comment_args number description passthrough -d "first" --description="second"

	[[ "$description" == "second" ]]
}

@test "_parse_issue_comment_args: returns error when -d has no value" {
	local number=""
	local description=""
	local passthrough=()
	run _parse_issue_comment_args number description passthrough -d

	[[ "$status" -eq 1 ]]
}

@test "_parse_issue_comment_args: collects unknown flags as passthrough" {
	local number=""
	local description=""
	local passthrough=()
	_parse_issue_comment_args number description passthrough --edit

	[[ "${passthrough[0]}" == "--edit" ]]
}

@test "_parse_issue_comment_args: known flags before unknown flag works correctly" {
	local number=""
	local description=""
	local passthrough=()
	_parse_issue_comment_args number description passthrough 42 -d "status update" --edit

	[[ "$number" == "42" ]]
	[[ "$description" == "status update" ]]
	[[ "${passthrough[0]}" == "--edit" ]]
}

@test "_parse_issue_comment_args: accepts GitHub issue URL as issue number" {
	local number=""
	local description=""
	local passthrough=()
	_parse_issue_comment_args number description passthrough "https://github.com/owner/repo/issues/42" -d "post a status update"

	[[ "$number" == "42" ]]
	[[ "$description" == "post a status update" ]]
}
