#!/usr/bin/env bats

# Unit tests for gh_worktree.sh
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_worktree.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _gh_ai_source_dir="$REPO_ROOT"
	export HOME="$BATS_TEST_TMPDIR"

	# Create a bare "remote" and a worktree-like local clone
	git init --bare "$BATS_TEST_TMPDIR/remote.git" >/dev/null 2>&1
	git clone "$BATS_TEST_TMPDIR/remote.git" "$BATS_TEST_TMPDIR/repo" >/dev/null 2>&1
	git -C "$BATS_TEST_TMPDIR/repo" config user.email "test@test.com"
	git -C "$BATS_TEST_TMPDIR/repo" config user.name "Test"
	git -C "$BATS_TEST_TMPDIR/repo" commit --allow-empty -m "initial" >/dev/null 2>&1
	git -C "$BATS_TEST_TMPDIR/repo" push >/dev/null 2>&1

	# Create a worktree off the clone
	WORKTREE_PATH="$BATS_TEST_TMPDIR/repo/.claude/worktrees/issue-1"
	git -C "$BATS_TEST_TMPDIR/repo" worktree add -b issue-1 "$WORKTREE_PATH" HEAD >/dev/null 2>&1
	local _main_branch
	_main_branch=$(git -C "$BATS_TEST_TMPDIR/repo" rev-parse --abbrev-ref HEAD)
	git -C "$WORKTREE_PATH" branch --set-upstream-to="origin/${_main_branch}" >/dev/null 2>&1

	# Source the functions under test
	# shellcheck disable=SC2155
	eval "$(
		# shellcheck source=../scripts/gh_worktree.sh
		source "$REPO_ROOT/scripts/gh_worktree.sh"
		declare -f _gh_worktree_is_dirty _gh_worktree_has_unpushed _gh_worktree_remove
	)"
}

teardown() {
	# Clean up worktrees so git doesn't complain
	git -C "$BATS_TEST_TMPDIR/repo" worktree prune 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# _gh_worktree_is_dirty
# ---------------------------------------------------------------------------

@test "_gh_worktree_is_dirty: returns 1 for clean worktree" {
	run _gh_worktree_is_dirty "$WORKTREE_PATH"
	[[ "$status" -eq 1 ]]
}

@test "_gh_worktree_is_dirty: returns 0 for untracked file" {
	echo "new" >"$WORKTREE_PATH/untracked.txt"

	run _gh_worktree_is_dirty "$WORKTREE_PATH"
	[[ "$status" -eq 0 ]]
}

@test "_gh_worktree_is_dirty: returns 0 for staged changes" {
	echo "staged" >"$WORKTREE_PATH/staged.txt"
	git -C "$WORKTREE_PATH" add staged.txt

	run _gh_worktree_is_dirty "$WORKTREE_PATH"
	[[ "$status" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# _gh_worktree_has_unpushed
# ---------------------------------------------------------------------------

@test "_gh_worktree_has_unpushed: returns 1 when up to date" {
	run _gh_worktree_has_unpushed "$WORKTREE_PATH"
	[[ "$status" -eq 1 ]]
}

@test "_gh_worktree_has_unpushed: returns 0 when commits ahead" {
	git -C "$WORKTREE_PATH" commit --allow-empty -m "local only" >/dev/null 2>&1

	run _gh_worktree_has_unpushed "$WORKTREE_PATH"
	[[ "$status" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# _gh_worktree_remove
# ---------------------------------------------------------------------------

@test "_gh_worktree_remove: removes clean worktree silently" {
	echo '{"worktree_path": "'"$WORKTREE_PATH"'"}' | _gh_worktree_remove

	[[ ! -d "$WORKTREE_PATH" ]]
}

@test "_gh_worktree_remove: succeeds when worktree path does not exist" {
	echo '{"worktree_path": "/nonexistent/path"}' | _gh_worktree_remove
}

@test "_gh_worktree_remove: auto-stashes uncommitted changes before removal" {
	echo "save me" >"$WORKTREE_PATH/dirty.txt"

	echo '{"worktree_path": "'"$WORKTREE_PATH"'"}' | _gh_worktree_remove

	# Worktree should be removed
	[[ ! -d "$WORKTREE_PATH" ]]

	# Changes should be in the stash
	local stash_list
	stash_list=$(git -C "$BATS_TEST_TMPDIR/repo" stash list)
	[[ "$stash_list" == *"gh-ai: auto-stash worktree 'issue-1'"* ]]
}

@test "_gh_worktree_remove: stash includes untracked files" {
	echo "untracked" >"$WORKTREE_PATH/new_file.txt"

	echo '{"worktree_path": "'"$WORKTREE_PATH"'"}' | _gh_worktree_remove

	# Pop the stash into the main repo and verify the file is there
	git -C "$BATS_TEST_TMPDIR/repo" stash pop >/dev/null 2>&1
	[[ -f "$BATS_TEST_TMPDIR/repo/new_file.txt" ]]
}

@test "_gh_worktree_remove: warns about unpushed commits" {
	git -C "$WORKTREE_PATH" commit --allow-empty -m "unpushed work" >/dev/null 2>&1

	local output
	output=$(echo '{"worktree_path": "'"$WORKTREE_PATH"'"}' | _gh_worktree_remove 2>&1)

	# Worktree should be removed
	[[ ! -d "$WORKTREE_PATH" ]]

	# Should warn about unpushed commits
	[[ "$output" == *"unpushed commits"* ]]
}

@test "_gh_worktree_remove: stashes and warns when both dirty and unpushed" {
	echo "dirty" >"$WORKTREE_PATH/dirty.txt"
	git -C "$WORKTREE_PATH" commit --allow-empty -m "unpushed" >/dev/null 2>&1

	local output
	output=$(echo '{"worktree_path": "'"$WORKTREE_PATH"'"}' | _gh_worktree_remove 2>&1)

	[[ ! -d "$WORKTREE_PATH" ]]
	[[ "$output" == *"auto-stash"*"issue-1"* ]]
	[[ "$output" == *"unpushed commits"* ]]
}

@test "_gh_worktree_remove: does not stash when worktree is clean" {
	echo '{"worktree_path": "'"$WORKTREE_PATH"'"}' | _gh_worktree_remove

	local stash_list
	stash_list=$(git -C "$BATS_TEST_TMPDIR/repo" stash list)
	[[ -z "$stash_list" ]]
}
