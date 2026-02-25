#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# PR-related functions for gh-ai

# Parse PR create arguments in a single pass
#
# Extracts the --base branch value and passthrough args for gh pr create
# via namerefs. --base passes through AND is captured for git diff.
# AI-managed flags (--title, --body, --body-file, --template, --fill*) are stripped.
#
# Example: _parse_pr_create_args base args --base develop --draft
_parse_pr_create_args() {
	local -n git_base_branch_ref="$1"
	local -n gh_pr_args_ref="$2"
	shift 2

	local args=("$@")
	local skip_next=false
	local i=0

	while [[ $i -lt ${#args[@]} ]]; do
		if [ "$skip_next" = true ]; then
			skip_next=false
			((++i))
			continue
		fi

		case "${args[$i]}" in
		--base | -B)
			git_base_branch_ref="${args[$((i + 1))]}"
			gh_pr_args_ref+=("${args[$i]}" "${args[$((i + 1))]}")
			skip_next=true
			;;
		--base=*)
			git_base_branch_ref="${args[$i]#--base=}"
			gh_pr_args_ref+=("${args[$i]}")
			;;
		--title | -t | --body | -b | --body-file | -F | --template | -T)
			skip_next=true
			;;
		--title=* | --body=* | --body-file=* | --template=*) ;;
		--fill | --fill-first | --fill-verbose) ;;
		*)
			gh_pr_args_ref+=("${args[$i]}")
			;;
		esac
		((++i))
	done
}

# PR create help function
#
# Displays help information for the PR create command
# including usage examples and available options.
_show_pr_create_help() {
	cat <<'EOF'
gh ai pr create - Create PRs with AI-generated titles and descriptions

USAGE:
    gh ai pr create [OPTIONS]

DESCRIPTION:
    Creates a GitHub pull request with an AI-generated title and description
    based on the diff and commit history between the current and base branch.

PASSTHROUGH FLAGS:
    All flags are passed directly to gh pr create.
    See gh pr create --help for the full list.

EXAMPLES:
    gh ai pr create
    gh ai pr create --draft
    gh ai pr create --draft --base develop
EOF
}

# PR Create implementation
#
# Creates a GitHub PR with an AI-generated title and description.
# Renders a prompt template with git diff and commit context,
# sends it to the AI provider, and parses the response.
#
# Usage: _gh_pr_create [GH_PR_CREATE_OPTIONS]
_gh_pr_create() {
	case "${1:-}" in
	--help | -h | help)
		_show_pr_create_help
		return 0
		;;
	esac

	local args=("$@")

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_ai_source_dir/templates/gh_pr_create.tmpl"

	local git_base_branch=""
	local gh_pr_args=()
	_parse_pr_create_args git_base_branch gh_pr_args "${args[@]}"

	local git_head_branch
	git_head_branch=$(git rev-parse --abbrev-ref HEAD)

	# Fall back to default base branch if --base not provided
	if [[ -z "$git_base_branch" ]]; then
		git_base_branch=$(git rev-parse --abbrev-ref origin/HEAD 2>/dev/null | sed 's|origin/||' ||
			gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null || echo "main")
	fi

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
	gh pr create --title "$gh_pr_title" --body "$gh_pr_body" "${gh_pr_args[@]}"
}

# Parse PR explain arguments in a single pass
#
# Extracts the PR number (first numeric arg, with auto-detect fallback),
# output mode (--comment or --edit), and passthrough args via namerefs.
#
# Example: _parse_pr_explain_args num mode 42 --comment
_parse_pr_explain_args() {
	local -n gh_pr_number_ref="$1"
	local -n gh_pr_output_mode_ref="$2"
	shift 2

	local args=("$@")
	local i=0

	while [[ $i -lt ${#args[@]} ]]; do
		case "${args[$i]}" in
		--comment)
			gh_pr_output_mode_ref="comment"
			;;
		--edit)
			gh_pr_output_mode_ref="edit"
			;;
		*)
			if [[ -z "$gh_pr_number_ref" && "${args[$i]}" =~ ^[0-9]+$ ]]; then
				gh_pr_number_ref="${args[$i]}"
			fi
			;;
		esac
		((++i))
	done

	# Auto-detect PR number from current branch if not found in args
	if [[ -z "$gh_pr_number_ref" ]]; then
		gh_pr_number_ref=$(gh pr view --json number -q '.number' 2>/dev/null || true)
	fi
}

