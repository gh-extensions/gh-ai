#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# PR-related functions for gh-ai

# Resolve PR number from arguments or current branch
#
# First looks for a numeric argument in the provided args.
# Falls back to auto-detecting the PR for the current branch via gh pr view.
# Returns the PR number or empty string if none found.
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

	local pr_number
	pr_number=$(gh pr view --json number -q '.number' 2>/dev/null || true)
	# Fall back to auto-detecting PR for current branch
	if [[ -n "$pr_number" ]]; then
		echo "$pr_number"
	fi
}

# Filter out flags managed by gh-ai from pr create arguments
#
# Removes title, body, template, and fill flags (and their values) since
# the PR content is AI-generated. All other flags pass through.
_filter_pr_create_args() {
	local filtered=()
	local skip_next=false
	local arg

	for arg in "$@"; do
		if [ "$skip_next" = true ]; then
			skip_next=false
			continue
		fi

		case "$arg" in
		--title | -t | --body | -b | --body-file | -F | --template | -T)
			skip_next=true
			;;
		--title=* | --body=* | --body-file=* | --template=*) ;;
		--fill | --fill-first | --fill-verbose) ;;
		*)
			filtered+=("$arg")
			;;
		esac
	done

	[[ ${#filtered[@]} -gt 0 ]] && printf '%s\n' "${filtered[@]}" || true
}

# PR Create implementation
#
# Creates a GitHub PR with an AI-generated title and description.
# Renders a prompt template with git diff and commit context,
# sends it to the AI provider, and parses the response.
#
# Usage: _gh_pr_create [GH_PR_CREATE_OPTIONS]
_gh_pr_create() {
	local args=("$@")
	local clean_args

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_ai_source_dir/templates/gh_pr_create.tmpl"

	local filtered_args
	filtered_args=$(_filter_pr_create_args "${args[@]}")
	if [[ -n "$filtered_args" ]]; then
		IFS=$'\n' read -rd '' -a clean_args <<<"$filtered_args" || true
	else
		clean_args=()
	fi

	local git_head_branch
	git_head_branch=$(git rev-parse --abbrev-ref HEAD)

	local git_base_branch
	git_base_branch=$(git rev-parse --abbrev-ref origin/HEAD 2>/dev/null | sed 's|origin/||' ||
		gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null || echo "main")

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
	git_diff=$(git diff "origin/$git_base_branch"..."$git_head_branch" 2>/dev/null || true)
	if [[ -z "$git_diff" ]]; then
		# Fallback: try without origin prefix
		git_diff=$(git diff "$git_base_branch"..."$git_head_branch" 2>/dev/null || true)
	fi
	if [[ -z "$git_diff" ]]; then
		gum log --level error "Failed to get diff between $git_base_branch and $git_head_branch"
		return 1
	fi

	local git_diff_stat
	# shellcheck disable=SC2140
	git_diff_stat=$(git diff "origin/$git_base_branch"..."$git_head_branch" --stat 2>/dev/null ||
		git diff "$git_base_branch"..."$git_head_branch" --stat 2>/dev/null || true)

	local git_log
	# shellcheck disable=SC2140
	git_log=$(git log --oneline "origin/$git_base_branch".."$git_head_branch" 2>/dev/null ||
		git log --oneline "$git_base_branch".."$git_head_branch" 2>/dev/null || true)

	local git_log_oneline
	# shellcheck disable=SC2001
	git_log_oneline=$(echo "$git_log" | sed 's/^[a-f0-9]* /- /')

	local agent_model
	agent_model=$(gh config get gh-ai.pr.model 2>/dev/null || true)

	local output
	# Generate PR content using assistant run
	output=$(
		gum spin --title "Generating GitHub pull request..." -- \
			"$_gh_ai_source_dir/scripts/gh_cmd.sh" assist "$agent_model" < <(
				GIT_DIFF="$git_diff" GIT_DIFF_STAT="$git_diff_stat" GIT_LOG="$git_log" GIT_COMMITS="$git_log_oneline" \
					"$_gh_ai_source_dir/scripts/gh_cmd.sh" render "$template_file"
			)
	)

	# Validate we got PR content
	if [[ -z "$output" ]]; then
		gum log --level error "Failed to generate pull request content"
		gum log --level info "Run with DEBUG=1 for detailed diagnostics"
		return 1
	fi

	local gh_pr_title
	# Parse title from output
	if ! gh_pr_title=$(_get_title "$output"); then
		gum log --level error "Failed to extract title from AI content"
		return 1
	fi

	local gh_pr_body
	# Parse body from output
	gh_pr_body=$(_get_body "$output")

	# Validate we got body content
	if [[ -z "$gh_pr_body" ]]; then
		gum log --level error "Failed to extract body from AI content"
		return 1
	fi

	# Create PR with AI-generated content
	gh pr create --title "$gh_pr_title" --body "$gh_pr_body" "${clean_args[@]}"
}

# Filter out flags managed by gh-ai from pr review arguments
#
# Removes body flags (and their values) and the PR number since
# the review content is AI-generated. All other flags pass through.
_filter_pr_review_args() {
	local pr_number="$1"
	shift

	local filtered=()
	local skip_next=false
	local arg

	for arg in "$@"; do
		if [ "$skip_next" = true ]; then
			skip_next=false
			continue
		fi

		case "$arg" in
		--body | -b | --body-file | -F)
			skip_next=true
			;;
		--body=* | --body-file=*) ;;
		"$pr_number") ;;
		*)
			filtered+=("$arg")
			;;
		esac
	done

	[[ ${#filtered[@]} -gt 0 ]] && printf '%s\n' "${filtered[@]}" || true
}

# PR Review implementation
#
# Submits a GitHub PR review with AI-generated feedback.
# Renders a prompt template with the PR diff and commit context,
# sends it to the AI provider, and submits the response as a review.
# Auto-detects PR number from current branch if not provided.
#
# Usage: _gh_pr_review [PR_NUMBER] [GH_PR_REVIEW_OPTIONS]
_gh_pr_review() {
	local args=("$@")
	local clean_args

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_ai_source_dir/templates/gh_pr_review.tmpl"

	local gh_pr_number
	# Resolve PR number from arguments or auto-detect from current branch
	gh_pr_number=$(_get_pr_number "${args[@]}")
	if [[ -z "$gh_pr_number" ]]; then
		gum log --level error "No PR number provided and could not detect PR for current branch"
		gum log --level info "Usage: gh ai pr review <PR_NUMBER> [OPTIONS]"
		return 1
	fi

	local filtered_args
	filtered_args=$(_filter_pr_review_args "$gh_pr_number" "${args[@]}")
	if [[ -n "$filtered_args" ]]; then
		IFS=$'\n' read -rd '' -a clean_args <<<"$filtered_args" || true
	else
		clean_args=()
	fi

	# Get PR diff using gh cli (--patch for full patch format)
	local git_diff
	git_diff=$(gum spin --title "Fetching GitHub pull request diff..." -- \
		gh pr diff "$gh_pr_number" --patch || true)
	if [[ -z "$git_diff" ]]; then
		gum log --level error "Failed to get diff for PR #$gh_pr_number"
		return 1
	fi

	local git_diff_stat
	git_diff_stat=$(echo "$git_diff" | git apply --stat 2>/dev/null || true)

	local git_commit_list
	git_commit_list=$(gum spin --title "Fetching GitHub pull request commits..." -- \
		gh pr view "$gh_pr_number" --json commits -q '.commits[] | "- " + .messageHeadline' || true)

	local git_branch
	git_branch=$(gum spin --title "Fetching GitHub pull request branch..." -- \
		gh pr view "$gh_pr_number" --json headRefName -q '.headRefName' || true)

	local agent_model
	agent_model=$(gh config get gh-ai.pr.model 2>/dev/null || true)

	local gh_pr_body
	# Generate review content using assistant run
	gh_pr_body=$(
		gum spin --title "Generating GitHub pull request review..." -- \
			"$_gh_ai_source_dir/scripts/gh_cmd.sh" assist "$agent_model" < <(
				GIT_DIFF="$git_diff" GIT_DIFF_STAT="$git_diff_stat" GIT_COMMITS="$git_commit_list" GIT_BRANCH="$git_branch" \
					"$_gh_ai_source_dir/scripts/gh_cmd.sh" render "$template_file"
			)
	)

	# Validate we got review content
	if [[ -z "$gh_pr_body" ]]; then
		gum log --level error "Failed to generate review content"
		gum log --level info "Run with DEBUG=1 for detailed diagnostics"
		return 1
	fi

	# Submit review with AI-generated content
	gh pr review "$gh_pr_number" --body "$gh_pr_body" "${clean_args[@]}"
}

# PR Explain implementation
#
# Generates a plain-language explanation of what a PR does.
# By default prints to stdout; supports --comment and --edit output modes.
#
# Usage: _gh_pr_explain [PR_NUMBER] [--comment | --edit]
_gh_pr_explain() {
	local args=("$@")

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_ai_source_dir/templates/gh_pr_explain.tmpl"

	local gh_pr_number
	# Resolve PR number from arguments or auto-detect from current branch
	gh_pr_number=$(_get_pr_number "${args[@]}")
	if [[ -z "$gh_pr_number" ]]; then
		gum log --level error "No PR number provided and could not detect PR for current branch"
		gum log --level info "Usage: gh ai pr explain [PR_NUMBER] [--comment | --edit]"
		return 1
	fi

	# Get PR diff using gh cli (--patch for full patch format)
	local git_diff
	git_diff=$(gum spin --title "Fetching GitHub pull request diff..." -- \
		gh pr diff "$gh_pr_number" --patch || true)
	if [[ -z "$git_diff" ]]; then
		gum log --level error "Failed to get diff for PR #$gh_pr_number"
		return 1
	fi

	local git_diff_stat
	git_diff_stat=$(echo "$git_diff" | git apply --stat 2>/dev/null || true)

	local git_commit_list
	git_commit_list=$(gum spin --title "Fetching GitHub pull request commits..." -- \
		gh pr view "$gh_pr_number" --json commits -q '.commits[] | "- " + .messageHeadline' || true)

	local git_branch
	git_branch=$(gum spin --title "Fetching GitHub pull request branch..." -- \
		gh pr view "$gh_pr_number" --json headRefName -q '.headRefName' || true)

	# Fetch PR title and body
	local gh_pr_title
	gh_pr_title=$(gh pr view "$gh_pr_number" --json title -q '.title' 2>/dev/null || true)

	local gh_pr_body
	gh_pr_body=$(gh pr view "$gh_pr_number" --json body -q '.body' 2>/dev/null || true)

	local agent_model
	agent_model=$(gh config get gh-ai.pr.model 2>/dev/null || true)

	local output
	# Generate explanation using assistant run
	output=$(
		gum spin --title "Generating GitHub pull request explanation..." -- \
			"$_gh_ai_source_dir/scripts/gh_cmd.sh" assist "$agent_model" < <(
				PR_TITLE="$gh_pr_title" PR_BODY="$gh_pr_body" GIT_DIFF="$git_diff" GIT_DIFF_STAT="$git_diff_stat" \
					GIT_COMMITS="$git_commit_list" GIT_BRANCH="$git_branch" \
					"$_gh_ai_source_dir/scripts/gh_cmd.sh" render "$template_file"
			)
	)

	# Validate we got explanation content
	if [[ -z "$output" ]]; then
		gum log --level error "Failed to generate explanation"
		gum log --level info "Run with DEBUG=1 for detailed diagnostics"
		return 1
	fi

	# Output based on flags
	local arg
	for arg in "${args[@]}"; do
		case "$arg" in
		--comment)
			gh pr comment "$gh_pr_number" --body "$output"
			return 0
			;;
		--edit)
			gh pr edit "$gh_pr_number" --body "$output"
			return 0
			;;
		esac
	done

	printf '%s\n' "$output"
}

