#!/usr/bin/env bash

[ -z "$DEBUG" ] || set -x

set -eo pipefail

# Shared utility functions for gh-assistant

# Extract content between markers (exclusive of markers)
#
# Extracts text between start and end marker lines.
# Markers themselves are not included in output.
#
# Usage: echo "$output" | _extract_block "---START---" "---END---"
_extract_block() {
	local start="$1"
	local end="$2"
	sed -n "/${start}/,/${end}/p" | sed "1d;\$d"
}

# Create a temporary file with consistent naming
#
# Creates a temp file in $TMPDIR (or /tmp) with the given prefix.
# Caller is responsible for cleanup (use trap).
#
# Usage: diff_file=$(_create_temp_file "gh-opencode-diff")
_create_temp_file() {
	local prefix="${1:-gh-assistant-temp}"
	local tmpdir="${TMPDIR:-/tmp}"
	mktemp "${tmpdir%/}/${prefix}.XXXXXX"
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

# Parse tasks from body text
#
# Extracts task items matching the pattern: - [ ] T001 — Description
# Outputs JSON array of task objects.
#
# Usage: echo "$body" | _parse_tasks
# Returns: JSON array [{"id": "T001", "status": "pending", "description": "..."}]
_parse_tasks() {
	local line
	local tasks="[]"

	while IFS= read -r line; do
		# Match: - [ ] T001 — Description or - [x] T001 — Description
		if [[ "$line" =~ ^-\ \[([\ x])\]\ (T[0-9]+)\ —\ (.*)$ ]]; then
			local check="${BASH_REMATCH[1]}"
			local id="${BASH_REMATCH[2]}"
			local desc="${BASH_REMATCH[3]}"
			local status="pending"

			[[ "$check" == "x" ]] && status="completed"

			# Append to JSON array
			tasks=$(echo "$tasks" | jq --arg id "$id" --arg status "$status" --arg desc "$desc" \
				'. += [{"id": $id, "status": $status, "description": $desc}]')
		fi
	done

	echo "$tasks"
}

# Filter tasks by regex pattern
#
# Filters task array by matching regex against ID or description.
#
# Usage: echo "$tasks_json" | _filter_tasks "T00[1-3]"
# Returns: Filtered JSON array
_filter_tasks() {
	local pattern="$1"

	if [[ -z "$pattern" ]]; then
		cat
		return
	fi

	jq --arg pat "$pattern" '[.[] | select((.id | test($pat)) or (.description | test($pat)))]'
}

# Format tasks for display
#
# Formats task JSON array as table or JSON output.
#
# Usage: echo "$tasks_json" | _format_tasks [--json]
# Returns: Formatted output (table by default, JSON with --json)
_format_tasks() {
	local json_output=false

	if [[ "$1" == "--json" ]]; then
		json_output=true
	fi

	if [[ "$json_output" == true ]]; then
		cat
	else
		# Table header
		printf "%-8s %-10s %s\n" "ID" "STATUS" "DESCRIPTION"
		printf "%-8s %-10s %s\n" "----" "------" "-----------"

		# Table rows
		jq -r '.[] | "\(.id)\t\(.status)\t\(.description)"' | while IFS=$'\t' read -r id status desc; do
			local status_display="[ ]"
			[[ "$status" == "completed" ]] && status_display="[x]"
			printf "%-8s %-10s %s\n" "$id" "$status_display" "$desc"
		done
	fi
}

# Modify task status in body text
#
# Checks or unchecks a specific task in the body text.
#
# Usage: echo "$body" | _modify_task_status "T001" "check"
# Usage: echo "$body" | _modify_task_status "T001" "uncheck"
# Returns: Modified body text
_modify_task_status() {
	local task_id="$1"
	local action="$2"

	if [[ "$action" == "check" ]]; then
		sed "s/^- \[ \] ${task_id} —/- [x] ${task_id} —/"
	else
		sed "s/^- \[x\] ${task_id} —/- [ ] ${task_id} —/"
	fi
}
