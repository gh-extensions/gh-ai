#!/usr/bin/env bats

# Unit tests for gh ai issue develop arg parsing and integration
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
		# shellcheck source=../scripts/gh_cmd.sh
		source "$REPO_ROOT/scripts/gh_cmd.sh"
		declare -f _parse_issue_develop_args _show_issue_develop_help _gh_issue_develop _get_title _get_body _split_on_separator
	)"
}

@test "_parse_issue_develop_args: captures issue number from first positional arg" {
	local number=""
	local checkout=false
	local base="" name="" branch_repo=""
	_parse_issue_develop_args number checkout base name branch_repo 42

	[[ "$number" == "42" ]]
	[[ "$checkout" == "false" ]]
	[[ -z "$base" ]]
}

@test "_parse_issue_develop_args: sets base from --base flag" {
	local number=""
	local checkout=false
	local base="" name="" branch_repo=""
	_parse_issue_develop_args number checkout base name branch_repo 42 --base develop

	[[ "$base" == "develop" ]]
	[[ -z "$name" ]]
}

@test "_parse_issue_develop_args: sets base from -b flag" {
	local number=""
	local checkout=false
	local base="" name="" branch_repo=""
	_parse_issue_develop_args number checkout base name branch_repo 42 -b develop

	[[ "$base" == "develop" ]]
}

@test "_parse_issue_develop_args: sets base from --base=value" {
	local number=""
	local checkout=false
	local base="" name="" branch_repo=""
	_parse_issue_develop_args number checkout base name branch_repo 42 --base=develop

	[[ "$base" == "develop" ]]
}

@test "_parse_issue_develop_args: sets name from --name flag" {
	local number=""
	local checkout=false
	local base="" name="" branch_repo=""
	_parse_issue_develop_args number checkout base name branch_repo 42 --name my-branch

	[[ "$name" == "my-branch" ]]
}

@test "_parse_issue_develop_args: sets name from -n flag" {
	local number=""
	local checkout=false
	local base="" name="" branch_repo=""
	_parse_issue_develop_args number checkout base name branch_repo 42 -n my-branch

	[[ "$name" == "my-branch" ]]
}

@test "_parse_issue_develop_args: sets branch_repo from --branch-repo flag" {
	local number=""
	local checkout=false
	local base="" name="" branch_repo=""
	_parse_issue_develop_args number checkout base name branch_repo 42 --branch-repo owner/repo

	[[ "$branch_repo" == "owner/repo" ]]
}

@test "_parse_issue_develop_args: enables checkout with --checkout flag" {
	local number=""
	local checkout=false
	local base="" name="" branch_repo=""
	_parse_issue_develop_args number checkout base name branch_repo 42 --checkout

	[[ "$checkout" == "true" ]]
}

@test "_parse_issue_develop_args: enables checkout with -c flag" {
	local number=""
	local checkout=false
	local base="" name="" branch_repo=""
	_parse_issue_develop_args number checkout base name branch_repo 42 -c

	[[ "$checkout" == "true" ]]
}

@test "_parse_issue_develop_args: parses all flags together" {
	local number=""
	local checkout=false
	local base="" name="" branch_repo=""
	_parse_issue_develop_args number checkout base name branch_repo 42 -c --base develop --name my-branch

	[[ "$number" == "42" ]]
	[[ "$checkout" == "true" ]]
	[[ "$base" == "develop" ]]
	[[ "$name" == "my-branch" ]]
}

@test "_parse_issue_develop_args: returns error with hint for unknown flags" {
	local number=""
	local checkout=false
	local base="" name="" branch_repo=""
	run _parse_issue_develop_args number checkout base name branch_repo 42 --draft

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"use -- to pass flags to gh pr create"* ]]
}

# ---------------------------------------------------------------------------
# Helpers shared by _gh_issue_develop integration tests
# ---------------------------------------------------------------------------

# _setup_develop_mocks sets up gh/git/gum mocks that record calls to temp
# files (passed as arguments) and return appropriate fake values for the full
# develop workflow.  Callers should use BATS_TEST_TMPDIR for the log paths so
# bats cleans them up automatically after each test.
#
# Usage: _setup_develop_mocks <gh_log> <git_log>
_setup_develop_mocks() {
	local gh_log="$1"
	local git_log="$2"

	gh() {
		printf '%s\n' "$@" >>"$gh_log"
		case "$1 $2" in
		"issue view") printf "gh_issue_title='Test Issue'\ngh_issue_body='Issue body'\ngh_issue_labels=''\ngh_issue_comments=''";;
		"issue develop") echo "https://github.com/owner/repo/tree/42-test-issue";;
		"config get") ;;
		"pr create") ;;
		esac
	}
	export -f gh

	git() {
		echo "$*" >>"$git_log"
		case "$1" in
		"rev-parse") echo "abc123sha";;
		"commit-tree") echo "def456sha";;
		esac
	}
	export -f git

	gum() {
		case "$1" in
		spin)
			while [[ $# -gt 0 && "$1" != "--" ]]; do shift; done
			[[ $# -gt 0 ]] && shift
			case "${1:-}" in
			*/gh_cmd.sh) printf '# Test PR Title\n\n## Plan\n\n- Step 1\n';;
			*) "$@";;
			esac
			;;
		log) ;;
		esac
	}
	export -f gum
}

