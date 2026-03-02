#!/usr/bin/env bash
#
# Worktree hooks for Claude Code
#
# Subcommands:
#   create — reads JSON {name, cwd} from stdin, creates a git worktree
#            tracking the matching remote branch, prints worktree path
#   remove — reads JSON {worktree_path} from stdin, removes the worktree

set -euo pipefail

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Create a git worktree for a Claude Code session
#
# Reads JSON from stdin with "name", "cwd", and "session_id" fields.
# Looks up the session state file to resolve the remote ref to track.
# The local branch is named worktree-<name>.
#
# Stdin:  {"name": "issue-42", "cwd": "/path/to/repo", "session_id": "uuid"}
# Stdout: worktree path (e.g. /path/to/repo/.claude/worktrees/issue-42)
# Stderr: git worktree add output
_gh_worktree_create() {
	local input
	input=$(cat)

	local gh_worktree_jq
	gh_worktree_jq=$(<"$_script_dir/gh_worktree.jq")

	# First pass: extract name, cwd, session_id from Claude's hook JSON
	local gh_worktree_name gh_worktree_cwd gh_worktree_session_id gh_worktree_remote_ref="main"
	eval "$(printf '%s' "$input" | jq -r "$gh_worktree_jq")"

	# Second pass: overlay remote_ref from the session state file (same jq filter)
	# Try new directory format first, then fall back to old .json format
	local session_state_file="${gh_worktree_cwd}/.claude/sessions/${gh_worktree_session_id}/state.json"
	if [[ -f "$session_state_file" ]]; then
		eval "$(jq -r "$gh_worktree_jq" "$session_state_file")"
	else
		session_state_file="${gh_worktree_cwd}/.claude/sessions/${gh_worktree_session_id}.json"
		if [[ -f "$session_state_file" ]]; then
			eval "$(jq -r "$gh_worktree_jq" "$session_state_file")"
		fi
	fi

	local gh_worktree_path
	gh_worktree_path="${gh_worktree_cwd}/.claude/worktrees/${gh_worktree_name}"

	local git_ref="origin/${gh_worktree_remote_ref}"

	# If the worktree is already registered, reuse it instead of failing
	if git -C "$gh_worktree_cwd" worktree list --porcelain | grep -qx "worktree ${gh_worktree_path}"; then
		printf '%s\n' "$gh_worktree_path"
		return 0
	fi

	# Ensure the remote tracking branch is available locally before creating the worktree.
	# This is necessary when the branch has never been fetched (e.g. on first session start).
	git -C "$gh_worktree_cwd" fetch origin "$gh_worktree_remote_ref" >&2 || true

	git -C "$gh_worktree_cwd" worktree add -B "worktree-${gh_worktree_name}" "$gh_worktree_path" "$git_ref" >&2

	printf '%s\n' "$gh_worktree_path"
}

# Check if a worktree has uncommitted changes (untracked, modified, staged)
#
# Returns 0 if dirty, 1 if clean.
#
# Usage: _gh_worktree_is_dirty "/path/to/worktree"
_gh_worktree_is_dirty() {
	local wt="$1"
	[[ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]]
}

# Check if a worktree has commits not pushed to the upstream branch
#
# Returns 0 if there are unpushed commits, 1 otherwise.
# Falls back to clean when there is no upstream configured.
#
# Usage: _gh_worktree_has_unpushed "/path/to/worktree"
_gh_worktree_has_unpushed() {
	local wt="$1"
	local ahead
	ahead=$(git -C "$wt" rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo "0")
	[[ "$ahead" -gt 0 ]]
}

# Remove a git worktree created by _gh_worktree_create
#
# Reads JSON from stdin with "worktree_path" field. Before removing,
# checks for uncommitted or unpushed changes. If found, auto-stashes
# them so they are recoverable from the main repo via `git stash list`.
#
# WorktreeRemove hooks have no decision control and cannot be
# interactive — they run as cleanup side effects. Auto-stash is the
# safest non-interactive strategy to prevent silent data loss.
#
# Silently removes clean worktrees.
# Silently succeeds if the worktree path does not exist.
#
# Stdin: {"worktree_path": "/path/to/repo/.claude/worktrees/issue-42"}
_gh_worktree_remove() {
	local worktree_path
	worktree_path=$(jq -r .worktree_path)

	# Nothing to do if the worktree doesn't exist
	if [[ ! -d "$worktree_path" ]]; then
		return 0
	fi

	# Auto-stash dirty changes so they survive worktree removal
	if _gh_worktree_is_dirty "$worktree_path"; then
		local wt_name
		wt_name=$(basename "$worktree_path")
		# Stage everything (including untracked) so stash captures it all
		git -C "$worktree_path" add -A
		git -C "$worktree_path" stash push -m "gh-ai: auto-stash worktree '${wt_name}'" 2>/dev/null || true
		echo "Auto-stashed uncommitted changes from worktree '${wt_name}' — recover with: git stash list" >&2
	fi

	# Warn about unpushed commits (stash doesn't help here — they're in the branch reflog)
	if _gh_worktree_has_unpushed "$worktree_path"; then
		local branch
		branch=$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
		echo "Warning: branch '${branch}' has unpushed commits — they remain in the reflog" >&2
	fi

	git -C "$worktree_path" worktree remove -f "$worktree_path" 2>/dev/null || true
}

# CLI entry point (when executed directly, not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	case "${1:-}" in
	create)
		_gh_worktree_create
		;;
	remove)
		_gh_worktree_remove
		;;
	*)
		echo "Usage: gh_worktree.sh <create|remove>" >&2
		exit 1
		;;
	esac
fi
