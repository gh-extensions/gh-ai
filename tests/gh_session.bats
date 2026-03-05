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
		"rev-parse --git-common-dir") echo "$BATS_TEST_TMPDIR/.git" ;;
		esac
	}
	export -f gum git

	# shellcheck disable=SC2155
	eval "$(
		export _gh_ai_source_dir="$REPO_ROOT"
		# shellcheck source=../scripts/gh_cmd.sh
		source "$REPO_ROOT/scripts/gh_cmd.sh"
		declare -f _git_repo_path _resolve_chat_session _gh_session_base_dir
	)"
}

# ---------------------------------------------------------------------------
# _resolve_chat_session
# ---------------------------------------------------------------------------

@test "_resolve_chat_session: first call returns --session-id and a UUID" {
	local session_dir="$BATS_TEST_TMPDIR/sessions/test-1"
	mkdir -p "$session_dir"

	local is_new="" args=()
	_resolve_chat_session "$session_dir" "" is_new args

	[[ "$is_new" == "1" ]]
	[[ ${#args[@]} -eq 2 ]]
	[[ "${args[0]}" == "--session-id" ]]
	[[ -n "${args[1]}" ]]
}

@test "_resolve_chat_session: creates session.id file on first call" {
	local session_dir="$BATS_TEST_TMPDIR/sessions/test-2"
	mkdir -p "$session_dir"

	local is_new="" args=()
	_resolve_chat_session "$session_dir" "" is_new args

	[[ -f "$session_dir/session.id" ]]
}

@test "_resolve_chat_session: session.id contains the returned UUID" {
	local session_dir="$BATS_TEST_TMPDIR/sessions/test-3"
	mkdir -p "$session_dir"

	local is_new="" args=()
	_resolve_chat_session "$session_dir" "" is_new args

	local stored
	stored=$(<"$session_dir/session.id")
	[[ "$stored" == "${args[1]}" ]]
}

@test "_resolve_chat_session: second call returns --resume with same UUID" {
	local session_dir="$BATS_TEST_TMPDIR/sessions/test-4"
	mkdir -p "$session_dir"

	local is_new1="" args1=()
	_resolve_chat_session "$session_dir" "" is_new1 args1
	local first_uuid="${args1[1]}"

	local is_new2="" args2=()
	_resolve_chat_session "$session_dir" "" is_new2 args2

	[[ -z "$is_new2" ]]
	[[ ${#args2[@]} -eq 2 ]]
	[[ "${args2[0]}" == "--resume" ]]
	[[ "${args2[1]}" == "$first_uuid" ]]
}

@test "_resolve_chat_session: --new-session deletes session file and returns --session-id" {
	local session_dir="$BATS_TEST_TMPDIR/sessions/test-5"
	mkdir -p "$session_dir"

	# First call to establish a session
	local is_new1="" args1=()
	_resolve_chat_session "$session_dir" "" is_new1 args1
	local first_uuid="${args1[1]}"

	# Second call with new_session=1 should create a fresh session
	local is_new2="" args2=()
	_resolve_chat_session "$session_dir" "1" is_new2 args2

	[[ "$is_new2" == "1" ]]
	[[ "${args2[0]}" == "--session-id" ]]
	# UUID should be different (or at least the flag is --session-id, not --resume)
	[[ "${args2[0]}" != "--resume" ]]
}

@test "_resolve_chat_session: --new-session removes the old session.id" {
	local session_dir="$BATS_TEST_TMPDIR/sessions/test-6"
	mkdir -p "$session_dir"
	printf 'old-uuid-12345' >"$session_dir/session.id"

	local is_new="" args=()
	_resolve_chat_session "$session_dir" "1" is_new args

	local stored
	stored=$(<"$session_dir/session.id")
	[[ "$stored" != "old-uuid-12345" ]]
}

@test "_resolve_chat_session: is_new is empty on resumed session" {
	local session_dir="$BATS_TEST_TMPDIR/sessions/test-7"
	mkdir -p "$session_dir"
	printf 'existing-uuid' >"$session_dir/session.id"

	local is_new="initial" args=()
	_resolve_chat_session "$session_dir" "" is_new args

	[[ -z "$is_new" ]]
}

@test "_resolve_chat_session: UUID is lowercase" {
	local session_dir="$BATS_TEST_TMPDIR/sessions/test-8"
	mkdir -p "$session_dir"

	local is_new="" args=()
	_resolve_chat_session "$session_dir" "" is_new args

	# UUID should be lowercase (no uppercase letters)
	[[ "${args[1]}" =~ ^[0-9a-f-]+$ ]]
}

@test "_resolve_chat_session: separate session dirs are independent" {
	local dir1="$BATS_TEST_TMPDIR/sessions/pull-42"
	local dir2="$BATS_TEST_TMPDIR/sessions/issue-7"
	mkdir -p "$dir1" "$dir2"

	local is1="" args1=() is2="" args2=()
	_resolve_chat_session "$dir1" "" is1 args1
	_resolve_chat_session "$dir2" "" is2 args2

	# Both are new sessions
	[[ "$is1" == "1" ]]
	[[ "$is2" == "1" ]]
	# UUIDs differ
	[[ "${args1[1]}" != "${args2[1]}" ]]
}

# ---------------------------------------------------------------------------
# _gh_session_base_dir
# ---------------------------------------------------------------------------

@test "_gh_session_base_dir: default path is .github/sessions under git root" {
	gh() { return 1; }
	export -f gh
	unset GH_SESSION_DIR

	local result
	result=$(_gh_session_base_dir "$BATS_TEST_TMPDIR")

	[[ "$result" == "$BATS_TEST_TMPDIR/.github/sessions" ]]
}

@test "_gh_session_base_dir: ai.session.dir gh config (relative) is anchored to git root" {
	gh() {
		if [[ "$1 $2 $3" == "config get ai.session.dir" ]]; then
			echo "custom/sessions"
			return 0
		fi
		return 1
	}
	export -f gh
	unset GH_SESSION_DIR

	local result
	result=$(_gh_session_base_dir "$BATS_TEST_TMPDIR")

	[[ "$result" == "$BATS_TEST_TMPDIR/custom/sessions" ]]
}

@test "_gh_session_base_dir: ai.session.dir gh config (absolute) is used as-is" {
	gh() {
		if [[ "$1 $2 $3" == "config get ai.session.dir" ]]; then
			echo "/abs/path/sessions"
			return 0
		fi
		return 1
	}
	export -f gh
	unset GH_SESSION_DIR

	local result
	result=$(_gh_session_base_dir "$BATS_TEST_TMPDIR")

	[[ "$result" == "/abs/path/sessions" ]]
}

@test "_gh_session_base_dir: GH_SESSION_DIR env var takes highest priority" {
	gh() {
		if [[ "$1 $2 $3" == "config get ai.session.dir" ]]; then
			echo "should-not-be-used"
			return 0
		fi
		return 1
	}
	export -f gh
	export GH_SESSION_DIR="/env/override/sessions"

	local result
	result=$(_gh_session_base_dir "$BATS_TEST_TMPDIR")

	[[ "$result" == "/env/override/sessions" ]]
	unset GH_SESSION_DIR
}

@test "_gh_session_base_dir: GH_SESSION_DIR overrides default when config absent" {
	gh() { return 1; }
	export -f gh
	export GH_SESSION_DIR="/tmp/my-sessions"

	local result
	result=$(_gh_session_base_dir "$BATS_TEST_TMPDIR")

	[[ "$result" == "/tmp/my-sessions" ]]
	unset GH_SESSION_DIR
}
