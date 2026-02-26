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

# ---------------------------------------------------------------------------
# T002: Issue number captured from positional arg
# ---------------------------------------------------------------------------

@test "T002: issue number captured as first numeric arg" {
	local number=""
	local checkout=false
	local base="" name="" branch_repo=""
	_parse_issue_develop_args number checkout base name branch_repo 42

	[[ "$number" == "42" ]]
	[[ "$checkout" == "false" ]]
	[[ -z "$base" ]]
}

# ---------------------------------------------------------------------------
# T003: gh issue develop flags captured as scalars
# ---------------------------------------------------------------------------

@test "T003: --base flag captures base value" {
	local number=""
	local checkout=false
	local base="" name="" branch_repo=""
	_parse_issue_develop_args number checkout base name branch_repo 42 --base develop

	[[ "$base" == "develop" ]]
	[[ -z "$name" ]]
}

@test "T003: -b flag captures base value" {
	local number=""
	local checkout=false
	local base="" name="" branch_repo=""
	_parse_issue_develop_args number checkout base name branch_repo 42 -b develop

	[[ "$base" == "develop" ]]
}

@test "T003: --base=value captures base" {
	local number=""
	local checkout=false
	local base="" name="" branch_repo=""
	_parse_issue_develop_args number checkout base name branch_repo 42 --base=develop

	[[ "$base" == "develop" ]]
}

@test "T003: --name flag captures name value" {
	local number=""
	local checkout=false
	local base="" name="" branch_repo=""
	_parse_issue_develop_args number checkout base name branch_repo 42 --name my-branch

	[[ "$name" == "my-branch" ]]
}

@test "T003: -n flag captures name value" {
	local number=""
	local checkout=false
	local base="" name="" branch_repo=""
	_parse_issue_develop_args number checkout base name branch_repo 42 -n my-branch

	[[ "$name" == "my-branch" ]]
}

@test "T003: --branch-repo flag captures branch_repo value" {
	local number=""
	local checkout=false
	local base="" name="" branch_repo=""
	_parse_issue_develop_args number checkout base name branch_repo 42 --branch-repo owner/repo

	[[ "$branch_repo" == "owner/repo" ]]
}

# ---------------------------------------------------------------------------
# T004: Checkout flag handled
# ---------------------------------------------------------------------------

@test "T004: --checkout sets checkout=true" {
	local number=""
	local checkout=false
	local base="" name="" branch_repo=""
	_parse_issue_develop_args number checkout base name branch_repo 42 --checkout

	[[ "$checkout" == "true" ]]
}

@test "T004: -c sets checkout=true" {
	local number=""
	local checkout=false
	local base="" name="" branch_repo=""
	_parse_issue_develop_args number checkout base name branch_repo 42 -c

	[[ "$checkout" == "true" ]]
}

# ---------------------------------------------------------------------------
# T006: Edge cases — combined flags
# ---------------------------------------------------------------------------

@test "T006: all flags parsed together" {
	local number=""
	local checkout=false
	local base="" name="" branch_repo=""
	_parse_issue_develop_args number checkout base name branch_repo 42 -c --base develop --name my-branch

	[[ "$number" == "42" ]]
	[[ "$checkout" == "true" ]]
	[[ "$base" == "develop" ]]
	[[ "$name" == "my-branch" ]]
}

# ---------------------------------------------------------------------------
# Unknown flags before -- produce an error
# ---------------------------------------------------------------------------

@test "unknown flag before -- returns error with hint" {
	local number=""
	local checkout=false
	local base="" name="" branch_repo=""
	run _parse_issue_develop_args number checkout base name branch_repo 42 --draft

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"use -- to pass flags to gh pr create"* ]]
}

# ---------------------------------------------------------------------------
# Helpers shared by T009/T010 integration tests
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

# ---------------------------------------------------------------------------
# T009: checkout path — _gh_issue_develop with --checkout
# ---------------------------------------------------------------------------

@test "T009: checkout path calls gh issue develop with --checkout" {
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

@test "T009: checkout path gh pr create does not include --head" {
	local gh_log="$BATS_TEST_TMPDIR/gh.log"
	local git_log="$BATS_TEST_TMPDIR/git.log"
	_setup_develop_mocks "$gh_log" "$git_log"

	_gh_issue_develop 42 -c

	! grep -qx -- "--head" "$gh_log"
}

# ---------------------------------------------------------------------------
# T010: no-checkout path — _gh_issue_develop without --checkout
# ---------------------------------------------------------------------------

@test "T010: no-checkout path does not call gh issue develop with --checkout" {
	local gh_log="$BATS_TEST_TMPDIR/gh.log"
	local git_log="$BATS_TEST_TMPDIR/git.log"
	_setup_develop_mocks "$gh_log" "$git_log"

	_gh_issue_develop 42

	grep -qx "develop" "$gh_log"
	! grep -qx -- "--checkout" "$gh_log"
}

@test "T010: no-checkout path uses git commit-tree workflow" {
	local gh_log="$BATS_TEST_TMPDIR/gh.log"
	local git_log="$BATS_TEST_TMPDIR/git.log"
	_setup_develop_mocks "$gh_log" "$git_log"

	_gh_issue_develop 42

	grep -q "fetch origin 42-test-issue" "$git_log"
	grep -q "commit-tree" "$git_log"
	grep -q "push origin def456sha:refs/heads/42-test-issue" "$git_log"
}

@test "T010: no-checkout path gh pr create includes --head" {
	local gh_log="$BATS_TEST_TMPDIR/gh.log"
	local git_log="$BATS_TEST_TMPDIR/git.log"
	_setup_develop_mocks "$gh_log" "$git_log"

	_gh_issue_develop 42

	grep -qx -- "--head" "$gh_log"
	grep -qx "42-test-issue" "$gh_log"
}

@test "T010: no-checkout path does not call git commit --allow-empty" {
	local gh_log="$BATS_TEST_TMPDIR/gh.log"
	local git_log="$BATS_TEST_TMPDIR/git.log"
	_setup_develop_mocks "$gh_log" "$git_log"

	_gh_issue_develop 42

	! grep -q "commit --allow-empty" "$git_log"
	! grep -q "push -u origin HEAD" "$git_log"
}

@test "T009: checkout path forwards --base to gh issue develop" {
	local gh_log="$BATS_TEST_TMPDIR/gh.log"
	local git_log="$BATS_TEST_TMPDIR/git.log"
	_setup_develop_mocks "$gh_log" "$git_log"

	_gh_issue_develop 42 -c -b main

	grep -qx -- "--checkout" "$gh_log"
	grep -qx -- "--base" "$gh_log"
	grep -qx "main" "$gh_log"
}

@test "T010: no-checkout path fails when gh issue develop returns empty" {
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

@test "T010: passthrough flags reach gh pr create" {
	local gh_log="$BATS_TEST_TMPDIR/gh.log"
	local git_log="$BATS_TEST_TMPDIR/git.log"
	_setup_develop_mocks "$gh_log" "$git_log"

	_gh_issue_develop 42 -- --draft --label enhancement

	grep -qx -- "--draft" "$gh_log"
	grep -qx -- "--label" "$gh_log"
	grep -qx "enhancement" "$gh_log"
}
