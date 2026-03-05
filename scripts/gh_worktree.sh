#!/usr/bin/env bash
#
# Worktree hooks for Claude Code
#
# Subcommands:
#   create — reads JSON {name, cwd} from stdin, creates a git worktree
#            tracking the matching remote branch, prints worktree path
#   remove — reads JSON {worktree_path} from stdin, removes the worktree

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# Returns 0 if the current directory is inside a git worktree (not the main tree).
#
# Used to skip worktree lifecycle (create/remove hooks, --worktree flag) when
# gh-ai is invoked inside an already-prepared worktree (e.g. by gh-worktree).
#
# Usage: _gh_in_worktree && echo "inside worktree"
_gh_in_worktree() {
	local git_dir common_dir
	git_dir=$(git rev-parse --git-dir 2>/dev/null) || return 1
	common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || return 1
	[[ "$git_dir" != "$common_dir" ]]
}

# Save worktree metadata to session_dir/worktree.json.
#
# Called in each _gh_*_chat after context prep. The file is read by
# _gh_worktree_create to initialize the worktree for the session.
# Falls back to the repo's default branch when remote_ref is empty.
#
# Usage: _save_worktree_state session_dir name remote_ref head_sha [branch]
_save_worktree_state() {
	local _sws_dir="$1"
	local _sws_name="$2"
	local _sws_remote_ref="$3"
	local _sws_sha="$4"
	local _sws_branch="${5:-}"

	if [[ -z "$_sws_remote_ref" ]]; then
		_sws_remote_ref=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' | grep . ||
			gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null ||
			echo "main")
	fi

	jq -n \
		--arg name "$_sws_name" \
		--arg remote_ref "$_sws_remote_ref" \
		--arg head_sha "$_sws_sha" \
		--arg branch "$_sws_branch" \
		'{name: $name, remote_ref: $remote_ref, head_sha: $head_sha, branch: $branch}' \
		>"$_sws_dir/worktree.json"
}

