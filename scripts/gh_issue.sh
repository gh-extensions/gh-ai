#!/usr/bin/env bash

# Issue-related functions for gh-assistant

# List tasks in an issue body
#
# Extracts and displays task items from the issue body.
#
# Usage: _gh_issue_task_list <issue_number> [--filter <regex>] [--json]
_gh_issue_task_list() {
	local issue_number="$1"
	shift
	local filter=""
	local json_output=""

	# Parse options
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--filter)
			filter="$2"
			shift 2
			;;
		--json)
			json_output="--json"
			shift
			;;
		*)
			shift
			;;
		esac
	done

	if [[ -z "$issue_number" ]]; then
		gum log --level error "Issue number required"
		gum log --level info "Usage: gh assistant issue task list <number> [--filter <regex>] [--json]"
		return 1
	fi

	local body
	body=$(_gh_api_issue_view "$issue_number" | jq -r '.body')

	if [[ -z "$body" || "$body" == "null" ]]; then
		gum log --level error "Issue #$issue_number has no body"
		return 1
	fi

	echo "$body" | _parse_tasks | _filter_tasks "$filter" | _format_tasks $json_output
}

# View a specific task in an issue
#
# Displays details of a specific task item.
#
# Usage: _gh_issue_task_view <issue_number> <task_id> [--json]
_gh_issue_task_view() {
	local issue_number="$1"
	local task_id="$2"
	local json_output=""

	if [[ "$3" == "--json" ]]; then
		json_output="--json"
	fi

	if [[ -z "$issue_number" || -z "$task_id" ]]; then
		gum log --level error "Issue number and task ID required"
		gum log --level info "Usage: gh assistant issue task view <number> <task_id> [--json]"
		return 1
	fi

	local body
	body=$(_gh_api_issue_view "$issue_number" | jq -r '.body')

	if [[ -z "$body" || "$body" == "null" ]]; then
		gum log --level error "Issue #$issue_number has no body"
		return 1
	fi

	local task
	task=$(echo "$body" | _parse_tasks | jq --arg id "$task_id" '.[] | select(.id == $id)')

	if [[ -z "$task" || "$task" == "null" ]]; then
		gum log --level error "Task $task_id not found in issue #$issue_number"
		return 1
	fi

	if [[ -n "$json_output" ]]; then
		echo "$task"
	else
		local id status desc
		id=$(echo "$task" | jq -r '.id')
		status=$(echo "$task" | jq -r '.status')
		desc=$(echo "$task" | jq -r '.description')
		echo "$id — $desc"
		echo "Status: $status"
	fi
}

# Check a task in an issue
#
# Marks a task item as completed in the issue body.
#
# Usage: _gh_issue_task_check <issue_number> <task_id>
_gh_issue_task_check() {
	local issue_number="$1"
	local task_id="$2"

	if [[ -z "$issue_number" || -z "$task_id" ]]; then
		gum log --level error "Issue number and task ID required"
		gum log --level info "Usage: gh assistant issue task check <number> <task_id>"
		return 1
	fi

	local body
	body=$(_gh_api_issue_view "$issue_number" | jq -r '.body')

	if [[ -z "$body" || "$body" == "null" ]]; then
		gum log --level error "Issue #$issue_number has no body"
		return 1
	fi

	local new_body
	new_body=$(echo "$body" | _modify_task_status "$task_id" "check")

	if [[ "$body" == "$new_body" ]]; then
		gum log --level warn "Task $task_id not found or already checked"
		return 1
	fi

	_gh_api_issue_update "$issue_number" "body=$new_body" >/dev/null
	gum log --level info "Checked task $task_id in issue #$issue_number"
}

# Uncheck a task in an issue
#
# Marks a task item as pending in the issue body.
#
# Usage: _gh_issue_task_uncheck <issue_number> <task_id>
_gh_issue_task_uncheck() {
	local issue_number="$1"
	local task_id="$2"

	if [[ -z "$issue_number" || -z "$task_id" ]]; then
		gum log --level error "Issue number and task ID required"
		gum log --level info "Usage: gh assistant issue task uncheck <number> <task_id>"
		return 1
	fi

	local body
	body=$(_gh_api_issue_view "$issue_number" | jq -r '.body')

	if [[ -z "$body" || "$body" == "null" ]]; then
		gum log --level error "Issue #$issue_number has no body"
		return 1
	fi

	local new_body
	new_body=$(echo "$body" | _modify_task_status "$task_id" "uncheck")

	if [[ "$body" == "$new_body" ]]; then
		gum log --level warn "Task $task_id not found or already unchecked"
		return 1
	fi

	_gh_api_issue_update "$issue_number" "body=$new_body" >/dev/null
	gum log --level info "Unchecked task $task_id in issue #$issue_number"
}

# Issue task help function
_gh_issue_task_help() {
	cat <<'EOF'
gh assistant issue task - Manage tasks in issue body

USAGE:
    gh assistant issue task list <number> [--filter <regex>] [--json]
    gh assistant issue task view <number> <task_id> [--json]
    gh assistant issue task check <number> <task_id>
    gh assistant issue task uncheck <number> <task_id>

COMMANDS:
    list        List all tasks in issue body
    view        View a specific task
    check       Mark a task as completed
    uncheck     Mark a task as pending

EXAMPLES:
    gh assistant issue task list 42
    gh assistant issue task list 42 --filter 'T00[1-3]'
    gh assistant issue task list 42 --json
    gh assistant issue task view 42 T001
    gh assistant issue task check 42 T001
    gh assistant issue task uncheck 42 T002
EOF
}

# Issue task subcommand router
_gh_issue_task() {
	local subcommand="$1"
	shift

	case $subcommand in
	list)
		_gh_issue_task_list "$@"
		;;
	view)
		_gh_issue_task_view "$@"
		;;
	check)
		_gh_issue_task_check "$@"
		;;
	uncheck)
		_gh_issue_task_uncheck "$@"
		;;
	--help | -h | help | "")
		_gh_issue_task_help
		;;
	*)
		gum log --level error "Unknown task command '$subcommand'"
		gum log --level info "Available commands: list, view, check, uncheck"
		gum log --level info "Run 'gh assistant issue task --help' for usage information"
		exit 1
		;;
	esac
}

# Issue help function
_show_issue_help() {
	cat <<'EOF'
gh assistant issue - Issue commands

USAGE:
    gh assistant issue task <subcommand> [OPTIONS]

DESCRIPTION:
    Manage task checklists in issue bodies.

COMMANDS:
    task        Manage tasks in issue body (list, view, check, uncheck)

SEE ALSO:
    gh assistant issue task --help    # Task management commands
EOF
}

# Issue subcommand handler
#
# Routes issue subcommands to their appropriate handler functions.
#
# Usage: _gh_issue <subcommand> [OPTIONS]
# Subcommands: task, help
_gh_issue() {
	local subcommand="$1"
	shift

	case $subcommand in
	task)
		_gh_issue_task "$@"
		;;
	--help | -h | help | "")
		_show_issue_help
		;;
	*)
		gum log --level error "Unknown issue command '$subcommand'"
		gum log --level info "Available commands: task"
		gum log --level info "Run 'gh assistant issue --help' for usage information"
		exit 1
		;;
	esac
}