# PR help function
#
# Displays comprehensive help information for all PR subcommands
# including usage examples and available options.
_show_pr_help() {
	cat <<'EOF'
gh ai pr - Pull request commands with AI assistance

USAGE:
    gh ai pr create [GH_PR_CREATE_OPTIONS]
    gh ai pr review [PR_NUMBER] [GH_PR_REVIEW_OPTIONS]
    gh ai pr explain [PR_NUMBER] [--comment | --edit]

DESCRIPTION:
    Creates, reviews, and explains GitHub pull requests with AI-generated content.

COMMANDS:
    create      Create PRs with AI-generated titles and descriptions
    review      Review PRs with AI-generated feedback
    explain     Generate a plain-language explanation of a PR

SEE ALSO:
    gh ai pr create --help     # Full list of gh pr create options
    gh ai pr review --help     # Full list of gh pr review options
    gh ai pr explain --help    # PR explain usage
EOF
}

# PR subcommand handler
#
# Routes PR subcommands to their appropriate handler functions.
# Shows help for unknown commands.
#
# Usage: _gh_pr <subcommand> [OPTIONS]
# Subcommands: create, review, explain, help
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
	explain)
		_gh_pr_explain "$@"
		;;
	--help | -h | help | "")
		_show_pr_help
		;;
	*)
		gum log --level error "Unknown pr command '$subcommand'"
		gum log --level info "Available commands: create, review, explain"
		gum log --level info "Run 'gh ai pr --help' for usage information"
		exit 1
		;;
	esac
}
