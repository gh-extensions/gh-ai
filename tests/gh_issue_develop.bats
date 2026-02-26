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
		declare -f _parse_issue_develop_args _show_issue_develop_help _gh_issue_develop \
			_gh_issue_develop_remotely _gh_issue_develop_no_checkout \
			_cmd_assist_remotely _get_title _get_body _split_on_separator
	)"
}

# ---------------------------------------------------------------------------
# _parse_issue_develop_args: issue number
# ---------------------------------------------------------------------------

@test "_parse_issue_develop_args: sets number from first positional arg" {
	local number="" checkout=false base="" name="" branch_repo="" agent=""
	_parse_issue_develop_args number checkout base name branch_repo agent 42

	[[ "$number" == "42" ]]
	[[ "$checkout" == "false" ]]
	[[ -z "$base" ]]
}

# ---------------------------------------------------------------------------
# _parse_issue_develop_args: branch flags
# ---------------------------------------------------------------------------

@test "_parse_issue_develop_args: sets base from --base flag" {
	local number="" checkout=false base="" name="" branch_repo="" agent=""
	_parse_issue_develop_args number checkout base name branch_repo agent 42 --base develop

	[[ "$base" == "develop" ]]
}

@test "_parse_issue_develop_args: sets base from -b flag" {
	local number="" checkout=false base="" name="" branch_repo="" agent=""
	_parse_issue_develop_args number checkout base name branch_repo agent 42 -b develop

	[[ "$base" == "develop" ]]
}

@test "_parse_issue_develop_args: sets base from --base=value form" {
	local number="" checkout=false base="" name="" branch_repo="" agent=""
	_parse_issue_develop_args number checkout base name branch_repo agent 42 --base=develop

	[[ "$base" == "develop" ]]
}

@test "_parse_issue_develop_args: sets name from --name flag" {
	local number="" checkout=false base="" name="" branch_repo="" agent=""
	_parse_issue_develop_args number checkout base name branch_repo agent 42 --name my-branch

	[[ "$name" == "my-branch" ]]
}

@test "_parse_issue_develop_args: sets name from -n flag" {
	local number="" checkout=false base="" name="" branch_repo="" agent=""
	_parse_issue_develop_args number checkout base name branch_repo agent 42 -n my-branch

	[[ "$name" == "my-branch" ]]
}

@test "_parse_issue_develop_args: sets branch_repo from --branch-repo flag" {
	local number="" checkout=false base="" name="" branch_repo="" agent=""
	_parse_issue_develop_args number checkout base name branch_repo agent 42 --branch-repo owner/repo

	[[ "$branch_repo" == "owner/repo" ]]
}

# ---------------------------------------------------------------------------
# _parse_issue_develop_args: checkout flag
# ---------------------------------------------------------------------------

@test "_parse_issue_develop_args: sets checkout=true from --checkout flag" {
	local number="" checkout=false base="" name="" branch_repo="" agent=""
	_parse_issue_develop_args number checkout base name branch_repo agent 42 --checkout

	[[ "$checkout" == "true" ]]
}

@test "_parse_issue_develop_args: sets checkout=true from -c flag" {
	local number="" checkout=false base="" name="" branch_repo="" agent=""
	_parse_issue_develop_args number checkout base name branch_repo agent 42 -c

	[[ "$checkout" == "true" ]]
}

# ---------------------------------------------------------------------------
# _parse_issue_develop_args: --agent flag
# ---------------------------------------------------------------------------

@test "_parse_issue_develop_args: sets agent from --agent flag" {
	local number="" checkout=false base="" name="" branch_repo="" agent=""
	_parse_issue_develop_args number checkout base name branch_repo agent 42 --agent @claude

	[[ "$agent" == "@claude" ]]
}

@test "_parse_issue_develop_args: sets agent from --agent=value form" {
	local number="" checkout=false base="" name="" branch_repo="" agent=""
	_parse_issue_develop_args number checkout base name branch_repo agent 42 --agent=@jules

	[[ "$agent" == "@jules" ]]
}

@test "_parse_issue_develop_args: sets agent to @copilot" {
	local number="" checkout=false base="" name="" branch_repo="" agent=""
	_parse_issue_develop_args number checkout base name branch_repo agent 42 --agent=@copilot

	[[ "$agent" == "@copilot" ]]
}

