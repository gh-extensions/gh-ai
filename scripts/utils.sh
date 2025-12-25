#!/usr/bin/env bash

# Shared utility functions for gh-opencode

# Get prompt directory path
#
# Returns the path to the prompt directory relative to source_dir.
# Requires $source_dir to be set by the main script.
#
# Usage: prompt_dir=$(_get_prompt_dir)
_get_prompt_dir() {
	# shellcheck disable=SC2154
	echo "$_gh_assistant_source_dir/prompts"
}

# Create a temporary file with consistent naming
#
# Creates a temp file in $TMPDIR (or /tmp) with the given prefix.
# Caller is responsible for cleanup (use trap).
#
# Usage: diff_file=$(_create_temp_file "gh-opencode-diff")
_create_temp_file() {
	local prefix="${1:-gh-assistant-temp}"
	mktemp "${TMPDIR:-/tmp}/${prefix}.XXXXXX"
}

# Check if file has content, log error if empty
#
# Returns 0 if file exists and has content, 1 otherwise.
# Logs the provided error message on failure.
#
# Usage: _require_file_not_empty "$file" "No staged changes found"
_require_file_not_empty() {
	local file="$1"
	local error_msg="$2"

	if [[ ! -s "$file" ]]; then
		gum log --level error "$error_msg"
		return 1
	fi
}
