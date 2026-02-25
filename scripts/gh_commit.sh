#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# Commit help function
#
# Displays help information for the commit command
# including usage examples and available options.
_show_commit_help() {
	cat <<'EOF'
gh assistant commit - Create commits with AI-generated messages

USAGE:
    gh assistant commit [GIT_COMMIT_OPTIONS]

DESCRIPTION:
    Generates a conventional commit message from staged changes using AI,
    then creates the commit. Any extra options are passed to git commit.

EXAMPLES:
    gh assistant commit                # Generate message and commit
    gh assistant commit --signoff      # Commit with sign-off
    gh assistant commit --no-verify    # Skip pre-commit hooks

SEE ALSO:
    git commit --help    # Full list of git commit options
EOF
}

# Main commit command implementation
#
# Creates a git commit with an AI-generated message based on staged changes.
# Uses assistant run with the template content directly injected into the prompt,
# and passes the staged diff as a file attachment.
#
# Usage: _gh_commit [GIT_COMMIT_OPTIONS]
# Example: _gh_commit --signoff --no-verify
_gh_commit() {
	case "${1:-}" in
	--help | -h | help)
		_show_commit_help
		return 0
		;;
	esac

	local args=("$@")
	local clean_args

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_assistant_source_dir/templates/gh_commit.tmpl"

	local filtered_args
	filtered_args=$(_filter_args "-m --message -F --file" "" -- "${args[@]}")
	# Filter out assistant-managed arguments
	if [[ -n "$filtered_args" ]]; then
		IFS=$'\n' read -rd '' -a clean_args <<<"$filtered_args" || true
	else
		clean_args=()
	fi

	# Gather git context
	local git_diff_staged
	git_diff_staged=$(git diff --staged)

	# Check if there are staged changes
	if [[ -z "$git_diff_staged" ]]; then
		gum log --level error "No staged changes found"
		gum log --level info "Stage your changes with 'git add' first"
		return 1
	fi

	local git_diff_staged_stat
	git_diff_staged_stat=$(git diff --staged --stat)

	local git_branch
	git_branch=$(git rev-parse --abbrev-ref HEAD)

	local git_commits
	git_commits=$(git log --oneline -5 2>/dev/null | sed 's/^[a-f0-9]* /- /')

	local agent_model
	agent_model=$(gh config get gh-assistant.commit.model 2>/dev/null || true)

	local git_message
	# Generate commit message using assistant run
	git_message=$(
		gum spin --title "Generating Git commit message..." -- \
			"$_gh_assistant_source_dir/scripts/gh_cmd.sh" assist "$agent_model" < <(
				GIT_DIFF_STAGED="$git_diff_staged" GIT_DIFF_STAGED_STAT="$git_diff_staged_stat" GIT_BRANCH="$git_branch" GIT_COMMITS="$git_commits" \
					"$_gh_assistant_source_dir/scripts/gh_cmd.sh" render "$template_file"
			)
	)

	# Validate we got a commit message
	if [[ -z "$git_message" ]]; then
		gum log --level error "Failed to generate commit message"
		gum log --level info "Run with DEBUG=1 for detailed diagnostics"
		return 1
	fi

	# Commit with the generated message and pass through any extra args
	git commit -m "$git_message" "${clean_args[@]}"
}
