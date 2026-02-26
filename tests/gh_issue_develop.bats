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
		# shellcheck source=../scripts/gh_cmd.sh
		source "$REPO_ROOT/scripts/gh_cmd.sh"
		declare -f _parse_issue_develop_args _show_issue_develop_help _gh_issue_develop _get_title _get_body
	)"
}

# ---------------------------------------------------------------------------
# T002: Issue number captured from positional arg
# ---------------------------------------------------------------------------

@test "T002: issue number captured as first numeric arg" {
	local number=""
	local issue_args=()
	local pr_args=()
	local checkout=false
	_parse_issue_develop_args number issue_args pr_args checkout 42

	[[ "$number" == "42" ]]
	[[ ${#issue_args[@]} -eq 0 ]]
	[[ ${#pr_args[@]} -eq 0 ]]
}

@test "T002: issue number does not bleed into passthrough args" {
	local number=""
	local issue_args=()
	local pr_args=()
	local checkout=false
	_parse_issue_develop_args number issue_args pr_args checkout 42 --draft

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
	local checkout=false
	_parse_issue_develop_args number issue_args pr_args checkout 42 --base develop

	[[ "${issue_args[0]}" == "--base" ]]
	[[ "${issue_args[1]}" == "develop" ]]
	[[ ${#pr_args[@]} -eq 0 ]]
}

@test "T003: -b flag goes to issue args" {
	local number=""
	local issue_args=()
	local pr_args=()
	local checkout=false
	_parse_issue_develop_args number issue_args pr_args checkout 42 -b develop

	[[ "${issue_args[0]}" == "-b" ]]
	[[ "${issue_args[1]}" == "develop" ]]
	[[ ${#pr_args[@]} -eq 0 ]]
}

@test "T003: --base=value goes to issue args" {
	local number=""
	local issue_args=()
	local pr_args=()
	local checkout=false
	_parse_issue_develop_args number issue_args pr_args checkout 42 --base=develop

	[[ "${issue_args[0]}" == "--base=develop" ]]
	[[ ${#pr_args[@]} -eq 0 ]]
}

@test "T003: --name flag goes to issue args" {
	local number=""
	local issue_args=()
	local pr_args=()
	local checkout=false
	_parse_issue_develop_args number issue_args pr_args checkout 42 --name my-branch

	[[ "${issue_args[0]}" == "--name" ]]
	[[ "${issue_args[1]}" == "my-branch" ]]
	[[ ${#pr_args[@]} -eq 0 ]]
}

@test "T003: -n flag goes to issue args" {
	local number=""
	local issue_args=()
	local pr_args=()
	local checkout=false
	_parse_issue_develop_args number issue_args pr_args checkout 42 -n my-branch

	[[ "${issue_args[0]}" == "-n" ]]
	[[ "${issue_args[1]}" == "my-branch" ]]
	[[ ${#pr_args[@]} -eq 0 ]]
}

@test "T003: --branch-repo flag goes to issue args" {
	local number=""
	local issue_args=()
	local pr_args=()
	local checkout=false
	_parse_issue_develop_args number issue_args pr_args checkout 42 --branch-repo owner/repo

	[[ "${issue_args[0]}" == "--branch-repo" ]]
	[[ "${issue_args[1]}" == "owner/repo" ]]
	[[ ${#pr_args[@]} -eq 0 ]]
}

# ---------------------------------------------------------------------------
# T004: Develop-only flags handled (not passed to gh pr create)
# ---------------------------------------------------------------------------

@test "T004: --checkout sets checkout=true" {
	local number=""
	local issue_args=()
	local pr_args=()
	local checkout=false
	_parse_issue_develop_args number issue_args pr_args checkout 42 --checkout --draft

	[[ "$checkout" == "true" ]]
	[[ ${#issue_args[@]} -eq 0 ]]
	[[ "${pr_args[0]}" == "--draft" ]]
}

@test "T004: -c sets checkout=true" {
	local number=""
	local issue_args=()
	local pr_args=()
	local checkout=false
	_parse_issue_develop_args number issue_args pr_args checkout 42 -c --draft

	[[ "$checkout" == "true" ]]
	[[ ${#issue_args[@]} -eq 0 ]]
	[[ "${pr_args[0]}" == "--draft" ]]
}

@test "T004: --head flag is stripped" {
	local number=""
	local issue_args=()
	local pr_args=()
	local checkout=false
	_parse_issue_develop_args number issue_args pr_args checkout 42 --head my-branch --draft

	[[ ${#issue_args[@]} -eq 0 ]]
	[[ "${pr_args[0]}" == "--draft" ]]
}

@test "T004: -H flag is stripped" {
	local number=""
	local issue_args=()
	local pr_args=()
	local checkout=false
	_parse_issue_develop_args number issue_args pr_args checkout 42 -H my-branch --draft

	[[ ${#issue_args[@]} -eq 0 ]]
	[[ "${pr_args[0]}" == "--draft" ]]
}

@test "T004: -B flag is stripped" {
	local number=""
	local issue_args=()
	local pr_args=()
	local checkout=false
	_parse_issue_develop_args number issue_args pr_args checkout 42 -B main --draft

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
	local checkout=false
	_parse_issue_develop_args number issue_args pr_args checkout 42 -t "ignored" --draft

	[[ ${#issue_args[@]} -eq 0 ]]
	[[ "${pr_args[0]}" == "--draft" ]]
}

@test "T005: --title flag is stripped" {
	local number=""
	local issue_args=()
	local pr_args=()
	local checkout=false
	_parse_issue_develop_args number issue_args pr_args checkout 42 --title "ignored" --draft

	[[ ${#issue_args[@]} -eq 0 ]]
	[[ "${pr_args[0]}" == "--draft" ]]
}

@test "T005: --body flag is stripped" {
	local number=""
	local issue_args=()
	local pr_args=()
	local checkout=false
	_parse_issue_develop_args number issue_args pr_args checkout 42 --body "ignored" --draft

	[[ ${#issue_args[@]} -eq 0 ]]
	[[ "${pr_args[0]}" == "--draft" ]]
}

@test "T005: -F flag is stripped" {
	local number=""
	local issue_args=()
	local pr_args=()
	local checkout=false
	_parse_issue_develop_args number issue_args pr_args checkout 42 -F body.md --draft

	[[ ${#issue_args[@]} -eq 0 ]]
	[[ "${pr_args[0]}" == "--draft" ]]
}

@test "T005: --body-file flag is stripped" {
	local number=""
	local issue_args=()
	local pr_args=()
	local checkout=false
	_parse_issue_develop_args number issue_args pr_args checkout 42 --body-file body.md --draft

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
	local checkout=false
	_parse_issue_develop_args number issue_args pr_args checkout 42 --draft --label enhancement

	[[ ${#issue_args[@]} -eq 0 ]]
	[[ "${pr_args[0]}" == "--draft" ]]
	[[ "${pr_args[1]}" == "--label" ]]
	[[ "${pr_args[2]}" == "enhancement" ]]
}

@test "T006: issue and PR flags are correctly separated" {
	local number=""
	local issue_args=()
	local pr_args=()
	local checkout=false
	_parse_issue_develop_args number issue_args pr_args checkout 42 --base develop --draft --label bug

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

# ---------------------------------------------------------------------------
# Helpers shared by T009/T010 integration tests
# ---------------------------------------------------------------------------

# _setup_develop_mocks sets up gh/git/gum mocks that record calls to temp
# files and return appropriate fake values for the develop workflow.
#
# Usage: _setup_develop_mocks <gh_log_var> <git_log_var>
_setup_develop_mocks() {
	local gh_log="$1"
	local git_log="$2"

	gh() {
		# Write each argument on its own line so multiline body args don't
		# break grep assertions.
		printf '%s\n' "$@" >>"$gh_log"
		case "$1 $2" in
		"issue view") echo '{"title":"Test Issue","body":"Issue body","labels":[],"comments":[]}';;
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
	local gh_log git_log
	gh_log=$(mktemp)
	git_log=$(mktemp)
	_setup_develop_mocks "$gh_log" "$git_log"

	_gh_issue_develop 42 --checkout

	# gh mock writes one arg per line; verify "develop" and "--checkout" present
	grep -qx "develop" "$gh_log"
	grep -qx -- "--checkout" "$gh_log"
	grep -q "commit --allow-empty" "$git_log"
	grep -q "push -u origin HEAD" "$git_log"
	! grep -q "commit-tree" "$git_log"

	rm -f "$gh_log" "$git_log"
}

@test "T009: checkout path gh pr create does not include --head" {
	local gh_log git_log
	gh_log=$(mktemp)
	git_log=$(mktemp)
	_setup_develop_mocks "$gh_log" "$git_log"

	_gh_issue_develop 42 --checkout

	# --head argument should not appear anywhere in the gh calls
	! grep -qx -- "--head" "$gh_log"

	rm -f "$gh_log" "$git_log"
}

# ---------------------------------------------------------------------------
# T010: no-checkout path — _gh_issue_develop without --checkout
# ---------------------------------------------------------------------------

@test "T010: no-checkout path does not call gh issue develop with --checkout" {
	local gh_log git_log
	gh_log=$(mktemp)
	git_log=$(mktemp)
	_setup_develop_mocks "$gh_log" "$git_log"

	_gh_issue_develop 42

	# gh issue develop was called (develop arg present) but --checkout was not
	grep -qx "develop" "$gh_log"
	! grep -qx -- "--checkout" "$gh_log"

	rm -f "$gh_log" "$git_log"
}

@test "T010: no-checkout path uses git commit-tree workflow" {
	local gh_log git_log
	gh_log=$(mktemp)
	git_log=$(mktemp)
	_setup_develop_mocks "$gh_log" "$git_log"

	_gh_issue_develop 42

	grep -q "fetch origin 42-test-issue" "$git_log"
	grep -q "commit-tree" "$git_log"
	grep -q "push origin def456sha:refs/heads/42-test-issue" "$git_log"

	rm -f "$gh_log" "$git_log"
}

@test "T010: no-checkout path gh pr create includes --head" {
	local gh_log git_log
	gh_log=$(mktemp)
	git_log=$(mktemp)
	_setup_develop_mocks "$gh_log" "$git_log"

	_gh_issue_develop 42

	# --head and its value appear as separate lines (one arg per line in mock)
	grep -qx -- "--head" "$gh_log"
	grep -qx "42-test-issue" "$gh_log"

	rm -f "$gh_log" "$git_log"
}

@test "T010: no-checkout path does not call git commit --allow-empty" {
	local gh_log git_log
	gh_log=$(mktemp)
	git_log=$(mktemp)
	_setup_develop_mocks "$gh_log" "$git_log"

	_gh_issue_develop 42

	! grep -q "commit --allow-empty" "$git_log"
	! grep -q "push -u origin HEAD" "$git_log"

	rm -f "$gh_log" "$git_log"
}
