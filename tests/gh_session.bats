#!/usr/bin/env bats

# Unit tests for session management functions in gh_cmd.sh
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_session.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _gh_claude_source_dir="$REPO_ROOT"
	export HOME="$BATS_TEST_TMPDIR"
	unset XDG_STATE_HOME

	gum() { if [[ "$1" == "log" ]]; then shift; shift; shift; echo "$@"; fi; }
	git() {
		case "$1 $2" in
		"rev-parse --show-toplevel") echo "$BATS_TEST_TMPDIR" ;;
		"rev-parse --abbrev-ref") echo "" ;;
		"rev-parse --git-common-dir") echo "$BATS_TEST_TMPDIR/.git" ;;
		esac
	}
	export -f gum git

	# shellcheck disable=SC2155
	eval "$(
		export _gh_claude_source_dir="$REPO_ROOT"
		# shellcheck source=../scripts/gh_cmd.sh
		source "$REPO_ROOT/scripts/gh_cmd.sh"
		declare -f _git_repo_path _resolve_chat_session _gh_session_base_dir \
			_extract_chat_passthrough _resolve_context_dir _create_context_dir
	)"
}

# ---------------------------------------------------------------------------
# _gh_session_base_dir
# ---------------------------------------------------------------------------

@test "_gh_session_base_dir: returns XDG-based path (no arg)" {
	local result
	result=$(_gh_session_base_dir)

	[[ "$result" == "$HOME/.local/state/gh/claude/sessions" ]]
}

@test "_gh_session_base_dir: respects XDG_STATE_HOME when set" {
	local result
	XDG_STATE_HOME="$BATS_TEST_TMPDIR/xdg" result=$(_gh_session_base_dir)

	[[ "$result" == "$BATS_TEST_TMPDIR/xdg/gh/claude/sessions" ]]
}

# ---------------------------------------------------------------------------
# _resolve_chat_session: auto-generate
# ---------------------------------------------------------------------------

@test "_resolve_chat_session: auto-generate returns --session-id and UUID" {
	local dir="" is_new="" args=()
	_resolve_chat_session "pull-42" "" "" dir is_new args

	[[ "$is_new" == "1" ]]
	[[ "${args[0]}" == "--session-id" ]]
	[[ -n "${args[1]}" ]]
}

@test "_resolve_chat_session: creates session dir with chat.id" {
	local dir="" is_new="" args=()
	_resolve_chat_session "pull-42" "" "" dir is_new args

	[[ -f "$dir/chat.id" ]]
}

@test "_resolve_chat_session: chat.id contains resource name" {
	local dir="" is_new="" args=()
	_resolve_chat_session "pull-42" "" "" dir is_new args

	local stored
	stored=$(<"$dir/chat.id")
	[[ "$stored" == "pull-42" ]]
}

@test "_resolve_chat_session: UUID is lowercase" {
	local dir="" is_new="" args=()
	_resolve_chat_session "issue-7" "" "" dir is_new args

	[[ "${args[1]}" =~ ^[0-9a-f-]+$ ]]
}

@test "_resolve_chat_session: separate calls get different UUIDs" {
	local dir1="" is_new1="" args1=()
	local dir2="" is_new2="" args2=()
	_resolve_chat_session "pull-1" "" "" dir1 is_new1 args1
	_resolve_chat_session "pull-2" "" "" dir2 is_new2 args2

	[[ "${args1[1]}" != "${args2[1]}" ]]
}

# ---------------------------------------------------------------------------
# _resolve_chat_session: user --session-id
# ---------------------------------------------------------------------------

