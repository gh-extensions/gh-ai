#!/usr/bin/env bash

[ -z "$DEBUG" ] || set -x

set -eo pipefail

# Commit-related functions for gh-assistant

# Filter out assistant-managed arguments for commit
#
# Removes arguments that assistant manages internally (-m, --message, -F, --file)
# and returns the remaining arguments. This allows users to pass other git commit
# flags while assistant handles the commit message.
#
# Example: _filter_gh_commit_args --all -m "message" --signoff
# Returns: --all --signoff
_filter_gh_commit_args() {
	local input_args=("$@")
	local filtered_args=()
	local i=0

	while [[ $i -lt ${#input_args[@]} ]]; do
		case "${input_args[$i]}" in
		# Arguments to filter out (assistant manages these)
		-m | --message | -F | --file)
			# Skip this argument and its value
			if [[ $((i + 1)) -lt ${#input_args[@]} ]] && [[ "${input_args[$((i + 1))]}" != -* ]]; then
				((++i)) # Skip the value too
			fi
			;;
		--message=* | --file=*) ;;
		*)
			# Pass through all other arguments
			filtered_args+=("${input_args[$i]}")
			;;
		esac
		((++i))
	done

	# Output the filtered arguments
	printf '%s\n' "${filtered_args[@]}"
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
	local args=("$@")
	local clean_args

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_assistant_source_dir/templates/gh_commit.tmpl"

	# Filter out assistant-managed arguments
	local filtered_output
	filtered_output=$(_filter_gh_commit_args "${args[@]}")
	IFS=$'\n' read -rd '' -a clean_args <<<"$filtered_output" || true

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
		return 1
	fi

	# Commit with the generated message and pass through any extra args
	git commit -m "$git_message" "${clean_args[@]}"
}
