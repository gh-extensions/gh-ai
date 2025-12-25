#!/usr/bin/env bash

# Shared utility functions for gh-opencode

# Get template directory path
#
# Returns the path to the template directory relative to source_dir.
# Requires $source_dir to be set by the main script.
#
# Usage: template_dir=$(_get_template_dir)
_get_template_dir() {
	# shellcheck disable=SC2154
	echo "$source_dir/templates"
}

# Extract content between HTML comment delimiters
#
# Parses output and extracts content between <!-- NAME_START --> and <!-- NAME_END -->
# This is used to extract generated content from AI responses.
#
# Usage: _extract_delimited_content "$output" "COMMIT_MESSAGE"
# Usage: _extract_delimited_content "$output" "PR_CONTENT"
# Usage: _extract_delimited_content "$output" "REVIEW_CONTENT"
_extract_delimited_content() {
	local output="$1"
	local name="$2"

	echo "$output" | sed -n "/<!-- ${name}_START -->/,/<!-- ${name}_END -->/p" | sed '1d;$d'
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
