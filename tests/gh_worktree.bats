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
	git -C "$BATS_TEST_TMPDIR/repo" config commit.gpgsign false
	git -C "$BATS_TEST_TMPDIR/repo" commit --allow-empty -m "initial" >/dev/null 2>&1
	git -C "$BATS_TEST_TMPDIR/repo" push >/dev/null 2>&1

	# Create a worktree off the clone
	WORKTREE_PATH="$BATS_TEST_TMPDIR/repo/.claude/worktrees/issue-1"
	git -C "$BATS_TEST_TMPDIR/repo" worktree add -b issue-1 "$WORKTREE_PATH" HEAD >/dev/null 2>&1
	DEFAULT_BRANCH=$(git -C "$BATS_TEST_TMPDIR/repo" rev-parse --abbrev-ref HEAD)
	git -C "$WORKTREE_PATH" branch --set-upstream-to="origin/${DEFAULT_BRANCH}" >/dev/null 2>&1

	# Source the functions under test
	# shellcheck disable=SC2155
	eval "$(
		# shellcheck source=../scripts/gh_worktree.sh
		source "$REPO_ROOT/scripts/gh_worktree.sh"
		declare -f _save_worktree_state _load_worktree_state _gh_worktree_create \
			_gh_worktree_is_dirty _gh_worktree_has_unpushed _gh_worktree_remove
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

# ---------------------------------------------------------------------------
# _save_worktree_state
# ---------------------------------------------------------------------------

@test "_save_worktree_state: writes worktree.json with all fields" {
	local session_dir="$BATS_TEST_TMPDIR/sessions/pull-42"
	mkdir -p "$session_dir"

	_save_worktree_state "$session_dir" "pull-42" "feature" "abc123" "feature-branch"

	local json
	json=$(cat "$session_dir/worktree.json")
	[[ "$(printf '%s' "$json" | jq -r '.name')" == "pull-42" ]]
	[[ "$(printf '%s' "$json" | jq -r '.remote_ref')" == "feature" ]]
	[[ "$(printf '%s' "$json" | jq -r '.head_sha')" == "abc123" ]]
	[[ "$(printf '%s' "$json" | jq -r '.branch')" == "feature-branch" ]]
}

@test "_save_worktree_state: branch defaults to empty string when omitted" {
	local session_dir="$BATS_TEST_TMPDIR/sessions/issue-7"
	mkdir -p "$session_dir"

	_save_worktree_state "$session_dir" "issue-7" "main" "" ""

	local branch
	branch=$(jq -r '.branch' "$session_dir/worktree.json")
	[[ "$branch" == "" ]]
}

@test "_save_worktree_state: falls back to git origin/HEAD when remote_ref is empty" {
	local session_dir="$BATS_TEST_TMPDIR/sessions/issue-8"
	mkdir -p "$session_dir"

	# Run from inside the test repo so git rev-parse can resolve origin/HEAD
	(cd "$BATS_TEST_TMPDIR/repo" && _save_worktree_state "$session_dir" "issue-8" "" "" "")

	local remote_ref
	remote_ref=$(jq -r '.remote_ref' "$session_dir/worktree.json")
	[[ -n "$remote_ref" ]]
	[[ "$remote_ref" != "" ]]
}

@test "_save_worktree_state: falls back to main when git and gh both fail" {
	local session_dir="$BATS_TEST_TMPDIR/sessions/issue-9"
	mkdir -p "$session_dir"

	# Run in a subprocess so that sourcing gh_worktree.sh (which sets -euo pipefail)
	# causes the git|sed pipeline to exit non-zero when git fails, triggering the fallback.
	run bash -c "
		source '$REPO_ROOT/scripts/gh_worktree.sh'
		git() { return 1; }
		gh() { return 1; }
		export -f git gh
		_save_worktree_state '$session_dir' 'issue-9' '' '' ''
		jq -r .remote_ref '$session_dir/worktree.json'
	"

	[[ "$status" -eq 0 ]]
	[[ "$output" == "main" ]]
}

# ---------------------------------------------------------------------------
# _load_worktree_state
# ---------------------------------------------------------------------------

@test "_load_worktree_state: returns 1 when worktree.json is absent" {
	local session_dir="$BATS_TEST_TMPDIR/sessions/missing"
	mkdir -p "$session_dir"

	local ref="" sha="" branch=""
	run _load_worktree_state "$session_dir" ref sha branch

	[[ "$status" -eq 1 ]]
}

