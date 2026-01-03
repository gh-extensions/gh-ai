#!/usr/bin/env bash

[ -z "$DEBUG" ] || set -x

set -eo pipefail

# PR-related functions for gh-assistant

# Extract PR number from arguments
#
# Searches through command line arguments to find a numeric PR number.
# Returns the first numeric argument found, or exits with code 1 if none found.
#
# Example: _get_pr_number review 123 --body "test"  # Returns: 123
_get_pr_number() {
	local args=("$@")
	local i=0

	# Look for a numeric argument (PR number)
	while [[ $i -lt ${#args[@]} ]]; do
		if [[ "${args[$i]}" =~ ^[0-9]+$ ]]; then
			echo "${args[$i]}"
			return 0
		fi
		((i++))
	done

	# No PR number found - will let gh pr review handle this
	return 1
}

# Auto-detect PR number for current branch
#
# Uses gh pr view to get the PR number associated with the current branch.
# Returns the PR number or exits with code 1 if no PR found.
#
# Usage: _detect_pr_number
_detect_pr_number() {
	local pr_number

	pr_number=$(gh pr view --json number -q '.number' 2>/dev/null)

	if [[ -n "$pr_number" ]]; then
		echo "$pr_number"
		return 0
	fi

	return 1
}

# Extract title from AI response
#
# Gets the PR title from AI-generated content by taking the first line
# and removing any markdown heading prefix (#).
#
# Example: _get_pr_title "# Fix bug in parser\n\nDescription..."
# Returns: "Fix bug in parser"
_get_pr_title() {
	local ai_content="$1"
	local title

	# Extract title (first line with # prefix removed)
	title=$(echo "$ai_content" | head -n 1 | sed 's/^# *//')

	# Validate we got a title
	if [[ -z "$title" ]]; then
		gum log --level error "Failed to extract title from AI content"
		return 1
	fi

	echo "$title"
}

# Extract body from AI response and save to file
#
# Takes everything after the first line of AI content (skipping the title)
# and saves it to a temporary markdown file. Removes any leading blank lines
# to ensure clean formatting. This avoids duplicating the title which is
# already set in the PR title field.
# Caller must handle cleanup of the temporary file.
_get_pr_body() {
	local ai_content="$1"
	local body_file

	# Create temporary file for body content
	body_file=$(mktemp).md

	# Extract body (skip first line) and remove leading blank lines
	echo "$ai_content" | tail -n +2 | sed '/./,$!d' >"$body_file"

	# Return the file path
	echo "$body_file"
}

# Filter out assistant-managed arguments for PR create
#
# Removes PR create arguments that assistant handles (title, body, fill flags)
# so users can still pass other options like --draft, --base, etc.
#
# Filters out: --title/-t, --body/-b, --body-file/-F, --fill variants
# Example: _filter_gh_pr_create_args --title "test" --draft --base main
# Returns: --draft --base main
_filter_gh_pr_create_args() {
	local input_args=("$@")
	local filtered_args=()
	local i=0

	while [[ $i -lt ${#input_args[@]} ]]; do
		case "${input_args[$i]}" in
		# Arguments to filter out (assistant manages these)
		--title | -t | --body | -b | --body-file | -F)
			# Skip this argument and its value
			if [[ $((i + 1)) -lt ${#input_args[@]} ]] && [[ "${input_args[$((i + 1))]}" != -* ]]; then
				((i++)) # Skip the value too
			fi
			;;
		--fill | --fill-first | --fill-verbose)
			# These flags don't have values, just skip
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

# Filter arguments for PR review (remove assistant-managed ones)
#
# Removes review arguments that assistant handles (body, comment flags)
# while preserving other options like PR number and --approve.
#
# Filters out: --body/-b, --body-file/-F, --comment/-c
# Example: _filter_gh_pr_review_args 123 --body "test" --approve
# Returns: 123 --approve
_filter_gh_pr_review_args() {
	local input_args=("$@")
	local filtered_args=()
	local i=0

	while [[ $i -lt ${#input_args[@]} ]]; do
		case "${input_args[$i]}" in
		# Arguments to filter out (assistant manages these)
		--body | -b | --body-file | -F | --comment | -c)
			# Skip this argument and its value
			if [[ $((i + 1)) -lt ${#input_args[@]} ]] && [[ "${input_args[$((i + 1))]}" != -* ]]; then
				((i++)) # Skip the value too
			fi
			;;
		*)
			# Pass through all other arguments (including PR number)
			filtered_args+=("${input_args[$i]}")
			;;
		esac
		((i++))
	done

	# Output the filtered arguments
	printf '%s\n' "${filtered_args[@]}"
}

# PR Create implementation
#
# Creates a GitHub PR with AI-generated title and description.
# Uses assistant run with the template content directly injected into the prompt,
# and passes the git diff and commit log as file attachments.
# Falls back to manual PR creation if AI generation fails.
#
# Usage: _gh_pr_create [GH_PR_CREATE_OPTIONS]
_gh_pr_create() {
	local args=("$@")
	local clean_args
	local output
	local pr_content
	local title
	local body_file
	local model
	local diff_file
	local log_file
	local prompt_dir
	local base_branch
	local head_branch

	# Prompt directory (relative to source_dir from main script)
	prompt_dir=$(_get_prompt_dir)
	prompt_file="$prompt_dir/gh_pr_ready.md"

	# Model for PR content generation
	model="claude-3-5-haiku-20241022"

	# Filter out assistant-managed arguments
	local filtered_output
	filtered_output=$(_filter_gh_pr_create_args "${args[@]}")
	IFS=$'\n' read -rd '' -a clean_args <<<"$filtered_output" || true

	# Determine base and head branches
	head_branch=$(git rev-parse --abbrev-ref HEAD)
	base_branch=$(git rev-parse --abbrev-ref origin/HEAD 2>/dev/null | sed 's|origin/||' || echo "main")

	# Check for --base flag in args to override default
	local i=0
	while [[ $i -lt ${#args[@]} ]]; do
		if [[ "${args[$i]}" == "--base" ]] && [[ $((i + 1)) -lt ${#args[@]} ]]; then
			base_branch="${args[$((i + 1))]}"
			break
		fi
		((i++))
	done

	# Create temporary files for diff and log
	diff_file=$(_create_temp_file "gh-assistant-pr-diff")
	log_file=$(_create_temp_file "gh-assistant-pr-log")
	# shellcheck disable=SC2064
	trap "rm -f '$diff_file' '$log_file'" RETURN

	# Get diff between base and head
	# shellcheck disable=SC2140
	if ! git diff "origin/$base_branch"..."$head_branch" >"$diff_file" 2>/dev/null; then
		# Fallback: try without origin prefix
		if ! git diff "$base_branch"..."$head_branch" >"$diff_file" 2>/dev/null; then
			gum log --level error "Failed to get diff between $base_branch and $head_branch"
			return 1
		fi
	fi

	# Check if there are changes
	_require_file_not_empty "$diff_file" "No changes between $base_branch and $head_branch" || return 1

	# Get commit log
	# shellcheck disable=SC2140
	git log --oneline "origin/$base_branch".."$head_branch" >"$log_file" 2>/dev/null ||
		git log --oneline "$base_branch".."$head_branch" >"$log_file" 2>/dev/null || true

	# Build the prompt from prompt file
	prompt="Follow @$prompt_file instructions for pr_diff @$diff_file and pr_log @$log_file"

	# Generate PR content using assistant run
	output=$(
		gum spin --title "Generating GitHub pull request..." -- \
			claude \
			--no-session-persistence \
			--permission-mode "dontAsk" \
			--allowed-tools "Read($log_file)" \
			--allowed-tools "Read($diff_file)" \
			--allowed-tools "Read($prompt_file)" \
			--model "$model" --print "$prompt"
	)

	# Check execution success
	# shellcheck disable=SC2181
	if [[ $? -ne 0 ]]; then
		gum log --level warn "AI content generation failed. Aborting."
		return 1
	fi

	# Extract PR content from output (between markers)
	pr_content=$(echo "$output" | _extract_block "<!-- PR_START -->" "<!-- PR_END -->")
	# Validate we got a pr content
	if [[ -z "$pr_content" ]]; then
		gum log --level warn "Failed to extract PR content. Aborting."
		return 1
	fi

	# Parse title and body from PR content
	if ! title=$(_get_pr_title "$pr_content"); then
		return 1
	fi

	body_file=$(_get_pr_body "$pr_content")
	trap 'rm -f "$body_file"' EXIT INT TERM

	# Create PR with AI-generated content
	gh pr create --title "$title" --body-file "$body_file" "${clean_args[@]}"
}

# PR Review implementation
#
# Submits a GitHub PR review with AI-generated feedback.
# Uses assistant run with the template content directly injected into the prompt,
# and passes the PR diff as a file attachment.
# Auto-detects PR number from current branch if not provided.
#
# Usage: _gh_pr_review [PR_NUMBER] [GH_PR_REVIEW_OPTIONS] [--model MODEL]
_gh_pr_review() {
	local args=("$@")
	local clean_args
	local pr_number
	local output
	local review_content
	local review_file
	local model
	local diff_file
	local prompt_dir

	# Prompt directory (relative to source_dir from main script)
	prompt_dir=$(_get_prompt_dir)
	prompt_file="$prompt_dir/gh_pr_review.md"

	# Model for PR content generation
	model="claude-3-5-haiku-20241022"

	# Extract PR number from arguments or auto-detect
	pr_number=$(_get_pr_number "${args[@]}")
	if [[ -z "$pr_number" ]]; then
		pr_number=$(_detect_pr_number)
		if [[ -z "$pr_number" ]]; then
			gum log --level error "No PR number provided and could not detect PR for current branch"
			gum log --level info "Usage: gh assistant pr review <PR_NUMBER> [OPTIONS]"
			return 1
		fi
		gum log --level info "Auto-detected PR #$pr_number for current branch"
	fi

	# Filter out assistant-managed arguments
	local filtered_output
	filtered_output=$(_filter_gh_pr_review_args "${args[@]}")
	IFS=$'\n' read -rd '' -a clean_args <<<"$filtered_output" || true

	# Create temporary file for PR diff
	diff_file=$(_create_temp_file "gh-assistant-review-diff")
	# shellcheck disable=SC2064
	trap "rm -f '$diff_file'" RETURN

	# Get PR diff using gh cli (--patch for full patch format)
	if ! gh pr diff "$pr_number" --patch >"$diff_file" 2>/dev/null; then
		gum log --level error "Failed to get diff for PR #$pr_number"
		return 1
	fi

	# Check if there's content
	_require_file_not_empty "$diff_file" "No changes found in PR #$pr_number" || return 1

	# Build the prompt from prompt file
	prompt="Follow @$prompt_file instructions for pr_diff @$diff_file"

	# Generate review content using assistant run
	output=$(
		gum spin --title "Generating GitHub pull request review..." -- \
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
		gum log --level error "Failed to generate AI review. Aborting."
		return 1
	fi

	# Extract review content from output (between markers)
	review_content=$(echo "$output" | _extract_block "<!-- REVIEW_START -->" "<!-- REVIEW_END -->")
	# Validate we got a commit message
	if [[ -z "$review_content" ]]; then
		gum log --level error "Failed to extract review content. Aborting."
		return 1
	fi

	# Create review file from content
	review_file=$(_create_temp_file "gh-assistant-review")
	echo "$review_content" >"$review_file"
	trap 'rm -f "$review_file"' EXIT INT TERM

	# Submit review with AI-generated content
	gh pr review "$pr_number" --body-file "$review_file" "${clean_args[@]}"
}

# List tasks in a PR body
#
# Extracts and displays task items from the PR body.
#
# Usage: _gh_pr_task_list <pr_number> [--filter <regex>] [--json]
_gh_pr_task_list() {
	local pr_number="$1"
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

	if [[ -z "$pr_number" ]]; then
		pr_number=$(_detect_pr_number)
		if [[ -z "$pr_number" ]]; then
			gum log --level error "PR number required"
			gum log --level info "Usage: gh assistant pr task list <number> [--filter <regex>] [--json]"
			return 1
		fi
	fi

	local body
	body=$(_gh_api_pr_view "$pr_number" | jq -r '.body')

	if [[ -z "$body" || "$body" == "null" ]]; then
		gum log --level error "PR #$pr_number has no body"
		return 1
	fi

	echo "$body" | _parse_tasks | _filter_tasks "$filter" | _format_tasks $json_output
}

# View a specific task in a PR
#
# Displays details of a specific task item.
#
# Usage: _gh_pr_task_view <pr_number> <task_id> [--json]
_gh_pr_task_view() {
	local pr_number="$1"
	local task_id="$2"
	local json_output=""

	if [[ "$3" == "--json" ]]; then
		json_output="--json"
	fi

	if [[ -z "$pr_number" || -z "$task_id" ]]; then
		gum log --level error "PR number and task ID required"
		gum log --level info "Usage: gh assistant pr task view <number> <task_id> [--json]"
		return 1
	fi

	local body
	body=$(_gh_api_pr_view "$pr_number" | jq -r '.body')

	if [[ -z "$body" || "$body" == "null" ]]; then
		gum log --level error "PR #$pr_number has no body"
		return 1
	fi

	local task
	task=$(echo "$body" | _parse_tasks | jq --arg id "$task_id" '.[] | select(.id == $id)')

	if [[ -z "$task" || "$task" == "null" ]]; then
		gum log --level error "Task $task_id not found in PR #$pr_number"
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

# Check a task in a PR
#
# Marks a task item as completed in the PR body.
#
# Usage: _gh_pr_task_check <pr_number> <task_id>
_gh_pr_task_check() {
	local pr_number="$1"
	local task_id="$2"

	if [[ -z "$pr_number" || -z "$task_id" ]]; then
		gum log --level error "PR number and task ID required"
		gum log --level info "Usage: gh assistant pr task check <number> <task_id>"
		return 1
	fi

	local body
	body=$(_gh_api_pr_view "$pr_number" | jq -r '.body')

	if [[ -z "$body" || "$body" == "null" ]]; then
		gum log --level error "PR #$pr_number has no body"
		return 1
	fi

	local new_body
	new_body=$(echo "$body" | _modify_task_status "$task_id" "check")

	if [[ "$body" == "$new_body" ]]; then
		gum log --level warn "Task $task_id not found or already checked"
		return 1
	fi

	_gh_api_pr_update "$pr_number" "body=$new_body" >/dev/null
	gum log --level info "Checked task $task_id in PR #$pr_number"
}

# Uncheck a task in a PR
#
# Marks a task item as pending in the PR body.
#
# Usage: _gh_pr_task_uncheck <pr_number> <task_id>
_gh_pr_task_uncheck() {
	local pr_number="$1"
	local task_id="$2"

	if [[ -z "$pr_number" || -z "$task_id" ]]; then
		gum log --level error "PR number and task ID required"
		gum log --level info "Usage: gh assistant pr task uncheck <number> <task_id>"
		return 1
	fi

	local body
	body=$(_gh_api_pr_view "$pr_number" | jq -r '.body')

	if [[ -z "$body" || "$body" == "null" ]]; then
		gum log --level error "PR #$pr_number has no body"
		return 1
	fi

	local new_body
	new_body=$(echo "$body" | _modify_task_status "$task_id" "uncheck")

	if [[ "$body" == "$new_body" ]]; then
		gum log --level warn "Task $task_id not found or already unchecked"
		return 1
	fi

	_gh_api_pr_update "$pr_number" "body=$new_body" >/dev/null
	gum log --level info "Unchecked task $task_id in PR #$pr_number"
}

# PR task help function
_gh_pr_task_help() {
	cat <<'EOF'
gh assistant pr task - Manage tasks in PR body

USAGE:
    gh assistant pr task list <number> [--filter <regex>] [--json]
    gh assistant pr task view <number> <task_id> [--json]
    gh assistant pr task check <number> <task_id>
    gh assistant pr task uncheck <number> <task_id>

COMMANDS:
    list        List all tasks in PR body
    view        View a specific task
    check       Mark a task as completed
    uncheck     Mark a task as pending

EXAMPLES:
    gh assistant pr task list 123
    gh assistant pr task list 123 --filter 'T00[1-3]'
    gh assistant pr task list 123 --json
    gh assistant pr task view 123 T001
    gh assistant pr task check 123 T001
    gh assistant pr task uncheck 123 T002
EOF
}

# PR task subcommand router
_gh_pr_task() {
	local subcommand="$1"
	shift

	case $subcommand in
	list)
		_gh_pr_task_list "$@"
		;;
	view)
		_gh_pr_task_view "$@"
		;;
	check)
		_gh_pr_task_check "$@"
		;;
	uncheck)
		_gh_pr_task_uncheck "$@"
		;;
	--help | -h | help | "")
		_gh_pr_task_help
		;;
	*)
		gum log --level error "Unknown task command '$subcommand'"
		gum log --level info "Available commands: list, view, check, uncheck"
		gum log --level info "Run 'gh assistant pr task --help' for usage information"
		exit 1
		;;
	esac
}

# PR help function
#
# Displays comprehensive help information for all PR subcommands
# including usage examples and available options.
_show_pr_help() {
	cat <<'EOF'
gh assistant pr - Pull request commands with AI assistance

USAGE:
    gh assistant pr create [GH_PR_CREATE_OPTIONS] [--model MODEL]
    gh assistant pr review [PR_NUMBER] [GH_PR_REVIEW_OPTIONS] [--model MODEL]
    gh assistant pr task <subcommand> [OPTIONS]

DESCRIPTION:
    Creates and reviews GitHub pull requests with AI-generated content.
    Manage task checklists in PR bodies.

COMMANDS:
    create      Create PRs with AI-generated titles and descriptions
    review      Review PRs with AI-generated feedback
    task        Manage tasks in PR body (list, view, check, uncheck)

SEE ALSO:
    gh assistant pr create --help    # Full list of gh pr create options
    gh assistant pr review --help    # Full list of gh pr review options
    gh assistant pr task --help      # Task management commands
EOF
}

# PR subcommand handler
#
# Routes PR subcommands (create, review, task) to their appropriate
# handler functions. Shows help for unknown commands.
#
# Usage: _gh_pr <subcommand> [OPTIONS]
# Subcommands: create, review, task, help
_gh_pr() {
	local subcommand="$1"
	shift

	case $subcommand in
	create)
		_gh_pr_create "$@"
		;;
	review)
		_gh_pr_review "$@"
		;;
	task)
		_gh_pr_task "$@"
		;;
	--help | -h | help | "")
		_show_pr_help
		;;
	*)
		gum log --level error "Unknown pr command '$subcommand'"
		gum log --level info "Available commands: create, review, task"
		gum log --level info "Run 'gh assistant pr --help' for usage information"
		exit 1
		;;
	esac
}