# Parse PR review arguments in a single pass
#
# Extracts the PR number (first numeric arg, with auto-detect fallback)
# and passthrough args for gh pr review via namerefs.
# AI-managed flags (--body, --body-file) and the PR number are stripped.
#
# Example: _parse_pr_review_args num args 42 --approve
_parse_pr_review_args() {
	local -n gh_pr_number_ref="$1"
	local -n gh_pr_args_ref="$2"
	shift 2

	local args=("$@")
	local skip_next=false
	local i=0

	while [[ $i -lt ${#args[@]} ]]; do
		if [ "$skip_next" = true ]; then
			skip_next=false
			((++i))
			continue
		fi

		case "${args[$i]}" in
		--body | -b | --body-file | -F)
			skip_next=true
			;;
		--body=* | --body-file=*) ;;
		*)
			if [[ -z "$gh_pr_number_ref" && "${args[$i]}" =~ ^[0-9]+$ ]]; then
				gh_pr_number_ref="${args[$i]}"
			else
				gh_pr_args_ref+=("${args[$i]}")
			fi
			;;
		esac
		((++i))
	done

	# Auto-detect PR number from current branch if not found in args
	if [[ -z "$gh_pr_number_ref" ]]; then
		gh_pr_number_ref=$(gh pr view --json number -q '.number' 2>/dev/null || true)
	fi
}

# PR review help function
#
# Displays help information for the PR review command
# including usage examples and available options.
_show_pr_review_help() {
	cat <<'EOF'
gh ai pr review - Review PRs with AI-generated feedback

USAGE:
    gh ai pr review [PR_NUMBER] [OPTIONS]

DESCRIPTION:
    Submits a GitHub PR review with AI-generated feedback based on the
    diff and commit history. Auto-detects PR from the current branch
    if no number is provided.

PASSTHROUGH FLAGS:
    All flags are passed directly to gh pr review.
    See gh pr review --help for the full list.

EXAMPLES:
    gh ai pr review 42
    gh ai pr review 42 --approve
    gh ai pr review              # auto-detect PR from current branch
EOF
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
	case "${1:-}" in
	--help | -h | help)
		_show_pr_review_help
		return 0
		;;
	esac

	local args=("$@")

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_ai_source_dir/templates/gh_pr_review.tmpl"

	local gh_pr_number=""
	local gh_pr_args=()
	_parse_pr_review_args gh_pr_number gh_pr_args "${args[@]}"

	if [[ -z "$gh_pr_number" ]]; then
		gum log --level error "No PR number provided and could not detect PR for current branch"
		gum log --level info "Usage: gh ai pr review <PR_NUMBER> [OPTIONS]"
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
	gh pr review "$gh_pr_number" --body "$gh_pr_body" "${gh_pr_args[@]}"
}

# PR explain help function
#
# Displays help information for the PR explain command
# including usage examples and available options.
_show_pr_explain_help() {
	cat <<'EOF'
gh ai pr explain - Generate a plain-language explanation of a PR

USAGE:
    gh ai pr explain [PR_NUMBER] [--comment | --edit]

DESCRIPTION:
    Generates a plain-language explanation of what a pull request does.
    By default prints to stdout. Auto-detects PR from the current branch
    if no number is provided.

FLAGS:
        --comment   Post the explanation as a PR comment
        --edit      Replace the PR description with the explanation

EXAMPLES:
    gh ai pr explain 42              # print to stdout
    gh ai pr explain                 # auto-detect PR from current branch
    gh ai pr explain 42 --comment    # post as PR comment
    gh ai pr explain 42 --edit       # replace PR description
EOF
}

# PR Explain implementation
#
# Generates a plain-language explanation of what a PR does.
# By default prints to stdout; supports --comment and --edit output modes.
#
# Usage: _gh_pr_explain [PR_NUMBER] [--comment | --edit]
_gh_pr_explain() {
	case "${1:-}" in
	--help | -h | help)
		_show_pr_explain_help
		return 0
		;;
	esac

	local args=("$@")

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_ai_source_dir/templates/gh_pr_explain.tmpl"

	local gh_pr_number=""
	local gh_pr_output_mode=""
	_parse_pr_explain_args gh_pr_number gh_pr_output_mode "${args[@]}"

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

	# Output based on mode
	case "$gh_pr_output_mode" in
	comment)
		gh pr comment "$gh_pr_number" --body "$output"
		;;
	edit)
		gh pr edit "$gh_pr_number" --body "$output"
		;;
	*)
		printf '%s\n' "$output"
		;;
	esac
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
