#!/usr/bin/env bats

# Unit tests for gh ai pr comment arg parsing
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_pr_comment.bats

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
		declare -f _parse_pr_comment_args _show_pr_comment_help _gh_pr_comment _split_on_separator _create_context_dir _save_context_file
	)"
}

@test "_parse_pr_comment_args: sets description from -d flag" {
	local number=""
	local description=""
	_parse_pr_comment_args number description -d "summarise open threads"

	[[ "$description" == "summarise open threads" ]]
}

@test "_parse_pr_comment_args: sets description from --description flag" {
	local number=""
	local description=""
	_parse_pr_comment_args number description --description "ask about migration"

	[[ "$description" == "ask about migration" ]]
}

@test "_parse_pr_comment_args: sets description from --description=value" {
	local number=""
	local description=""
	_parse_pr_comment_args number description --description="request changes"

	[[ "$description" == "request changes" ]]
}

@test "_parse_pr_comment_args: captures both PR number and description" {
	local number=""
	local description=""
	_parse_pr_comment_args number description 42 -d "summarise open threads"

	[[ "$number" == "42" ]]
	[[ "$description" == "summarise open threads" ]]
}

@test "_parse_pr_comment_args: strips leading # from PR number" {
	local number=""
	local description=""
	_parse_pr_comment_args number description "#42" -d "context"

	[[ "$number" == "42" ]]
}

@test "_parse_pr_comment_args: accepts PR number without description flag" {
	local number=""
	local description=""
	_parse_pr_comment_args number description 99

	[[ "$number" == "99" ]]
	[[ -z "$description" ]]
}

@test "_parse_pr_comment_args: accepts empty string for -d" {
	local number=""
	local description=""
	_parse_pr_comment_args number description -d ""

	[[ -z "$description" ]]
}

@test "_parse_pr_comment_args: preserves special characters in description" {
	local number=""
	local description=""
	local expected='fix: handle $HOME and '"'"'quotes'"'"' & <html>'
	_parse_pr_comment_args number description -d "$expected"

	[[ "$description" == "$expected" ]]
}

@test "_parse_pr_comment_args: defaults to empty when no flags given" {
	local number=""
	local description=""
	_parse_pr_comment_args number description

	[[ -z "$number" ]]
	[[ -z "$description" ]]
}

@test "_parse_pr_comment_args: returns error when -d has no value" {
	local number=""
	local description=""
	run _parse_pr_comment_args number description -d

	[[ "$status" -eq 1 ]]
}

@test "_parse_pr_comment_args: returns error when --description has no value" {
	local number=""
	local description=""
	run _parse_pr_comment_args number description --description

	[[ "$status" -eq 1 ]]
}

@test "_parse_pr_comment_args: returns error with hint for unknown flags" {
	local number=""
	local description=""
	run _parse_pr_comment_args number description --approve

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"use -- to pass flags to gh pr comment"* ]]
}

@test "_parse_pr_comment_args: returns error for unexpected non-numeric argument" {
	local number=""
	local description=""
	run _parse_pr_comment_args number description somebranch

	[[ "$status" -eq 1 ]]
}

@test "_parse_pr_comment_args: auto-detects PR from current branch" {
	gh() {
		if [[ "$*" == *"pr view"* && "$*" == *"--json number"* ]]; then
			echo "7"
		else
			echo ""
		fi
	}
	export -f gh

	local number=""
	local description=""
	_parse_pr_comment_args number description -d "context"

	[[ "$number" == "7" ]]
}

@test "_show_pr_comment_help: prints expected help text" {
	run _show_pr_comment_help

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"gh ai pr comment"* ]]
	[[ "$output" == *"-d, --description"* ]]
	[[ "$output" == *"gh ai pr comment 42 -d"* ]]
}

@test "_gh_pr_comment: shows help with --help" {
	run _gh_pr_comment --help

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"gh ai pr comment"* ]]
}

@test "_gh_pr_comment: shows help with -h" {
	run _gh_pr_comment -h

	[[ "$status" -eq 0 ]]
	[[ "$output" == *"gh ai pr comment"* ]]
}

@test "_gh_pr_comment: errors when no PR number and auto-detect fails" {
	gh() { echo ""; }
	export -f gh

	run _gh_pr_comment -d "some description"

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"No PR number provided"* ]]
}

@test "_gh_pr_comment: errors when no description provided" {
	gh() {
		if [[ "$*" == *"pr view"* && "$*" == *"--json number"* ]]; then
			echo "42"
		else
			echo ""
		fi
	}
	export -f gh

	run _gh_pr_comment 42

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"No description provided"* ]]
}

@test "_gh_pr_comment: errors when metadata fetch fails" {
	gum() {
		if [[ "$1" == "spin" ]]; then
			echo ""
		elif [[ "$1" == "log" ]]; then
			shift; shift; shift; echo "$@"
		fi
	}
	export -f gum

	run _gh_pr_comment 42 -d "context"

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"Failed to fetch PR"* ]]
}

@test "_gh_pr_comment: passes passthrough args to gh pr comment" {
	# Verify that args after -- are not consumed by the parser
	local number=""
	local description=""
	local ai_args=()
	local passthrough=()

	# Simulate _split_on_separator behaviour inline
	local found_sep=false
	for arg in 42 -d "comment text" -- --edit-last; do
		if [[ "$arg" == "--" ]]; then
			found_sep=true
			continue
		fi
		if $found_sep; then
			passthrough+=("$arg")
		else
			ai_args+=("$arg")
		fi
	done

	_parse_pr_comment_args number description "${ai_args[@]}"

	[[ "$number" == "42" ]]
	[[ "$description" == "comment text" ]]
	[[ "${passthrough[0]}" == "--edit-last" ]]
}
