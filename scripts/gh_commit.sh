#!/usr/bin/env bash

# Commit-related functions for gh-agent

# Filter out agent-managed arguments for commit
#
# Removes arguments that agent manages internally (-m, --message, -F, --file)
# and returns the remaining arguments. This allows users to pass other git commit
# flags while agent handles the commit message.
#
# Example: _filter_gh_commit_args --all -m "message" --signoff
# Returns: --all --signoff
_filter_gh_commit_args() {
	local input_args=("$@")
	local filtered_args=()
	local i=0

	while [[ $i -lt ${#input_args[@]} ]]; do
		case "${input_args[$i]}" in
		# Arguments to filter out (agent manages these)
		-m | --message | -F | --file)
			# Skip this argument and its value
			if [[ $((i + 1)) -lt ${#input_args[@]} ]] && [[ "${input_args[$((i + 1))]}" != -* ]]; then
				((i++)) # Skip the value too
			fi
			;;
		*)
			# Pass through all other arguments
			filtered_args+=("${input_args[$i]}")
			;;
		esac
		((i++))
	done

	# Output the filtered arguments
	printf '%s\n' "${filtered_args[@]}"
}

# Main commit command implementation
#
# Creates a git commit with an AI-generated message based on staged changes.
# Uses agent run with the template content directly injected into the prompt,
# and passes the staged diff as a file attachment.
#
# Usage: _gh_commit [GIT_COMMIT_OPTIONS]
# Example: _gh_commit --signoff --no-verify
_gh_commit() {
	local args=("$@")
	local clean_args
	local output
	local commit_message
	local model
	local prompt
	local diff_file
	local template_dir

	# Template directory (relative to source_dir from main script)
	template_dir=$(_get_template_dir)
	template_file="$template_dir/gh_commit.md"

	# Model for commit message generation
	model="claude-3-5-haiku-20241022"

	# Filter out agent-managed arguments
	local filtered_output
	filtered_output=$(_filter_gh_commit_args "${args[@]}")
	IFS=$'\n' read -rd '' -a clean_args <<<"$filtered_output" || true

	# Create temporary file for diff
	diff_file=$(_create_temp_file "gh-agent-diff")
	# shellcheck disable=SC2064
	trap "rm -f '$diff_file'" RETURN

	# Get staged diff
	if ! git diff --staged >"$diff_file"; then
		gum log --level error "Failed to get staged changes"
		return 1
	fi

	# Check if there are staged changes
	_require_file_not_empty "$diff_file" "No staged changes found. Please stage your changes with 'git add' first." || return 1

	# Build the prompt from template
	prompt="The instructions are provided in the @$template_file file. The staged diff is the @$diff_file file."

	# Generate commit message using agent run
	output=$(
		gum spin --title "Generating Git commit message..." -- \
			claude --model "$model" -p "$prompt"
	)

	# Check execution success
	# shellcheck disable=SC2181
	if [[ $? -ne 0 ]]; then
		gum log --level error "Failed to generate commit message"
		return 1
	fi

	# Extract commit message from output
	commit_message=$output

	# Validate we got a commit message
	if [[ -z "$commit_message" ]]; then
		gum log --level error "Failed to extract commit message from output"
		return 1
	fi

	# Commit with the generated message and pass through any extra args
	git commit -m "$commit_message" "${clean_args[@]}"
}
