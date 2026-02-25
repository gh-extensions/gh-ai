#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# Commit help function
#
# Displays help information for the commit command
# including usage examples and available options.
_show_commit_help() {
	cat <<'EOF'
gh ai commit - Create commits with AI-generated messages

USAGE:
    gh ai commit [GIT_COMMIT_OPTIONS]

DESCRIPTION:
    Generates a conventional commit message from staged changes using AI,
    then creates the commit. Any extra options are passed to git commit.

EXAMPLES:
    gh ai commit                # Generate message and commit
    gh ai commit --signoff      # Commit with sign-off
    gh ai commit --no-verify    # Skip pre-commit hooks

SEE ALSO:
    git commit --help    # Full list of git commit options
EOF
}

# Filter out flags managed by gh-ai from git commit arguments
#
# Removes -m/--message and -F/--file flags (and their values) since
# the commit message is AI-generated. All other flags pass through.
_filter_commit_args() {
	local filtered=()
	local skip_next=false
	local arg

	for arg in "$@"; do
		if [ "$skip_next" = true ]; then
			skip_next=false
			continue
		fi

		case "$arg" in
		-m | --message | -F | --file)
			skip_next=true
			;;
		--message=* | --file=*)
			;;
		*)
			filtered+=("$arg")
			;;
		esac
	done

	[[ ${#filtered[@]} -gt 0 ]] && printf '%s\n' "${filtered[@]}" || true
}

# Main commit command implementation
#
# Creates a git commit with an AI-generated message based on staged changes.
# Renders a prompt template with the staged diff and branch context,
# sends it to the AI provider, and commits with the response.
#
# Usage: _gh_commit [GIT_COMMIT_OPTIONS]
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
	template_file="$_gh_ai_source_dir/templates/gh_commit.tmpl"

	local filtered_args
	filtered_args=$(_filter_commit_args "${args[@]}")
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
	agent_model=$(gh config get gh-ai.commit.model 2>/dev/null || true)

	local git_message
	# Generate commit message using assistant run
	git_message=$(
		gum spin --title "Generating Git commit message..." -- \
			"$_gh_ai_source_dir/scripts/gh_cmd.sh" assist "$agent_model" < <(
				GIT_DIFF_STAGED="$git_diff_staged" GIT_DIFF_STAGED_STAT="$git_diff_staged_stat" GIT_BRANCH="$git_branch" GIT_COMMITS="$git_commits" \
					"$_gh_ai_source_dir/scripts/gh_cmd.sh" render "$template_file"
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
