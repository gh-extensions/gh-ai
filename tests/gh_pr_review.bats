#!/usr/bin/env bats

# Unit tests for gh ai pr review arg parsing
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_pr_review.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _gh_ai_source_dir="$REPO_ROOT"

	# Mock external commands not under test
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
		declare -f _extract_pr_number _detect_pr_number _parse_pr_args _parse_pr_review_args _show_pr_review_help _gh_pr_review _split_on_separator
	)"
}

@test "_parse_pr_review_args: sets description from -d flag" {
	local number=""
	local description=""
	_parse_pr_review_args number description -d "focus on security"

	[[ "$description" == "focus on security" ]]
}

@test "_parse_pr_review_args: sets description from --description flag" {
	local number=""
	local description=""
	_parse_pr_review_args number description --description "improve readability"

	[[ "$description" == "improve readability" ]]
}

@test "_parse_pr_review_args: sets description from --description=value" {
	local number=""
	local description=""
	_parse_pr_review_args number description --description="use imperative mood"

	[[ "$description" == "use imperative mood" ]]
}

@test "_parse_pr_review_args: captures both PR number and description" {
	local number=""
	local description=""
	_parse_pr_review_args number description 42 -d "focus on security"

	[[ "$number" == "42" ]]
	[[ "$description" == "focus on security" ]]
}

@test "_parse_pr_review_args: accepts empty string for -d" {
	local number=""
	local description=""
	_parse_pr_review_args number description -d ""

	[[ -z "$description" ]]
}

@test "_parse_pr_review_args: preserves special characters in description" {
	local number=""
	local description=""
	local expected='fix: handle $HOME and '"'"'quotes'"'"' & <html>'
	_parse_pr_review_args number description -d "$expected"

	[[ "$description" == "$expected" ]]
}

@test "_parse_pr_review_args: defaults description to empty when no flags given" {
	local number=""
	local description=""
	_parse_pr_review_args number description

	[[ -z "$description" ]]
}

@test "_parse_pr_review_args: last value wins when -d and --description both given" {
	local number=""
	local description=""
	_parse_pr_review_args number description -d "first" --description="second"

	[[ "$description" == "second" ]]
}

@test "_parse_pr_review_args: returns error when -d has no value" {
	local number=""
	local description=""
	run _parse_pr_review_args number description -d

	[[ "$status" -eq 1 ]]
}

@test "_parse_pr_review_args: returns error when --description has no value" {
	local number=""
	local description=""
	run _parse_pr_review_args number description --description

	[[ "$status" -eq 1 ]]
}

@test "_parse_pr_review_args: returns error with hint for unknown flags" {
	local number=""
	local description=""
	run _parse_pr_review_args number description --approve

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"use -- to pass flags to gh pr review"* ]]
}

@test "_parse_pr_review_args: extracts PR number from canonical GitHub URL" {
	local number=""
	local description=""
	_parse_pr_review_args number description "https://github.com/owner/repo/pull/42"

	[[ "$number" == "42" ]]
}

@test "_parse_pr_review_args: extracts PR number from URL with query string" {
	local number=""
	local description=""
	_parse_pr_review_args number description "https://github.com/owner/repo/pull/42?tab=files" -d "focus on security"

	[[ "$number" == "42" ]]
	[[ "$description" == "focus on security" ]]
}

@test "_parse_pr_review_args: returns error for non-GitHub URL" {
	local number=""
	local description=""
	run _parse_pr_review_args number description "https://gitlab.com/owner/repo/merge_requests/42"

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unexpected argument"* ]]
}
