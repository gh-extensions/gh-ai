#!/usr/bin/env bats

# Unit tests for _resolve_chat_session in gh_cmd.sh
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_session.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _gh_ai_source_dir="$REPO_ROOT"
	export HOME="$BATS_TEST_TMPDIR"

	gum() { if [[ "$1" == "log" ]]; then shift; shift; shift; echo "$@"; fi; }
	git() {
		case "$1 $2" in
		"rev-parse --show-toplevel") echo "$BATS_TEST_TMPDIR" ;;
		"rev-parse --abbrev-ref") echo "" ;;
		esac
	}
	export -f gum git

	# shellcheck disable=SC2155
	eval "$(
		export _gh_ai_source_dir="$REPO_ROOT"
		# shellcheck source=../scripts/gh_cmd.sh
		source "$REPO_ROOT/scripts/gh_cmd.sh"
		declare -f _uuidv5 _git_repo_path _resolve_session_state _try_resume_chat_session _resolve_chat_session
	)"
}

# ---------------------------------------------------------------------------
# _try_resume_chat_session
# ---------------------------------------------------------------------------

@test "_try_resume_chat_session: returns 1 when no state file exists" {
	local args=()
	run _try_resume_chat_session args "https://github.com/owner/repo/issues/42" ""

	[[ "$status" -eq 1 ]]
}