@test "_load_worktree_state: populates all three namerefs from existing file" {
	local session_dir="$BATS_TEST_TMPDIR/sessions/pull-55"
	mkdir -p "$session_dir"
	_save_worktree_state "$session_dir" "pull-55" "feature-x" "deadbeef" "feature-x"

	local ref="" sha="" branch=""
	_load_worktree_state "$session_dir" ref sha branch

	[[ "$ref" == "feature-x" ]]
	[[ "$sha" == "deadbeef" ]]
	[[ "$branch" == "feature-x" ]]
}

# ---------------------------------------------------------------------------
# _gh_worktree_create
# ---------------------------------------------------------------------------

@test "_gh_worktree_create: errors when name is missing from hook JSON" {
	local repo_real
	repo_real=$(cd "$BATS_TEST_TMPDIR/repo" && pwd -P)

	run bash -c "printf '%s' '{\"cwd\": \"$repo_real\"}' | '$REPO_ROOT/scripts/gh_worktree.sh' create"

	[[ "$status" -ne 0 ]]
}

@test "_gh_worktree_create: errors when cwd is missing from hook JSON" {
	run bash -c "printf '%s' '{\"name\": \"pull-99\"}' | '$REPO_ROOT/scripts/gh_worktree.sh' create"

	[[ "$status" -ne 0 ]]
}

@test "_gh_worktree_create: errors when worktree.json is not found in session dir" {
	local repo_real
	repo_real=$(cd "$BATS_TEST_TMPDIR/repo" && pwd -P)

	run bash -c "printf '%s' '{\"name\": \"pull-99\", \"cwd\": \"$repo_real\"}' | '$REPO_ROOT/scripts/gh_worktree.sh' create"

	[[ "$status" -ne 0 ]]
}

@test "_gh_worktree_create: errors when branch is already checked out in another worktree" {
	# issue-1 branch is already checked out in WORKTREE_PATH from setup.
	# Use a different worktree name ("issue-1-alt") so the path check doesn't
	# reuse the existing worktree — only the branch conflict check should fire.
	local repo_real
	repo_real=$(cd "$BATS_TEST_TMPDIR/repo" && pwd -P)
	local session_dir="$repo_real/.claude/sessions/issue-1-alt"
	mkdir -p "$session_dir"
	_save_worktree_state "$session_dir" "issue-1-alt" "$DEFAULT_BRANCH" "" "issue-1"

	run bash -c "printf '%s' '{\"name\": \"issue-1-alt\", \"cwd\": \"$repo_real\"}' | '$REPO_ROOT/scripts/gh_worktree.sh' create"

	[[ "$status" -ne 0 ]]
	[[ "$output" == *"already checked out"* ]]
}

@test "_gh_worktree_create: creates worktree at expected path and prints it" {
	local repo_real
	repo_real=$(cd "$BATS_TEST_TMPDIR/repo" && pwd -P)
	local session_dir="$repo_real/.claude/sessions/pull-99"
	local worktree_path="$repo_real/.claude/worktrees/pull-99"
	mkdir -p "$session_dir"
	_save_worktree_state "$session_dir" "pull-99" "$DEFAULT_BRANCH" "" ""

	local output
	output=$(printf '%s' "{\"name\": \"pull-99\", \"cwd\": \"$repo_real\"}" | "$REPO_ROOT/scripts/gh_worktree.sh" create)

	[[ -d "$worktree_path" ]]
	[[ "$output" == "$worktree_path" ]]
}

@test "_gh_worktree_create: is idempotent when worktree already exists" {
	local repo_real
	repo_real=$(cd "$BATS_TEST_TMPDIR/repo" && pwd -P)
	local session_dir="$repo_real/.claude/sessions/pull-100"
	local worktree_path="$repo_real/.claude/worktrees/pull-100"
	mkdir -p "$session_dir"
	_save_worktree_state "$session_dir" "pull-100" "$DEFAULT_BRANCH" "" ""

	# First call creates the worktree
	printf '%s' "{\"name\": \"pull-100\", \"cwd\": \"$repo_real\"}" | "$REPO_ROOT/scripts/gh_worktree.sh" create >/dev/null

	# Second call should succeed and return the same path
	local output
	output=$(printf '%s' "{\"name\": \"pull-100\", \"cwd\": \"$repo_real\"}" | "$REPO_ROOT/scripts/gh_worktree.sh" create)

	[[ "$output" == "$worktree_path" ]]
}