@test "_resolve_chat_session: user --session-id creates dir and is_new=1 when absent" {
	local dir="" is_new="" args=()
	_resolve_chat_session "issue-5" "my-session" "" dir is_new args

	[[ "$is_new" == "1" ]]
	[[ ${#args[@]} -eq 0 ]]
	[[ "$dir" == *"/my-session" ]]
	[[ -d "$dir" ]]
}

@test "_resolve_chat_session: user --session-id writes chat.id when dir absent" {
	local dir="" is_new="" args=()
	_resolve_chat_session "issue-5" "my-session" "" dir is_new args

	local stored
	stored=$(<"$dir/chat.id")
	[[ "$stored" == "issue-5" ]]
}

@test "_resolve_chat_session: user --session-id is_new empty when dir already exists" {
	local base
	base=$(_gh_session_base_dir)
	mkdir -p "$base/existing-session"
	printf 'issue-5' >"$base/existing-session/chat.id"

	local dir="" is_new="initial" args=()
	_resolve_chat_session "issue-5" "existing-session" "" dir is_new args

	[[ -z "$is_new" ]]
	[[ ${#args[@]} -eq 0 ]]
}

# ---------------------------------------------------------------------------
# _resolve_chat_session: user --resume
# ---------------------------------------------------------------------------

@test "_resolve_chat_session: user --resume errors when session not found" {
	run _resolve_chat_session "pull-42" "" "no-such-uuid" dir is_new args

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"Session not found"* ]]
}

@test "_resolve_chat_session: user --resume errors when chat.id does not match" {
	local base
	base=$(_gh_session_base_dir)
	mkdir -p "$base/abc123"
	printf 'issue-7' >"$base/abc123/chat.id"

	run _resolve_chat_session "pull-42" "" "abc123" dir is_new args

	[[ "$status" -eq 1 ]]
	[[ "$output" == *"belongs to"* ]]
}

@test "_resolve_chat_session: user --resume sets is_new to empty and returns empty args" {
	local base
	base=$(_gh_session_base_dir)
	mkdir -p "$base/abc123"
	printf 'pull-42' >"$base/abc123/chat.id"

	local dir="" is_new="initial" args=()
	_resolve_chat_session "pull-42" "" "abc123" dir is_new args

	[[ -z "$is_new" ]]
	[[ ${#args[@]} -eq 0 ]]
}

@test "_resolve_chat_session: user --resume sets dir path" {
	local base
	base=$(_gh_session_base_dir)
	mkdir -p "$base/abc123"
	printf 'pull-42' >"$base/abc123/chat.id"

	local dir="" is_new="" args=()
	_resolve_chat_session "pull-42" "" "abc123" dir is_new args

	[[ "$dir" == *"/abc123" ]]
}

# ---------------------------------------------------------------------------
# _extract_chat_passthrough
# ---------------------------------------------------------------------------

@test "_extract_chat_passthrough: extracts --session-id value" {
	local pt=(--session-id my-session --verbose)
	local sid="" resume=""
	_extract_chat_passthrough pt sid resume

	[[ "$sid" == "my-session" ]]
}

@test "_extract_chat_passthrough: extracts --resume value" {
	local pt=(--resume abc123 --verbose)
	local sid="" resume=""
	_extract_chat_passthrough pt sid resume

	[[ "$resume" == "abc123" ]]
}

@test "_extract_chat_passthrough: leaves refs empty when flags absent" {
	local pt=(--model sonnet --verbose)
	local sid="" resume=""
	_extract_chat_passthrough pt sid resume

	[[ -z "$sid" ]]
	[[ -z "$resume" ]]
}

# ---------------------------------------------------------------------------
# _resolve_chat_session: GH_CLAUDE_DEFAULT_SESSION_ID
# ---------------------------------------------------------------------------

@test "_resolve_chat_session: GH_CLAUDE_DEFAULT_SESSION_ID creates dir and is_new=1 when absent" {
	local dir="" is_new="" args=()
	GH_CLAUDE_DEFAULT_SESSION_ID="my-default" _resolve_chat_session "pull-42" "" "" dir is_new args

	[[ "$is_new" == "1" ]]
	[[ "$dir" == *"/my-default" ]]
	[[ -d "$dir" ]]
}

@test "_resolve_chat_session: GH_CLAUDE_DEFAULT_SESSION_ID writes chat.id when dir absent" {
	local dir="" is_new="" args=()
	GH_CLAUDE_DEFAULT_SESSION_ID="my-default" _resolve_chat_session "pull-42" "" "" dir is_new args

	local stored
	stored=$(<"$dir/chat.id")
	[[ "$stored" == "pull-42" ]]
}

@test "_resolve_chat_session: GH_CLAUDE_DEFAULT_SESSION_ID returns --session-id when dir absent" {
	local dir="" is_new="" args=()
	GH_CLAUDE_DEFAULT_SESSION_ID="my-default" _resolve_chat_session "pull-42" "" "" dir is_new args

	[[ "${args[0]}" == "--session-id" ]]
	[[ "${args[1]}" == "my-default" ]]
}

@test "_resolve_chat_session: GH_CLAUDE_DEFAULT_SESSION_ID auto-resumes when dir exists" {
	local base
	base=$(_gh_session_base_dir)
	mkdir -p "$base/my-default"
	printf 'pull-42' >"$base/my-default/chat.id"

	local dir="" is_new="initial" args=()
	GH_CLAUDE_DEFAULT_SESSION_ID="my-default" _resolve_chat_session "pull-42" "" "" dir is_new args

	[[ -z "$is_new" ]]
	[[ "${args[0]}" == "--resume" ]]
	[[ "${args[1]}" == "my-default" ]]
}

@test "_resolve_chat_session: GH_CLAUDE_DEFAULT_SESSION_ID ignored when --session-id in passthrough" {
	local dir="" is_new="" args=()
	GH_CLAUDE_DEFAULT_SESSION_ID="my-default" _resolve_chat_session "pull-42" "explicit-session" "" dir is_new args

	[[ "$dir" == *"/explicit-session" ]]
}

@test "_resolve_chat_session: GH_CLAUDE_DEFAULT_SESSION_ID ignored when --resume in passthrough" {
	local base
	base=$(_gh_session_base_dir)
	mkdir -p "$base/explicit-resume"
	printf 'pull-42' >"$base/explicit-resume/chat.id"

	local dir="" is_new="" args=()
	GH_CLAUDE_DEFAULT_SESSION_ID="my-default" _resolve_chat_session "pull-42" "" "explicit-resume" dir is_new args

	[[ "$dir" == *"/explicit-resume" ]]
}

# ---------------------------------------------------------------------------
# _resolve_context_dir
# ---------------------------------------------------------------------------

@test "_resolve_context_dir: uses pre-set dir when non-empty" {
	local dir="already/set"
	_resolve_context_dir "chat" "pull-42" dir

	[[ "$dir" == "already/set" ]]
}
