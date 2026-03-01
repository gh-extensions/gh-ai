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
	local session_state_file="${gh_worktree_cwd}/.claude/sessions/${gh_worktree_session_id}.json"
	if [[ -f "$session_state_file" ]]; then
		eval "$(jq -r "$gh_worktree_jq" "$session_state_file")"
	fi

	local gh_worktree_path
	gh_worktree_path="${gh_worktree_cwd}/.claude/worktrees/${gh_worktree_name}"

	local git_ref="origin/${gh_worktree_remote_ref}"
	git -C "$gh_worktree_cwd" worktree add -B "worktree-${gh_worktree_name}" "$gh_worktree_path" "$git_ref" >&2

	printf '%s\n' "$gh_worktree_path"
}

# Remove a git worktree created by _gh_worktree_create
#
# Reads JSON from stdin with "worktree_path" field and force-removes
# the worktree. Silently succeeds if the path does not exist.
#
# Stdin: {"worktree_path": "/path/to/repo/.claude/worktrees/issue-42"}
_gh_worktree_remove() {
	local worktree_path
	worktree_path=$(jq -r .worktree_path)
	git worktree remove -f "$worktree_path" 2>/dev/null || true
}

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