# Load worktree metadata from session_dir/worktree.json into namerefs.
#
# Returns 1 if worktree.json is absent.
#
# Usage: _load_worktree_state session_dir remote_ref_ref sha_ref branch_ref
_load_worktree_state() {
	local _lws_dir="$1"
	local -n _lws_remote_ref="$2"
	local -n _lws_sha="$3"
	local -n _lws_branch="$4"

	local spec="$_lws_dir/worktree.json"
	if [[ ! -f "$spec" ]]; then
		return 1
	fi

	eval "$(jq -r '
		"_lws_remote_ref=" + ((.remote_ref // "") | @sh),
		"_lws_sha=" + ((.head_sha // "") | @sh),
		"_lws_branch=" + ((.branch // "") | @sh)
	' "$spec")"
}

# Create a git worktree for a Claude Code session
#
# Reads JSON from stdin with "name" and "cwd" fields (Claude's WorktreeCreate hook format).
# Loads remote_ref and head_sha from $cwd/.claude/sessions/$name/worktree.json
# (written by _save_worktree_state before the session starts).
# Returns exit code 1 if worktree.json is absent — Claude treats this as a hook error.
#
# Stdin:  {"name": "pull-42", "cwd": "/path/to/repo", ...}
# Stdout: worktree path (e.g. /path/to/repo/.claude/worktrees/pull-42)
# Stderr: git worktree add output
_gh_worktree_create() {
	local hook_json
	hook_json=$(cat)

	local gh_worktree_name="" gh_worktree_cwd=""
	eval "$(printf '%s' "$hook_json" | jq -rf "$(dirname "${BASH_SOURCE[0]}")/gh_worktree_meta.jq")"

	if [[ -z "$gh_worktree_name" || -z "$gh_worktree_cwd" ]]; then
		gum log --level error "gh_worktree_create: missing name or cwd in hook JSON"
		return 1
	fi

	# Load saved state (remote_ref, head_sha, branch) written by _save_worktree_state.
	local session_dir="$gh_worktree_cwd/.claude/sessions/$gh_worktree_name"
	local gh_worktree_remote_ref="" gh_worktree_sha="" gh_worktree_branch=""
	if ! _load_worktree_state "$session_dir" gh_worktree_remote_ref gh_worktree_sha gh_worktree_branch; then
		gum log --level error "gh_worktree_create: worktree.json not found in $session_dir"
		return 1
	fi

	local gh_worktree_path
	gh_worktree_path="${gh_worktree_cwd}/.claude/worktrees/${gh_worktree_name}"
	mkdir -p "${gh_worktree_cwd}/.claude/worktrees"

	# Capture the worktree list once and reuse it for both checks below.
	local wt_list
	wt_list=$(git -C "$gh_worktree_cwd" worktree list --porcelain)

	# If the worktree is already registered, reuse it instead of failing.
	if grep -qxF "worktree ${gh_worktree_path}" <<<"$wt_list"; then
		printf '%s\n' "$gh_worktree_path"
		return 0
	fi

	# PR sessions set branch to the PR head so the worktree checks it out directly
	# and `git push` updates the PR without extra flags. Issue/run sessions leave
	# branch empty, so a new local branch named after the worktree is created instead.
	local checkout_branch="${gh_worktree_branch:-$gh_worktree_name}"

	# Refuse to create the worktree if the desired branch is already checked out
	# elsewhere — git itself would fail, and silently using a different branch
	# would break auto-tracking for PR sessions.
	if grep -qxF "branch refs/heads/${checkout_branch}" <<<"$wt_list"; then
		gum log --level error "branch '${checkout_branch}' is already checked out in another worktree"
		return 1
	fi

	if git -C "$gh_worktree_cwd" show-ref --verify --quiet "refs/heads/${checkout_branch}"; then
		# Fast-forward the local branch to the remote tip in one fetch, so the
		# worktree always starts from the current state. If the local branch has
		# diverged (local commits ahead of remote), the fetch refuses and the
		# worktree opens at the local state instead.
		git -C "$gh_worktree_cwd" fetch origin "${checkout_branch}:${checkout_branch}" >&2 || true
		git -C "$gh_worktree_cwd" worktree add "$gh_worktree_path" "${checkout_branch}" >&2
	else
		# Fetch the remote branch so the SHA (or branch tip) is available locally.
		git -C "$gh_worktree_cwd" fetch origin "$gh_worktree_remote_ref" >&2 || true

		# Use the pinned SHA when present (run sessions), otherwise the remote branch tip.
		# Pinning to a SHA guarantees the worktree always starts from the exact commit
		# that triggered the run, regardless of how far the branch has since moved.
		local git_ref="${gh_worktree_sha:-origin/${gh_worktree_remote_ref}}"

		# Use auto-tracking only when checking out the actual PR head branch so
		# that `git push` updates the PR without extra flags. Issue/run sessions
		# use --no-track to avoid wiring a local branch to the wrong remote ref.
		local track_flag=""
		[[ "$checkout_branch" != "$gh_worktree_branch" ]] && track_flag="--no-track"
		git -C "$gh_worktree_cwd" worktree add ${track_flag:+"$track_flag"} -b "${checkout_branch}" "$gh_worktree_path" "$git_ref" >&2
	fi

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

# Check if a worktree has commits not pushed to any remote
#
# Returns 0 if there are unpushed commits, 1 otherwise.
# Uses --not --remotes so no upstream tracking branch is required —
# works correctly for PR, issue, and run worktrees alike.
#
# Usage: _gh_worktree_has_unpushed "/path/to/worktree"
_gh_worktree_has_unpushed() {
	local wt="$1"
	local ahead
	ahead=$(git -C "$wt" rev-list --count HEAD --not --remotes 2>/dev/null || echo "0")
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
	worktree_path=$(jq -r '.worktree_path')

	# Nothing to do if the worktree doesn't exist
	if [[ ! -d "$worktree_path" ]]; then
		return 0
	fi

	# Auto-stash dirty changes so they survive worktree removal
	if _gh_worktree_is_dirty "$worktree_path"; then
		local wt_name
		wt_name=$(basename "$worktree_path")
		# Stage everything (including untracked) so stash captures it all
		git -C "$worktree_path" add -A 2>/dev/null || true
		if git -C "$worktree_path" stash push -m "gh-ai: auto-stash worktree '${wt_name}'" 2>/dev/null; then
			gum log --level info "Auto-stashed uncommitted changes from worktree '${wt_name}' — recover with: git stash list"
		fi
	fi

	# Warn about unpushed commits (stash doesn't help here — they're in the branch reflog)
	if _gh_worktree_has_unpushed "$worktree_path"; then
		local branch
		branch=$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
		gum log --level warn "branch '${branch}' has unpushed commits — they remain in the reflog"
	fi

	git -C "$worktree_path" worktree remove -f "$worktree_path" 2>/dev/null || true
}

main() {
	local command="${1:-}"
	shift || true

	case $command in
	create)
		_gh_worktree_create
		;;
	remove)
		_gh_worktree_remove
		;;
	*)
		gum log --level error "unknown command '${command}'"
		exit 1
		;;
	esac
}

# CLI entry point (when executed directly, not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
