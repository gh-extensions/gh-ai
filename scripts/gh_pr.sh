#!/usr/bin/env bash

[ -z "$DEBUG" ] || set -x

set -eo pipefail

# PR-related functions for gh-assistant

# Resolve PR number from arguments or current branch
#
# First looks for a numeric argument in the provided args.
# Falls back to auto-detecting the PR for the current branch via gh pr view.
# Returns the PR number or exits with code 1 if none found.
#
# Example: _get_pr_number review 123 --body "test"  # Returns: 123
# Example: _get_pr_number --approve                 # Returns: detected PR number
_get_pr_number() {
	local args=("$@")
	local i=0

	# Look for a numeric argument (PR number)
	while [[ $i -lt ${#args[@]} ]]; do
		if [[ "${args[$i]}" =~ ^[0-9]+$ ]]; then
			echo "${args[$i]}"
			return 0
		fi
		((++i))
	done

	# Fall back to auto-detecting PR for current branch
	gh pr view --json number -q '.number' 2>/dev/null || true
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
	title=$(printf '%s\n' "$ai_content" | head -n 1 | sed 's/^# *//')

	# Validate we got a title
	if [[ -z "$title" ]]; then
		gum log --level error "Failed to extract title from AI content"
		return 1
	fi

	printf '%s\n' "$title"
}

# Extract body from AI response
#
# Takes everything after the first line of AI content (skipping the title)
# and removes leading blank lines. This avoids duplicating the title which is
# already set in the PR title field.
_get_pr_body() {
	local ai_content="$1"

	# Extract body (skip first line) and remove leading blank lines
	printf '%s\n' "$ai_content" | tail -n +2 | sed '/./,$!d'
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
				((++i)) # Skip the value too
			fi
			;;
		--title=* | --body=* | --body-file=*) ;;
		--fill | --fill-first | --fill-verbose)
			# These flags don't have values, just skip
			;;
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

# Filter arguments for PR review (remove assistant-managed ones)
#
# Removes review arguments that assistant handles (body, comment flags)
# while preserving other options like PR number and --approve.
#
# Filters out: --body/-b, --body-file/-F
# Example: _filter_gh_pr_review_args 123 --body "test" --approve
# Returns: 123 --approve
_filter_gh_pr_review_args() {
	local input_args=("$@")
	local filtered_args=()
	local i=0

	while [[ $i -lt ${#input_args[@]} ]]; do
		case "${input_args[$i]}" in
		# Arguments to filter out (assistant manages these)
		--body | -b | --body-file | -F)
			# Skip this argument and its value
			if [[ $((i + 1)) -lt ${#input_args[@]} ]] && [[ "${input_args[$((i + 1))]}" != -* ]]; then
				((++i)) # Skip the value too
			fi
			;;
		--body=* | --body-file=*) ;;
		*)
			# Pass through all other arguments (including PR number)
			filtered_args+=("${input_args[$i]}")
			;;
		esac
		((++i))
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

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_assistant_source_dir/templates/gh_pr_create.tmpl"

	# Filter out assistant-managed arguments
	local filtered_output
	filtered_output=$(_filter_gh_pr_create_args "${args[@]}")
	IFS=$'\n' read -rd '' -a clean_args <<<"$filtered_output" || true

	local git_head_branch
	git_head_branch=$(git rev-parse --abbrev-ref HEAD)

	local git_base_branch
	git_base_branch=$(git rev-parse --abbrev-ref origin/HEAD 2>/dev/null | sed 's|origin/||' || echo "main")

	# Check for --base flag in args to override default
	local i=0
	while [[ $i -lt ${#args[@]} ]]; do
		if [[ "${args[$i]}" == "--base" ]] && [[ $((i + 1)) -lt ${#args[@]} ]]; then
			git_base_branch="${args[$((i + 1))]}"
			break
		fi
		((++i))
	done

	# Get diff between base and head
	local git_diff
	# shellcheck disable=SC2140
	if ! git_diff=$(git diff "origin/$git_base_branch"..."$git_head_branch" 2>/dev/null) || [[ -z "$git_diff" ]]; then
		# Fallback: try without origin prefix
		if ! git_diff=$(git diff "$git_base_branch"..."$git_head_branch" 2>/dev/null) || [[ -z "$git_diff" ]]; then
			gum log --level error "Failed to get diff between $git_base_branch and $git_head_branch"
			return 1
		fi
	fi

	local git_diff_stat
	# shellcheck disable=SC2140
	git_diff_stat=$(git diff "origin/$git_base_branch"..."$git_head_branch" --stat 2>/dev/null ||
		git diff "$git_base_branch"..."$git_head_branch" --stat 2>/dev/null || true)

	local git_log
	# shellcheck disable=SC2140
	git_log=$(git log --oneline "origin/$git_base_branch".."$git_head_branch" 2>/dev/null ||
		git log --oneline "$git_base_branch".."$git_head_branch" 2>/dev/null || true)

	local git_commits
	# shellcheck disable=SC2001
	git_commits=$(echo "$git_log" | sed 's/^[a-f0-9]* /- /')

	local agent_model
	agent_model=$(gh config get gh-assistant.pr.model 2>/dev/null || true)

	local output
	# Generate PR content using assistant run
	output=$(
		gum spin --title "Generating GitHub pull request..." -- \
			"$_gh_assistant_source_dir/scripts/gh_cmd.sh" assist "$agent_model" < <(
				GIT_DIFF="$git_diff" GIT_DIFF_STAT="$git_diff_stat" GIT_LOG="$git_log" GIT_COMMITS="$git_commits" \
					"$_gh_assistant_source_dir/scripts/gh_cmd.sh" render "$template_file"

			)
	)

	# Validate we got PR content
	if [[ -z "$output" ]]; then
		gum log --level warn "AI generation failed. Aborting."
		return 1
	fi

	local pr_title
	# Parse title from output
	if ! pr_title=$(_get_pr_title "$output"); then
		return 1
	fi

	local pr_body
	# Parse body from output
	pr_body=$(_get_pr_body "$output")

	# Create PR with AI-generated content
	gum spin --title "Creating GitHub pull request..." --show-output -- \
		gh pr create --title "$pr_title" --body "$pr_body" "${clean_args[@]}"
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

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_assistant_source_dir/templates/gh_pr_review.tmpl"

	local gh_pr_number
	# Resolve PR number from arguments or auto-detect from current branch
	gh_pr_number=$(_get_pr_number "${args[@]}")
	if [[ -z "$gh_pr_number" ]]; then
		gum log --level error "No PR number provided and could not detect PR for current branch"
		gum log --level info "Usage: gh assistant pr review <PR_NUMBER> [OPTIONS]"
		return 1
	fi

	# Filter out assistant-managed arguments and the PR number
	local filtered_output
	filtered_output=$(_filter_gh_pr_review_args "${args[@]}")
	IFS=$'\n' read -rd '' -a clean_args <<<"$filtered_output" || true

	# Remove PR number from clean_args (already passed explicitly)
	local tmp_args=()
	for arg in "${clean_args[@]}"; do
		[[ "$arg" == "$gh_pr_number" ]] || tmp_args+=("$arg")
	done
	clean_args=("${tmp_args[@]}")

	# Get PR diff using gh cli (--patch for full patch format)
	local git_diff
	if ! git_diff=$(gum spin --title "Fetching GitHub pull request diff..." -- \
		gh pr diff "$gh_pr_number" --patch 2>/dev/null) || [[ -z "$git_diff" ]]; then
		gum log --level error "Failed to get diff for PR #$gh_pr_number"
		return 1
	fi

	local git_diff_stat
	git_diff_stat=$(echo "$git_diff" | git apply --stat 2>/dev/null || true)

	local git_commits
	git_commits=$(gum spin --title "Fetching GitHub pull request commits..." -- \
		gh pr view "$gh_pr_number" --json commits -q '.commits[] | "- " + .messageHeadline')

	local git_branch
	git_branch=$(gum spin --title "Fetching GitHub pull request branch..." -- \
		gh pr view "$gh_pr_number" --json headRefName -q '.headRefName')

	local agent_model
	agent_model=$(gh config get gh-assistant.pr.model 2>/dev/null || true)

	local pr_body
	# Generate review content using assistant run
	pr_body=$(
		gum spin --title "Generating GitHub pull request review..." -- \
			"$_gh_assistant_source_dir/scripts/gh_cmd.sh" assist "$agent_model" < <(
				GIT_DIFF="$git_diff" GIT_DIFF_STAT="$git_diff_stat" GIT_COMMITS="$git_commits" GIT_BRANCH="$git_branch" \
					"$_gh_assistant_source_dir/scripts/gh_cmd.sh" render "$template_file"
			)
	)

	# Validate we got review content
	if [[ -z "$pr_body" ]]; then
		gum log --level error "Failed to generate review. Aborting."
		return 1
	fi

	# Submit review with AI-generated content
	gum spin --title "Creating GitHub pull request review..." --show-output -- \
		gh pr review "$gh_pr_number" --body "$pr_body" "${clean_args[@]}"
}

# PR help function
#
# Displays comprehensive help information for all PR subcommands
# including usage examples and available options.
_show_pr_help() {
	cat <<'EOF'
gh assistant pr - Pull request commands with AI assistance

USAGE:
    gh assistant pr create [GH_PR_CREATE_OPTIONS]
    gh assistant pr review [PR_NUMBER] [GH_PR_REVIEW_OPTIONS]

DESCRIPTION:
    Creates and reviews GitHub pull requests with AI-generated content.

COMMANDS:
    create      Create PRs with AI-generated titles and descriptions
    review      Review PRs with AI-generated feedback

SEE ALSO:
    gh assistant pr create --help    # Full list of gh pr create options
    gh assistant pr review --help    # Full list of gh pr review options
EOF
}

# PR subcommand handler
#
# Routes PR subcommands (create, review) to their appropriate
# handler functions. Shows help for unknown commands.
#
# Usage: _gh_pr <subcommand> [OPTIONS]
# Subcommands: create, review, help
_gh_pr() {
	local subcommand="${1:-}"
	shift || true

	case $subcommand in
	create)
		_gh_pr_create "$@"
		;;
	review)
		_gh_pr_review "$@"
		;;
	--help | -h | help | "")
		_show_pr_help
		;;
	*)
		gum log --level error "Unknown pr command '$subcommand'"
		gum log --level info "Available commands: create, review"
		gum log --level info "Run 'gh assistant pr --help' for usage information"
		exit 1
		;;
	esac
}