@test "_try_resume_chat_session: returns 0 when state file exists" {
	# Create state file first via _resolve_chat_session
	local args=()
	_resolve_chat_session args "https://github.com/owner/repo/issues/42" "" "" ""

	local resume_args=()
	_try_resume_chat_session resume_args "https://github.com/owner/repo/issues/42" ""

	[[ ${#resume_args[@]} -eq 4 ]]
	[[ "${resume_args[0]}" == "--resume" ]]
	[[ "${resume_args[1]}" == "${args[1]}" ]]
	[[ "${resume_args[2]}" == "--worktree" ]]
	[[ "${resume_args[3]}" == "issue-42" ]]
}

@test "_try_resume_chat_session: returns 1 after --new-session deletes state file" {
	local args=()
	_resolve_chat_session args "https://github.com/owner/repo/issues/42" "" "" ""

	local resume_args=()
	if _try_resume_chat_session resume_args "https://github.com/owner/repo/issues/42" "1"; then
		return 1
	fi

	[[ ${#resume_args[@]} -eq 0 ]]
}

@test "_try_resume_chat_session: returns 1 when URL is empty" {
	local args=()
	if _try_resume_chat_session args "" ""; then
		return 1
	fi

	[[ ${#args[@]} -eq 0 ]]
}

@test "_try_resume_chat_session: returns 1 when user passes --resume in passthrough" {
	# Create state file first
	local args=()
	_resolve_chat_session args "https://github.com/owner/repo/issues/42" "" "" ""

	local resume_args=()
	if _try_resume_chat_session resume_args "https://github.com/owner/repo/issues/42" "" --resume "custom-id"; then
		return 1
	fi

	[[ ${#resume_args[@]} -eq 0 ]]
}

# ---------------------------------------------------------------------------
# _resolve_chat_session
# ---------------------------------------------------------------------------

@test "_resolve_chat_session: first call returns --session-id and --worktree" {
	local args=()
	_resolve_chat_session args "https://github.com/owner/repo/issues/42" "" "" ""

	[[ ${#args[@]} -eq 4 ]]
	[[ "${args[0]}" == "--session-id" ]]
	[[ -n "${args[1]}" ]]
	[[ "${args[2]}" == "--worktree" ]]
	[[ "${args[3]}" == "issue-42" ]]
}

@test "_resolve_chat_session: creates state file on first call" {
	local args=()
	_resolve_chat_session args "https://github.com/owner/repo/issues/42" "" "" ""

	local session_id="${args[1]}"
	local state_file="$BATS_TEST_TMPDIR/.claude/sessions/${session_id}/state.json"
	[[ -f "$state_file" ]]
}

@test "_resolve_chat_session: second call returns --resume with same session ID" {
	local args=()
	_resolve_chat_session args "https://github.com/owner/repo/issues/42" "" "" ""

	local first_id="${args[1]}"

	local args2=()
	_resolve_chat_session args2 "https://github.com/owner/repo/issues/42" "" "" ""

	[[ ${#args2[@]} -eq 4 ]]
	[[ "${args2[0]}" == "--resume" ]]
	[[ "${args2[1]}" == "$first_id" ]]
	[[ "${args2[2]}" == "--worktree" ]]
	[[ "${args2[3]}" == "issue-42" ]]
}

@test "_resolve_chat_session: --new-session deletes existing state and returns --session-id" {
	local args=()
	_resolve_chat_session args "https://github.com/owner/repo/issues/42" "" "" ""

	local args2=()
	_resolve_chat_session args2 "https://github.com/owner/repo/issues/42" "1" "" ""

	[[ ${#args2[@]} -eq 4 ]]
	[[ "${args2[0]}" == "--session-id" ]]
	[[ "${args2[2]}" == "--worktree" ]]
}

@test "_resolve_chat_session: skips when user passes --resume in passthrough" {
	local args=()
	_resolve_chat_session args "https://github.com/owner/repo/issues/42" "" "" "" --resume "some-uuid"

	[[ ${#args[@]} -eq 0 ]]
}

@test "_resolve_chat_session: skips when user passes --session-id in passthrough" {
	local args=()
	_resolve_chat_session args "https://github.com/owner/repo/issues/42" "" "" "" --session-id "some-uuid"

	[[ ${#args[@]} -eq 0 ]]
}

@test "_resolve_chat_session: skips when user passes --continue in passthrough" {
	local args=()
	_resolve_chat_session args "https://github.com/owner/repo/issues/42" "" "" "" --continue

	[[ ${#args[@]} -eq 0 ]]
}

@test "_resolve_chat_session: skips when user passes -c in passthrough" {
	local args=()
	_resolve_chat_session args "https://github.com/owner/repo/issues/42" "" "" "" -c

	[[ ${#args[@]} -eq 0 ]]
}

@test "_resolve_chat_session: skips silently when URL is empty" {
	local args=()
	_resolve_chat_session args "" "" "" ""

	[[ ${#args[@]} -eq 0 ]]
}

@test "_resolve_chat_session: all resource types use sessions/ directory" {
	local args_issue=() args_pr=() args_run=()
	_resolve_chat_session args_issue "https://github.com/owner/repo/issues/42" "" "" ""
	_resolve_chat_session args_pr "https://github.com/owner/repo/pull/7" "" "" ""
	_resolve_chat_session args_run "https://github.com/owner/repo/actions/runs/123456" "" "" ""

	local sessions_dir="$BATS_TEST_TMPDIR/.claude/sessions"
	[[ -f "$sessions_dir/${args_issue[1]}/state.json" ]]
	[[ -f "$sessions_dir/${args_pr[1]}/state.json" ]]
	[[ -f "$sessions_dir/${args_run[1]}/state.json" ]]
}

@test "_resolve_chat_session: state file contains valid session_id and name" {
	local args=()
	_resolve_chat_session args "https://github.com/owner/repo/issues/42" "" "" ""

	local state_file="$BATS_TEST_TMPDIR/.claude/sessions/${args[1]}/state.json"
	local content
	content=$(cat "$state_file")

	[[ "$content" == *'"session_id"'* ]]
	[[ "$content" == *'"name"'* ]]
	[[ "$content" == *"issue-42"* ]]
}

@test "_resolve_chat_session: derives worktree name from URL segments" {
	local args=()

	_resolve_chat_session args "https://github.com/owner/repo/issues/42" "" "" ""
	[[ "${args[3]}" == "issue-42" ]]

	args=()
	_resolve_chat_session args "https://github.com/owner/repo/pull/7" "" "" ""
	[[ "${args[3]}" == "pull-7" ]]

	args=()
	_resolve_chat_session args "https://github.com/owner/repo/actions/runs/123456" "" "" ""
	[[ "${args[3]}" == "run-123456" ]]
}

@test "_resolve_chat_session: state file contains remote_ref when provided" {
	local args=()
	_resolve_chat_session args "https://github.com/owner/repo/pull/7" "" "feat-my-branch" ""

	local state_file="$BATS_TEST_TMPDIR/.claude/sessions/${args[1]}/state.json"
	local content
	content=$(cat "$state_file")

	[[ "$content" == *'"remote_ref": "feat-my-branch"'* ]]
}

@test "_resolve_chat_session: state file contains default remote_ref when not provided" {
	git() {
		case "$1 $2" in
		"rev-parse --show-toplevel") echo "$BATS_TEST_TMPDIR" ;;
		"rev-parse --abbrev-ref") echo "origin/develop" ;;
		esac
	}
	export -f git

	local args=()
	_resolve_chat_session args "https://github.com/owner/repo/issues/42" "" "" ""

	local state_file="$BATS_TEST_TMPDIR/.claude/sessions/${args[1]}/state.json"
	local content
	content=$(cat "$state_file")

	[[ "$content" == *'"remote_ref": "develop"'* ]]
}

@test "_resolve_chat_session: remote_ref defaults to main when git rev-parse fails" {
	git() {
		case "$1 $2" in
		"rev-parse --show-toplevel") echo "$BATS_TEST_TMPDIR" ;;
		"rev-parse --abbrev-ref") return 1 ;;
		esac
	}
	export -f git

	local args=()
	_resolve_chat_session args "https://github.com/owner/repo/issues/42" "" "" ""

	local state_file="$BATS_TEST_TMPDIR/.claude/sessions/${args[1]}/state.json"
	local content
	content=$(cat "$state_file")

	[[ "$content" == *'"remote_ref": "main"'* ]]
}
