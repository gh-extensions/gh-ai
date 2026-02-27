#!/usr/bin/env bats

# Unit tests for _split_on_separator in gh_cmd.sh
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_cmd.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _gh_ai_source_dir="$REPO_ROOT"

	gum() { if [[ "$1" == "log" ]]; then shift; shift; shift; echo "$@"; fi; }
	gh() { echo ""; }
	git() { echo ""; }
	uuid() { echo "aaaabbbb-1234-5678-abcd-ef0123456789"; }
	claude() { :; }
	export -f gum gh git uuid claude

	# shellcheck disable=SC2155
	eval "$(
		export _gh_ai_source_dir="$REPO_ROOT"
		# shellcheck source=../scripts/gh_cmd.sh
		source "$REPO_ROOT/scripts/gh_cmd.sh"
		declare -f _split_on_separator \
			_get_repo_name _get_git_repo_path _init_claude_session \
			_git_worktree_sync _cmd_chat
	)"
}

@test "_split_on_separator: places all args in before when no -- present" {
	local before=()
	local after=()
	_split_on_separator before after -d "desc" --flag

	[[ ${#before[@]} -eq 3 ]]
	[[ "${before[0]}" == "-d" ]]
	[[ "${before[1]}" == "desc" ]]
	[[ "${before[2]}" == "--flag" ]]
	[[ ${#after[@]} -eq 0 ]]
}

@test "_split_on_separator: splits args into before and after on --" {
	local before=()
	local after=()
	_split_on_separator before after -d "desc" -- --signoff --no-verify

	[[ ${#before[@]} -eq 2 ]]
	[[ "${before[0]}" == "-d" ]]
	[[ "${before[1]}" == "desc" ]]
	[[ ${#after[@]} -eq 2 ]]
	[[ "${after[0]}" == "--signoff" ]]
	[[ "${after[1]}" == "--no-verify" ]]
}

@test "_split_on_separator: handles empty before when -- is first arg" {
	local before=()
	local after=()
	_split_on_separator before after -- --signoff

	[[ ${#before[@]} -eq 0 ]]
	[[ ${#after[@]} -eq 1 ]]
	[[ "${after[0]}" == "--signoff" ]]
}

@test "_split_on_separator: handles empty after when -- is last arg" {
	local before=()
	local after=()
	_split_on_separator before after -d "desc" --

	[[ ${#before[@]} -eq 2 ]]
	[[ ${#after[@]} -eq 0 ]]
}

@test "_split_on_separator: returns two empty arrays for no arguments" {
	local before=()
	local after=()
	_split_on_separator before after

	[[ ${#before[@]} -eq 0 ]]
	[[ ${#after[@]} -eq 0 ]]
}

@test "_split_on_separator: passes second -- through as passthrough arg" {
	local before=()
	local after=()
	_split_on_separator before after -d "desc" -- --signoff -- --extra

	[[ ${#before[@]} -eq 2 ]]
	[[ ${#after[@]} -eq 3 ]]
	[[ "${after[0]}" == "--signoff" ]]
	[[ "${after[1]}" == "--" ]]
	[[ "${after[2]}" == "--extra" ]]
}

@test "_split_on_separator: preserves special characters across the split" {
	local before=()
	local after=()
	_split_on_separator before after -d 'fix: handle $HOME & "quotes"' -- --message='hello world'

	[[ "${before[1]}" == 'fix: handle $HOME & "quotes"' ]]
	[[ "${after[0]}" == "--message=hello world" ]]
}

@test "_split_on_separator: returns two empty arrays when only -- given" {
	local before=()
	local after=()
	_split_on_separator before after --

	[[ ${#before[@]} -eq 0 ]]
	[[ ${#after[@]} -eq 0 ]]
}

# ---------------------------------------------------------------------------
# _get_repo_name
# ---------------------------------------------------------------------------

@test "_get_repo_name: sets nameref when gh repo view succeeds" {
	gh() { echo "owner/repo"; }
	export -f gh

	local repo=""
	_get_repo_name repo

	[[ "$repo" == "owner/repo" ]]
}

@test "_get_repo_name: returns error when gh repo view returns empty" {
	gh() { :; }
	export -f gh

	local repo=""
	run _get_repo_name repo

	[[ "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# _get_git_repo_path
# ---------------------------------------------------------------------------

@test "_get_git_repo_path: sets nameref when git rev-parse succeeds" {
	git() { echo "/home/user/myrepo"; }
	export -f git

	local dir=""
	_get_git_repo_path dir

	[[ "$dir" == "/home/user/myrepo" ]]
}

@test "_get_git_repo_path: returns error when git rev-parse returns empty" {
	git() { :; }
	export -f git

	local dir=""
	run _get_git_repo_path dir

	[[ "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# _init_claude_session
# ---------------------------------------------------------------------------

@test "_init_claude_session: populates session ID and file path" {
	uuid() { echo "deadbeef-dead-beef-dead-beefdeadbeef"; }
	export -f uuid

	local tmpdir="$BATS_TMPDIR/init-session-test-$$"
	local id="" file=""
	_init_claude_session id file "owner/repo" "I42" "$tmpdir"

	[[ "$id" == "deadbeef-dead-beef-dead-beefdeadbeef" ]]
	[[ "$file" == "$tmpdir/.claude/sessions/deadbeef-dead-beef-dead-beefdeadbeef" ]]
}

@test "_init_claude_session: creates session directory" {
	uuid() { echo "deadbeef-dead-beef-dead-beefdeadbeef"; }
	export -f uuid

	local tmpdir="$BATS_TMPDIR/init-session-mkdir-test-$$"
	local id="" file=""
	_init_claude_session id file "owner/repo" "P99" "$tmpdir"

	[[ -d "$tmpdir/.claude/sessions" ]]
}

# ---------------------------------------------------------------------------
# _git_worktree_sync
# ---------------------------------------------------------------------------

@test "_git_worktree_sync: creates worktree when path does not exist" {
	local tmpdir="$BATS_TMPDIR/sync-wt-create-test-$$"
	mkdir -p "$tmpdir"

	local fetch_called=false
	local worktree_called=false

	git() {
		case "$1 $2" in
		"fetch origin") fetch_called=true ;;
		"worktree add") worktree_called=true; mkdir -p "$4" ;;
		*) ;;
		esac
	}
	export -f git

	gum() {
		case "$1" in
		spin)
			while [[ $# -gt 0 && "$1" != "--" ]]; do shift; done
			[[ $# -gt 0 ]] && shift
			"$@" || true
			;;
		log) ;;
		esac
	}
	export -f gum

	_git_worktree_sync "pr-99" "$tmpdir/pr-99" "feature/branch" "PR #99"

	[[ "$fetch_called" == true ]]
	[[ "$worktree_called" == true ]]
}

@test "_git_worktree_sync: fast-forwards existing worktree" {
	local tmpdir="$BATS_TMPDIR/sync-wt-ff-test-$$"
	mkdir -p "$tmpdir/pr-99"

	local merge_called=false

	git() {
		case "$1" in
		-C) merge_called=true ;;
		*) ;;
		esac
	}
	export -f git

	gum() {
		case "$1" in
		spin)
			while [[ $# -gt 0 && "$1" != "--" ]]; do shift; done
			[[ $# -gt 0 ]] && shift
			"$@" || true
			;;
		log) ;;
		esac
	}
	export -f gum

	_git_worktree_sync "pr-99" "$tmpdir/pr-99" "feature/branch" "PR #99"

	[[ "$merge_called" == true ]]
}

@test "_git_worktree_sync: returns error when merge is not fast-forward" {
	local tmpdir="$BATS_TMPDIR/sync-wt-diverged-test-$$"
	mkdir -p "$tmpdir/pr-99"

	git() {
		case "$1" in
		-C) return 1 ;;
		*) ;;
		esac
	}
	export -f git

	# Do NOT swallow errors with || true so the || { return 1; } block in
	# _git_worktree_sync fires when git merge --ff-only fails.
	gum() {
		case "$1" in
		spin)
			while [[ $# -gt 0 && "$1" != "--" ]]; do shift; done
			[[ $# -gt 0 ]] && shift
			"$@"
			;;
		log) ;;
		esac
	}
	export -f gum

	run _git_worktree_sync "pr-99" "$tmpdir/pr-99" "feature/branch" "PR #99"

	[[ "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# _cmd_chat
# ---------------------------------------------------------------------------

@test "_cmd_chat: starts new session when sentinel file is absent" {
	local tmpdir="$BATS_TMPDIR/chat-run-new-test-$$"
	mkdir -p "$tmpdir"
	local session_file="$tmpdir/session-abc"

	export _claude_out="$tmpdir/claude-session-id"
	claude() {
		local prev=""
		for arg in "$@"; do
			if [[ "$prev" == "--session-id" ]]; then
				echo "$arg" >"$_claude_out"
			fi
			prev="$arg"
		done
	}
	export -f claude

	_cmd_chat "$session_file" "issue-42" "test-uuid" "" "" \
		echo "plan content"

	[[ "$(cat "$_claude_out")" == "test-uuid" ]]
	[[ -f "$session_file" ]]
}

@test "_cmd_chat: touches sentinel file after successful new session" {
	local tmpdir="$BATS_TMPDIR/chat-run-touch-test-$$"
	mkdir -p "$tmpdir"
	local session_file="$tmpdir/session-xyz"

	claude() { :; }
	export -f claude

	_cmd_chat "$session_file" "issue-42" "test-uuid" "" "" \
		echo "plan content"

	[[ -f "$session_file" ]]
}

@test "_cmd_chat: resumes session when sentinel file exists" {
	local tmpdir="$BATS_TMPDIR/chat-run-resume-test-$$"
	mkdir -p "$tmpdir"
	local session_file="$tmpdir/session-abc"
	touch "$session_file"

	local resume_id=""
	claude() {
		for arg in "$@"; do
			if [[ "$prev" == "--resume" ]]; then
				resume_id="$arg"
			fi
			prev="$arg"
		done
	}
	export -f claude

	_cmd_chat "$session_file" "issue-42" "test-uuid" "" "" \
		echo "plan content"

	[[ "$resume_id" == "test-uuid" ]]
}

@test "_cmd_chat: passes preamble as last positional argument" {
	local tmpdir="$BATS_TMPDIR/chat-run-preamble-test-$$"
	mkdir -p "$tmpdir"
	local session_file="$tmpdir/session-abc"

	export _claude_out="$tmpdir/claude-last-arg"
	claude() { echo "${!#}" >"$_claude_out"; }
	export -f claude

	_cmd_chat "$session_file" "issue-42" "test-uuid" "IMPORTANT: Do not modify code." "" \
		echo "plan"

	[[ "$(cat "$_claude_out")" == "IMPORTANT: Do not modify code." ]]
}

@test "_cmd_chat: errors when provider is not supported" {
	local tmpdir="$BATS_TMPDIR/chat-provider-test-$$"
	mkdir -p "$tmpdir"
	local session_file="$tmpdir/session-abc"

	gh() {
		case "$1 $2" in
		"config get") echo "openai" ;;
		*) ;;
		esac
	}
	export -f gh

	run _cmd_chat "$session_file" "issue-42" "test-uuid" "" "" echo "plan"

	[[ "$status" -eq 1 ]]
}

@test "_cmd_chat: passes --model when model arg is non-empty" {
	local tmpdir="$BATS_TMPDIR/chat-model-test-$$"
	mkdir -p "$tmpdir"
	local session_file="$tmpdir/session-abc"

	export _claude_out="$tmpdir/claude-model"
	claude() {
		local prev=""
		for arg in "$@"; do
			if [[ "$prev" == "--model" ]]; then
				echo "$arg" >"$_claude_out"
			fi
			prev="$arg"
		done
	}
	export -f claude

	_cmd_chat "$session_file" "issue-42" "test-uuid" "" "claude-opus-4-5" echo "plan"

	[[ "$(cat "$_claude_out")" == "claude-opus-4-5" ]]
}

@test "_cmd_chat: omits --model when no model is configured" {
	local tmpdir="$BATS_TMPDIR/chat-no-model-test-$$"
	mkdir -p "$tmpdir"
	local session_file="$tmpdir/session-abc"

	local saw_model=false
	claude() {
		for arg in "$@"; do
			if [[ "$arg" == "--model" ]]; then
				saw_model=true
			fi
		done
	}
	export -f claude

	_cmd_chat "$session_file" "issue-42" "test-uuid" "" "" echo "plan"

	[[ "$saw_model" == false ]]
}