@test "_parse_issue_develop_args: --agent without value returns error" {
	local number="" checkout=false base="" name="" branch_repo="" agent=""
	run _parse_issue_develop_args number checkout base name branch_repo agent 42 --agent

	[[ "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# _parse_issue_develop_args: combined flags
# ---------------------------------------------------------------------------

@test "_parse_issue_develop_args: parses all flags together" {
	local number="" checkout=false base="" name="" branch_repo="" agent=""
	_parse_issue_develop_args number checkout base name branch_repo agent 42 -c --base develop --name my-branch

	[[ "$number" == "42" ]]
	[[ "$checkout" == "true" ]]
	[[ "$base" == "develop" ]]
	[[ "$name" == "my-branch" ]]
}

# ---------------------------------------------------------------------------
# _parse_issue_develop_args: unknown flag error
# ---------------------------------------------------------------------------

@test "_parse_issue_develop_args: unknown flag before -- returns error with hint" {
	local number="" checkout=false base="" name="" branch_repo="" agent=""
	run _parse_issue_develop_args number checkout base name branch_repo agent 42 --draft

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"use -- to pass flags to gh pr create"* ]]
}

# ---------------------------------------------------------------------------
# _gh_issue_develop_remotely: agent delegation helper
# ---------------------------------------------------------------------------

@test "_gh_issue_develop_remotely: invokes _cmd_assist_remotely with repo and rendered prompt" {
	local claude_log="$BATS_TEST_TMPDIR/claude.log"
	claude() { echo "$*" >"$claude_log"; }
	gh() { echo "owner/repo"; }
	gum() {
		case "$1" in
		spin)
			while [[ $# -gt 0 && "$1" != "--" ]]; do shift; done
			shift; "$@"
			;;
		log) ;;
		esac
	}
	export -f claude gh gum

	_gh_issue_develop_remotely @claude 42 "Fix the bug" "## Plan"

	grep -q -- "--remote" "$claude_log"
}

@test "_gh_issue_develop_remotely: passes issue number in spin title" {
	local gum_log="$BATS_TEST_TMPDIR/gum.log"
	claude() { :; }
	gh() { echo "owner/repo"; }
	gum() {
		case "$1" in
		spin)
			echo "$*" >>"$gum_log"
			while [[ $# -gt 0 && "$1" != "--" ]]; do shift; done
			shift; "$@"
			;;
		log) ;;
		esac
	}
	export -f claude gh gum

	_gh_issue_develop_remotely @claude 99 "Title" "Body"

	grep -q "99" "$gum_log"
}

# ---------------------------------------------------------------------------
# Helpers shared by integration tests
# ---------------------------------------------------------------------------

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
# _gh_issue_develop: checkout path
# ---------------------------------------------------------------------------

@test "_gh_issue_develop: checkout path calls gh issue develop with --checkout" {
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

@test "_gh_issue_develop: checkout path gh pr create does not include --head" {
	local gh_log="$BATS_TEST_TMPDIR/gh.log"
	local git_log="$BATS_TEST_TMPDIR/git.log"
	_setup_develop_mocks "$gh_log" "$git_log"

	_gh_issue_develop 42 -c

	! grep -qx -- "--head" "$gh_log"
}

@test "_gh_issue_develop: checkout path forwards --base to gh issue develop" {
	local gh_log="$BATS_TEST_TMPDIR/gh.log"
	local git_log="$BATS_TEST_TMPDIR/git.log"
	_setup_develop_mocks "$gh_log" "$git_log"

	_gh_issue_develop 42 -c -b main

	grep -qx -- "--checkout" "$gh_log"
	grep -qx -- "--base" "$gh_log"
	grep -qx "main" "$gh_log"
}

# ---------------------------------------------------------------------------
# _gh_issue_develop: no-checkout path
# ---------------------------------------------------------------------------

@test "_gh_issue_develop: no-checkout path does not call gh issue develop with --checkout" {
	local gh_log="$BATS_TEST_TMPDIR/gh.log"
	local git_log="$BATS_TEST_TMPDIR/git.log"
	_setup_develop_mocks "$gh_log" "$git_log"

	_gh_issue_develop 42

	grep -qx "develop" "$gh_log"
	! grep -qx -- "--checkout" "$gh_log"
}

@test "_gh_issue_develop: no-checkout path uses git commit-tree workflow" {
	local gh_log="$BATS_TEST_TMPDIR/gh.log"
	local git_log="$BATS_TEST_TMPDIR/git.log"
	_setup_develop_mocks "$gh_log" "$git_log"

	_gh_issue_develop 42

	grep -q "fetch origin 42-test-issue" "$git_log"
	grep -q "commit-tree" "$git_log"
	grep -q "push origin def456sha:refs/heads/42-test-issue" "$git_log"
}

@test "_gh_issue_develop: no-checkout path gh pr create includes --head" {
	local gh_log="$BATS_TEST_TMPDIR/gh.log"
	local git_log="$BATS_TEST_TMPDIR/git.log"
	_setup_develop_mocks "$gh_log" "$git_log"

	_gh_issue_develop 42

	grep -qx -- "--head" "$gh_log"
	grep -qx "42-test-issue" "$gh_log"
}

@test "_gh_issue_develop: no-checkout path does not call git commit --allow-empty" {
	local gh_log="$BATS_TEST_TMPDIR/gh.log"
	local git_log="$BATS_TEST_TMPDIR/git.log"
	_setup_develop_mocks "$gh_log" "$git_log"

	_gh_issue_develop 42

	! grep -q "commit --allow-empty" "$git_log"
	! grep -q "push -u origin HEAD" "$git_log"
}

@test "_gh_issue_develop: no-checkout path fails when gh issue develop returns empty" {
	local gh_log="$BATS_TEST_TMPDIR/gh.log"
	local git_log="$BATS_TEST_TMPDIR/git.log"
	_setup_develop_mocks "$gh_log" "$git_log"

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

@test "_gh_issue_develop: passthrough flags reach gh pr create" {
	local gh_log="$BATS_TEST_TMPDIR/gh.log"
	local git_log="$BATS_TEST_TMPDIR/git.log"
	_setup_develop_mocks "$gh_log" "$git_log"

	_gh_issue_develop 42 -- --draft --label enhancement

	grep -qx -- "--draft" "$gh_log"
	grep -qx -- "--label" "$gh_log"
	grep -qx "enhancement" "$gh_log"
}

# ---------------------------------------------------------------------------
# _gh_issue_develop: --agent delegation path
# ---------------------------------------------------------------------------

@test "_gh_issue_develop: --agent @claude invokes claude --remote and returns 0" {
	local gh_log="$BATS_TEST_TMPDIR/gh.log"
	local git_log="$BATS_TEST_TMPDIR/git.log"
	_setup_develop_mocks "$gh_log" "$git_log"

	local claude_log="$BATS_TEST_TMPDIR/claude.log"
	claude() { echo "$*" >"$claude_log"; }
	export -f claude

	run _gh_issue_develop 42 --agent @claude
	[[ "$status" -eq 0 ]]
	grep -q -- "--remote" "$claude_log"
}

@test "_gh_issue_develop: --agent path does not call gh issue develop" {
	local gh_log="$BATS_TEST_TMPDIR/gh.log"
	local git_log="$BATS_TEST_TMPDIR/git.log"
	_setup_develop_mocks "$gh_log" "$git_log"

	claude() { :; }
	export -f claude

	_gh_issue_develop 42 --agent @claude

	! grep -qx "develop" "$gh_log"
}

@test "_gh_issue_develop: --agent path does not create git branch or PR" {
	local gh_log="$BATS_TEST_TMPDIR/gh.log"
	local git_log="$BATS_TEST_TMPDIR/git.log"
	_setup_develop_mocks "$gh_log" "$git_log"

	jules() { :; }
	export -f jules

	_gh_issue_develop 42 --agent @jules

	! grep -q "commit-tree" "$git_log"
	! grep -q "pr create" "$gh_log"
}

@test "_gh_issue_develop: unknown --agent value returns error" {
	local gh_log="$BATS_TEST_TMPDIR/gh.log"
	local git_log="$BATS_TEST_TMPDIR/git.log"
	_setup_develop_mocks "$gh_log" "$git_log"

	run _gh_issue_develop 42 --agent @unknown-bot
	[[ "$status" -eq 1 ]]
}

@test "_gh_issue_develop: --agent value without @ prefix returns error" {
	local gh_log="$BATS_TEST_TMPDIR/gh.log"
	local git_log="$BATS_TEST_TMPDIR/git.log"
	_setup_develop_mocks "$gh_log" "$git_log"

	run _gh_issue_develop 42 --agent claude
	[[ "$status" -eq 1 ]]
}
