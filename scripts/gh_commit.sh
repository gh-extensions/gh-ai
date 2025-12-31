#!/usr/bin/env bash

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
# Uses assistant run with the template content directly injected into the prompt,
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
	local prompt_dir

	# Prompt directory (relative to source_dir from main script)
	prompt_dir=$(_get_prompt_dir)
	prompt_file="$prompt_dir/gh_commit.md"

	# Model for commit message generation
	model="claude-3-5-haiku-20241022"

	# Filter out assistant-managed arguments
	local filtered_output
	filtered_output=$(_filter_gh_commit_args "${args[@]}")
	IFS=$'\n' read -rd '' -a clean_args <<<"$filtered_output" || true

	# Create temporary file for diff
	diff_file=$(_create_temp_file "gh-assistant-diff")
	# shellcheck disable=SC2064
	# trap "rm -f '$diff_file'" RETURN

	# Get staged diff
	if ! git diff --staged >"$diff_file"; then
		gum log --level error "Failed to get staged changes"
		return 1
	fi

	# Check if there are staged changes
	_require_file_not_empty "$diff_file" "No staged changes found. Please stage your changes with 'git add' first." || return 1

	# Build the prompt from prompt file
	prompt="Follow @$prompt_file instructions for staged_diff @$diff_file"

	# Generate commit message using assistant run
	output=$(
		gum spin --title "Generating Git commit message..." -- \
			claude \
			--no-session-persistence \
			--permission-mode "dontAsk" \
			--allowed-tools "Read($diff_file)" \
			--allowed-tools "Read($prompt_file)" \
			--model "$model" --print "$prompt"
	)

	# Check execution success
	# shellcheck disable=SC2181
	if [[ $? -ne 0 ]]; then
		gum log --level error "Failed to generate commit message"
		return 1
	fi

	# Extract commit message from output (between markers)
	commit_message=$(echo "$output" | _extract_block "<!-- COMMIT_START -->" "<!-- COMMIT_END -->")
	# Validate we got a commit message
	if [[ -z "$commit_message" ]]; then
		gum log --level error "Failed to extract commit message from output"
		return 1
	fi

	# Commit with the generated message and pass through any extra args
	git commit -m "$commit_message" "${clean_args[@]}"
}