@test "_gh_issue_develop: passes --checkout to gh issue develop when -c given" {
	local gh_log="$BATS_TEST_TMPDIR/gh.log"
	local git_log="$BATS_TEST_TMPDIR/git.log"
	_setup_develop_mocks "$gh_log" "$git_log"

	_gh_issue_develop 42 -c

	grep -qx "develop" "$gh_log"
	grep -qx -- "--checkout" "$gh_log"
	grep -q "commit --allow-empty" "$git_log"
	grep -q "push -u origin HEAD" "$git_log"
	! grep -q "commit-tree" "$git_log"
}

@test "_gh_issue_develop: omits --head from gh pr create in checkout mode" {
	local gh_log="$BATS_TEST_TMPDIR/gh.log"
	local git_log="$BATS_TEST_TMPDIR/git.log"
	_setup_develop_mocks "$gh_log" "$git_log"

	_gh_issue_develop 42 -c

	! grep -qx -- "--head" "$gh_log"
}

@test "_gh_issue_develop: omits --checkout from gh issue develop by default" {
	local gh_log="$BATS_TEST_TMPDIR/gh.log"
	local git_log="$BATS_TEST_TMPDIR/git.log"
	_setup_develop_mocks "$gh_log" "$git_log"

	_gh_issue_develop 42

	grep -qx "develop" "$gh_log"
	! grep -qx -- "--checkout" "$gh_log"
}

@test "_gh_issue_develop: uses commit-tree workflow without --checkout" {
	local gh_log="$BATS_TEST_TMPDIR/gh.log"
	local git_log="$BATS_TEST_TMPDIR/git.log"
	_setup_develop_mocks "$gh_log" "$git_log"

	_gh_issue_develop 42

	grep -q "fetch origin 42-test-issue" "$git_log"
	grep -q "commit-tree" "$git_log"
	grep -q "push origin def456sha:refs/heads/42-test-issue" "$git_log"
}

@test "_gh_issue_develop: passes --head to gh pr create without --checkout" {
	local gh_log="$BATS_TEST_TMPDIR/gh.log"
	local git_log="$BATS_TEST_TMPDIR/git.log"
	_setup_develop_mocks "$gh_log" "$git_log"

	_gh_issue_develop 42

	grep -qx -- "--head" "$gh_log"
	grep -qx "42-test-issue" "$gh_log"
}

@test "_gh_issue_develop: skips empty commit without --checkout" {
	local gh_log="$BATS_TEST_TMPDIR/gh.log"
	local git_log="$BATS_TEST_TMPDIR/git.log"
	_setup_develop_mocks "$gh_log" "$git_log"

	_gh_issue_develop 42

	! grep -q "commit --allow-empty" "$git_log"
	! grep -q "push -u origin HEAD" "$git_log"
}

@test "_gh_issue_develop: forwards --base to gh issue develop in checkout mode" {
	local gh_log="$BATS_TEST_TMPDIR/gh.log"
	local git_log="$BATS_TEST_TMPDIR/git.log"
	_setup_develop_mocks "$gh_log" "$git_log"

	_gh_issue_develop 42 -c -b main

	grep -qx -- "--checkout" "$gh_log"
	grep -qx -- "--base" "$gh_log"
	grep -qx "main" "$gh_log"
}

@test "_gh_issue_develop: fails when gh issue develop returns no branch URL" {
	local gh_log="$BATS_TEST_TMPDIR/gh.log"
	local git_log="$BATS_TEST_TMPDIR/git.log"
	_setup_develop_mocks "$gh_log" "$git_log"

	# Override gh to return empty output for the develop subcommand
	gh() {
		printf '%s\n' "$@" >>"$gh_log"
		case "$1 $2" in
		"issue view") printf "gh_issue_title='Test Issue'\ngh_issue_body='Issue body'\ngh_issue_labels=''\ngh_issue_comments=''";;
		"issue develop") ;;
		"config get") ;;
		esac
	}
	export -f gh

	run _gh_issue_develop 42
	[[ "$status" -eq 1 ]]
}

@test "_gh_issue_develop: forwards -- flags to gh pr create" {
	local gh_log="$BATS_TEST_TMPDIR/gh.log"
	local git_log="$BATS_TEST_TMPDIR/git.log"
	_setup_develop_mocks "$gh_log" "$git_log"

	_gh_issue_develop 42 -- --draft --label enhancement

	grep -qx -- "--draft" "$gh_log"
	grep -qx -- "--label" "$gh_log"
	grep -qx "enhancement" "$gh_log"
}
