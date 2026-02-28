#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# PR-related functions for gh-ai

# Parse PR create arguments (before -- separator)
#
# Extracts -d/--description and -B/--base values. Unknown flags produce
# an error with a hint to use --.
#
# Example: _parse_pr_create_args base desc -B develop -d "context"
_parse_pr_create_args() {
	local -n git_base_branch_ref="$1"
	local -n gh_pr_description_ref="$2"
	shift 2

	local raw_args=("$@")
	local skip_next=false
	local i=0

	while [[ $i -lt ${#raw_args[@]} ]]; do
		if [ "$skip_next" = true ]; then
			skip_next=false
			((++i))
			continue
		fi

		case "${raw_args[$i]}" in
		--description | -d)
			if ((i + 1 >= ${#raw_args[@]})); then
				gum log --level error "${raw_args[$i]} requires a value"
				return 1
			fi
			gh_pr_description_ref="${raw_args[$((i + 1))]}"
			skip_next=true
			;;
		--description=*)
			# shellcheck disable=SC2034 # nameref: set by caller
			gh_pr_description_ref="${raw_args[$i]#--description=}"
			;;
		--base | -B)
			if ((i + 1 >= ${#raw_args[@]})); then
				gum log --level error "${raw_args[$i]} requires a value"
				return 1
			fi
			# shellcheck disable=SC2034 # nameref: set by caller
			git_base_branch_ref="${raw_args[$((i + 1))]}"
			skip_next=true
			;;
		--base=*)
			# shellcheck disable=SC2034 # nameref: set by caller
			git_base_branch_ref="${raw_args[$i]#--base=}"
			;;
		-*)
			gum log --level error "unknown flag '${raw_args[$i]}' (use -- to pass flags to gh pr create)"
			return 1
			;;
		*)
			gum log --level error "unexpected argument '${raw_args[$i]}'"
			return 1
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
    gh ai pr create [-d <DESCRIPTION>] [-B <BASE>] [-- GH_PR_CREATE_OPTIONS]

DESCRIPTION:
    Creates a GitHub pull request with an AI-generated title and description
    based on the diff and commit history between the current and base branch.
    Options after -- are passed directly to gh pr create.

FLAGS:
    -d, --description string   Optional guidance for the AI (e.g. focus area)
    -B, --base string          Base branch for the pull request

EXAMPLES:
    gh ai pr create
    gh ai pr create -- --draft
    gh ai pr create -B develop -- --draft
    gh ai pr create -d "focus on the security changes"
EOF
}

# PR Create implementation
#
# Creates a GitHub PR with an AI-generated title and description.
# Renders a prompt template with git diff and commit context,
# sends it to the AI provider, and parses the response.
#
# Usage: _gh_pr_create [-d <DESCRIPTION>] [-B <BASE>] [-- OPTIONS]
_gh_pr_create() {
	case "${1:-}" in
	--help | -h | help)
		_show_pr_create_help
		return 0
		;;
	esac

	local ai_args=()
	local passthrough=()
	_split_on_separator ai_args passthrough "$@"

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_ai_source_dir/templates/gh_pr_create.tmpl"

	local git_base_branch=""
	local gh_pr_description=""
	_parse_pr_create_args git_base_branch gh_pr_description "${ai_args[@]}"

	# Remember whether the user explicitly specified --base so we only
	# forward it to gh pr create when intended (not from fallback defaults).
	local user_specified_base="$git_base_branch"

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
	git_log_oneline=$(printf '%s\n' "$git_log" | sed 's/^[a-f0-9]* /- /')

	local agent_model
	agent_model=$(gh config get gh-ai.pr.model 2>/dev/null || true)

	local output
	# Generate PR content using assistant run
	output=$(
		gum spin --title "Generating GitHub pull request..." -- \
			"$_gh_ai_source_dir/scripts/gh_cmd.sh" ask "$agent_model" < <(
				GIT_DIFF="$git_diff" GIT_DIFF_STAT="$git_diff_stat" GIT_LOG="$git_log" GIT_COMMITS="$git_log_oneline" GH_PR_DESCRIPTION="$gh_pr_description" \
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

	# Inject --base into passthrough only if the user explicitly specified it
	if [[ -n "$user_specified_base" ]]; then
		passthrough=("--base" "$user_specified_base" "${passthrough[@]}")
	fi

	# Create PR with AI-generated content
	gh pr create --title "$gh_pr_title" --body "$gh_pr_body" "${passthrough[@]}"
}

# Parse PR edit arguments (before -- separator)
#
# Extracts the PR number (first numeric arg, with auto-detect fallback)
# and -d/--description value. Unknown flags produce an error with a hint
# to use --.
#
# Example: _parse_pr_edit_args num desc 42 -d "add testing section"
_parse_pr_edit_args() {
	local -n gh_pr_number_ref="$1"
	local -n gh_pr_description_ref="$2"
	shift 2

	local raw_args=("$@")
	local skip_next=false
	local i=0

	while [[ $i -lt ${#raw_args[@]} ]]; do
		if [ "$skip_next" = true ]; then
			skip_next=false
			((++i))
			continue
		fi

		case "${raw_args[$i]}" in
		--description | -d)
			if ((i + 1 >= ${#raw_args[@]})); then
				gum log --level error "${raw_args[$i]} requires a value"
				return 1
			fi
			gh_pr_description_ref="${raw_args[$((i + 1))]}"
			skip_next=true
			;;
		--description=*)
			# shellcheck disable=SC2034 # nameref: set by caller
			gh_pr_description_ref="${raw_args[$i]#--description=}"
			;;
		-*)
			gum log --level error "unknown flag '${raw_args[$i]}' (use -- to pass flags to gh pr edit)"
			return 1
			;;
		*)
			local arg="${raw_args[$i]#\#}"
			if [[ -z "$gh_pr_number_ref" && "$arg" =~ ^[0-9]+$ ]]; then
				gh_pr_number_ref="$arg"
			else
				gum log --level error "unexpected argument '${raw_args[$i]}'"
				return 1
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

# PR edit help function
#
# Displays help information for the PR edit command
# including usage examples and available options.
_show_pr_edit_help() {
	cat <<'EOF'
gh ai pr edit - Edit an existing PR with AI-generated content

USAGE:
    gh ai pr edit [PR_NUMBER] -d <DESCRIPTION> [-- GH_PR_EDIT_OPTIONS]

DESCRIPTION:
    Edits an existing GitHub pull request using AI. Fetches the current PR
    content and diff, applies the requested changes via AI, and updates the
    PR title and body. Auto-detects PR from the current branch if no number
    is provided. Options after -- are passed directly to gh pr edit.

FLAGS:
    -d, --description string   Description of the changes to make (required)

EXAMPLES:
    gh ai pr edit 42 -d "add testing section"
    gh ai pr edit 42 -d "fix summary" -- --add-label bug
    gh ai pr edit -d "improve description"   # auto-detect PR from current branch
EOF
}

# PR Edit implementation
#
# Edits an existing GitHub PR with AI-generated content.
# Fetches the current PR content and diff, renders a prompt template
# with the description and PR context, sends it to the AI provider,
# and updates the PR with the parsed response.
#
# Usage: _gh_pr_edit [NUMBER] -d <DESCRIPTION> [-- OPTIONS]
_gh_pr_edit() {
	case "${1:-}" in
	--help | -h | help)
		_show_pr_edit_help
		return 0
		;;
	esac

	local ai_args=()
	local passthrough=()
	_split_on_separator ai_args passthrough "$@"

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_ai_source_dir/templates/gh_pr_edit.tmpl"

	local gh_pr_number=""
	local gh_pr_description=""
	_parse_pr_edit_args gh_pr_number gh_pr_description "${ai_args[@]}"

	if [[ -z "$gh_pr_number" ]]; then
		gum log --level error "No PR number provided and could not detect PR for current branch"
		gum log --level info "Usage: gh ai pr edit [PR_NUMBER] -d <DESCRIPTION> [-- OPTIONS]"
		return 1
	fi

	if [[ -z "$gh_pr_description" ]]; then
		gum log --level error "No description provided"
		gum log --level info "Usage: gh ai pr edit [PR_NUMBER] -d <DESCRIPTION> [-- OPTIONS]"
		return 1
	fi

	# Fetch PR metadata
	local gh_pr_eval
	gh_pr_eval=$(gum spin --title "Fetching GitHub pull request #$gh_pr_number metadata..." -- \
		gh pr view "$gh_pr_number" --json title,body \
		-q "$(<"$_gh_ai_source_dir/scripts/gh_pr_meta.jq")" || true)
	if [[ -z "$gh_pr_eval" ]]; then
		gum log --level error "Failed to fetch PR #$gh_pr_number"
		return 1
	fi

	local gh_pr_title gh_pr_body
	eval "$gh_pr_eval"

	# Get PR diff using gh cli (--patch for full patch format)
	local git_diff
	git_diff=$(gum spin --title "Fetching GitHub pull request #$gh_pr_number diff..." -- \
		gh pr diff "$gh_pr_number" --patch || true)
	if [[ -z "$git_diff" ]]; then
		gum log --level error "Failed to get diff for PR #$gh_pr_number"
		return 1
	fi

	local git_diff_stat
	git_diff_stat=$(echo "$git_diff" | git apply --stat 2>/dev/null || true)

	local git_commit_list
	git_commit_list=$(gum spin --title "Fetching GitHub pull request #$gh_pr_number commits..." -- \
		gh pr view "$gh_pr_number" --json commits -q '.commits[] | "- " + .messageHeadline' || true)

	local agent_model
	agent_model=$(gh config get gh-ai.pr.model 2>/dev/null || true)

	local output
	# Generate updated PR content using assistant
	output=$(
		gum spin --title "Generating updated GitHub pull request #$gh_pr_number..." -- \
			"$_gh_ai_source_dir/scripts/gh_cmd.sh" ask "$agent_model" < <(
				GH_PR_NUMBER="$gh_pr_number" GH_PR_TITLE="$gh_pr_title" GH_PR_BODY="$gh_pr_body" GIT_DIFF="$git_diff" GIT_DIFF_STAT="$git_diff_stat" GIT_COMMITS="$git_commit_list" GH_PR_DESCRIPTION="$gh_pr_description" \
					"$_gh_ai_source_dir/scripts/gh_cmd.sh" render "$template_file"
			)
	)

	# Validate we got PR content
	if [[ -z "$output" ]]; then
		gum log --level error "Failed to generate updated pull request content"
		gum log --level info "Run with DEBUG=1 for detailed diagnostics"
		return 1
	fi

	local gh_pr_new_title
	# Parse title from output
	if ! gh_pr_new_title=$(_get_title "$output"); then
		gum log --level error "Failed to extract title from AI content"
		return 1
	fi

	local gh_pr_new_body
	# Parse body from output
	gh_pr_new_body=$(_get_body "$output")

	# Edit PR with AI-generated content
	gh pr edit "$gh_pr_number" --title "$gh_pr_new_title" --body "$gh_pr_new_body" "${passthrough[@]}"
}

# Parse PR explain arguments
#
# Extracts the PR number (first numeric arg, with auto-detect fallback)
# and output mode (--comment or --edit) via namerefs.
#
# Example: _parse_pr_explain_args num mode 42 --comment
_parse_pr_explain_args() {
	local -n gh_pr_number_ref="$1"
	local -n gh_pr_output_mode_ref="$2"
	shift 2

	local raw_args=("$@")
	local i=0

	while [[ $i -lt ${#raw_args[@]} ]]; do
		case "${raw_args[$i]}" in
		--)
			break
			;;
		--comment)
			gh_pr_output_mode_ref="comment"
			;;
		--edit)
			# shellcheck disable=SC2034 # nameref: set by caller
			gh_pr_output_mode_ref="edit"
			;;
		-*)
			gum log --level error "unknown flag '${raw_args[$i]}'"
			return 1
			;;
		*)
			local arg="${raw_args[$i]#\#}"
			if [[ -z "$gh_pr_number_ref" && "$arg" =~ ^[0-9]+$ ]]; then
				gh_pr_number_ref="$arg"
			else
				gum log --level error "unexpected argument '${raw_args[$i]}'"
				return 1
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

# Parse PR review arguments (before -- separator)
#
# Extracts the PR number (first numeric arg, with auto-detect fallback)
# and -d/--description value. Unknown flags produce an error with a hint
# to use --.
#
# Example: _parse_pr_review_args num desc 42 -d "focus on security"
_parse_pr_review_args() {
	local -n gh_pr_number_ref="$1"
	# shellcheck disable=SC2178 # bash nameref: looks like scalar redefining array, but it's a reference
	local -n gh_pr_description_ref="$2"
	shift 2

	local raw_args=("$@")
	local skip_next=false
	local i=0

	while [[ $i -lt ${#raw_args[@]} ]]; do
		if [ "$skip_next" = true ]; then
			skip_next=false
			((++i))
			continue
		fi

		case "${raw_args[$i]}" in
		--description | -d)
			if ((i + 1 >= ${#raw_args[@]})); then
				gum log --level error "${raw_args[$i]} requires a value"
				return 1
			fi
			gh_pr_description_ref="${raw_args[$((i + 1))]}"
			skip_next=true
			;;
		--description=*)
			# shellcheck disable=SC2034 # nameref: set by caller
			gh_pr_description_ref="${raw_args[$i]#--description=}"
			;;
		-*)
			gum log --level error "unknown flag '${raw_args[$i]}' (use -- to pass flags to gh pr review)"
			return 1
			;;
		*)
			local arg="${raw_args[$i]#\#}"
			if [[ -z "$gh_pr_number_ref" && "$arg" =~ ^[0-9]+$ ]]; then
				gh_pr_number_ref="$arg"
			else
				gum log --level error "unexpected argument '${raw_args[$i]}'"
				return 1
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
    gh ai pr review [PR_NUMBER] [-d <DESCRIPTION>] [-- GH_PR_REVIEW_OPTIONS]

DESCRIPTION:
    Submits a GitHub PR review with AI-generated feedback based on the
    diff and commit history. Auto-detects PR from the current branch
    if no number is provided. Options after -- are passed directly to
    gh pr review.

FLAGS:
    -d, --description <TEXT>    Additional context for AI review generation

EXAMPLES:
    gh ai pr review 42
    gh ai pr review 42 -- --approve
    gh ai pr review -d "focus on security"
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
# Usage: _gh_pr_review [NUMBER] [-d <DESCRIPTION>] [-- OPTIONS]
_gh_pr_review() {
	case "${1:-}" in
	--help | -h | help)
		_show_pr_review_help
		return 0
		;;
	esac

	local ai_args=()
	local passthrough=()
	_split_on_separator ai_args passthrough "$@"

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_ai_source_dir/templates/gh_pr_review.tmpl"

	local gh_pr_number=""
	local gh_pr_description=""
	_parse_pr_review_args gh_pr_number gh_pr_description "${ai_args[@]}"

	if [[ -z "$gh_pr_number" ]]; then
		gum log --level error "No PR number provided and could not detect PR for current branch"
		gum log --level info "Usage: gh ai pr review <PR_NUMBER> [-- OPTIONS]"
		return 1
	fi

	# Get PR diff using gh cli (--patch for full patch format)
	local git_diff
	git_diff=$(gum spin --title "Fetching GitHub pull request #$gh_pr_number diff..." -- \
		gh pr diff "$gh_pr_number" --patch || true)
	if [[ -z "$git_diff" ]]; then
		gum log --level error "Failed to get diff for PR #$gh_pr_number"
		return 1
	fi

	local git_diff_stat
	git_diff_stat=$(echo "$git_diff" | git apply --stat 2>/dev/null || true)

	local git_commit_list
	git_commit_list=$(gum spin --title "Fetching GitHub pull request #$gh_pr_number commits..." -- \
		gh pr view "$gh_pr_number" --json commits -q '.commits[] | "- " + .messageHeadline' || true)

	local git_branch
	git_branch=$(gum spin --title "Fetching GitHub pull request #$gh_pr_number branch..." -- \
		gh pr view "$gh_pr_number" --json headRefName -q '.headRefName' || true)

	local agent_model
	agent_model=$(gh config get gh-ai.pr.model 2>/dev/null || true)

	local gh_pr_description_context=""
	if [[ -n "$gh_pr_description" ]]; then
		gh_pr_description_context="<description>$gh_pr_description</description>"
	fi

	local gh_pr_body
	# Generate review content using assistant run
	gh_pr_body=$(
		gum spin --title "Generating GitHub pull request #$gh_pr_number review..." -- \
			"$_gh_ai_source_dir/scripts/gh_cmd.sh" ask "$agent_model" < <(
				GIT_DIFF="$git_diff" GIT_DIFF_STAT="$git_diff_stat" GIT_COMMITS="$git_commit_list" GIT_BRANCH="$git_branch" GH_PR_REVIEW_DESCRIPTION="$gh_pr_description_context" \
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
	gh pr review "$gh_pr_number" --body "$gh_pr_body" "${passthrough[@]}"
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
# Usage: _gh_pr_explain [NUMBER] [--comment | --edit]
_gh_pr_explain() {
	case "${1:-}" in
	--help | -h | help)
		_show_pr_explain_help
		return 0
		;;
	esac

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_ai_source_dir/templates/gh_pr_explain.tmpl"

	local gh_pr_number=""
	local gh_pr_output_mode=""
	_parse_pr_explain_args gh_pr_number gh_pr_output_mode "$@"

	if [[ -z "$gh_pr_number" ]]; then
		gum log --level error "No PR number provided and could not detect PR for current branch"
		gum log --level info "Usage: gh ai pr explain [PR_NUMBER] [--comment | --edit]"
		return 1
	fi

	# Get PR diff using gh cli (--patch for full patch format)
	local git_diff
	git_diff=$(gum spin --title "Fetching GitHub pull request #$gh_pr_number diff..." -- \
		gh pr diff "$gh_pr_number" --patch || true)
	if [[ -z "$git_diff" ]]; then
		gum log --level error "Failed to get diff for PR #$gh_pr_number"
		return 1
	fi

	local git_diff_stat
	git_diff_stat=$(echo "$git_diff" | git apply --stat 2>/dev/null || true)

	local git_commit_list
	git_commit_list=$(gum spin --title "Fetching GitHub pull request #$gh_pr_number commits..." -- \
		gh pr view "$gh_pr_number" --json commits -q '.commits[] | "- " + .messageHeadline' || true)

	local git_branch
	git_branch=$(gum spin --title "Fetching GitHub pull request #$gh_pr_number branch..." -- \
		gh pr view "$gh_pr_number" --json headRefName -q '.headRefName' || true)

	# Fetch PR title and body
	local gh_pr_eval
	gh_pr_eval=$(gum spin --title "Fetching GitHub pull request #$gh_pr_number metadata..." -- \
		gh pr view "$gh_pr_number" --json title,body \
		-q "$(<"$_gh_ai_source_dir/scripts/gh_pr_meta.jq")" || true)

	local gh_pr_title gh_pr_body
	if [[ -n "$gh_pr_eval" ]]; then
		eval "$gh_pr_eval"
	fi

	local agent_model
	agent_model=$(gh config get gh-ai.pr.model 2>/dev/null || true)

	local output
	# Generate explanation using assistant run
	output=$(
		gum spin --title "Generating GitHub pull request #$gh_pr_number explanation..." -- \
			"$_gh_ai_source_dir/scripts/gh_cmd.sh" ask "$agent_model" < <(
				GH_PR_TITLE="$gh_pr_title" GH_PR_BODY="$gh_pr_body" GIT_DIFF="$git_diff" GIT_DIFF_STAT="$git_diff_stat" \
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

# PR chat help function
#
# Displays help information for the pr chat command.
_show_pr_chat_help() {
	cat <<'EOF'
gh ai pr chat - Open a Claude Code review session for a pull request

USAGE:
    gh ai pr chat <PR_NUMBER>

DESCRIPTION:
    Generates a plain-language explanation of the PR (via gh ai pr explain),
    creates a git worktree on branch pr-N (fast-forwarded to the PR head),
    and opens a Claude Code session seeded with that explanation.
    Re-running the command resumes the previous session.
    The session is opened in discussion mode — Claude will not commit or push changes.

EXAMPLES:
    gh ai pr chat 99
EOF
}

# Parse PR chat arguments
#
# Extracts the PR number (first positional arg, stripping leading #).
# Unknown flags produce an error.
#
# Example: _parse_pr_chat_args num 99
_parse_pr_chat_args() {
	local -n gh_pr_number_ref="$1"
	shift

	local raw_args=("$@")
	local i=0

	while [[ $i -lt ${#raw_args[@]} ]]; do
		case "${raw_args[$i]}" in
		--)
			break
			;;
		-*)
			gum log --level error "unknown flag '${raw_args[$i]}'"
			return 1
			;;
		*)
			local arg="${raw_args[$i]#\#}"
			if [[ -z "$gh_pr_number_ref" && "$arg" =~ ^[0-9]+$ ]]; then
				gh_pr_number_ref="$arg"
			else
				gum log --level error "unexpected argument '${raw_args[$i]}'"
				return 1
			fi
			;;
		esac
		((++i))
	done
}

# PR Chat implementation
#
# Generates a plain-language explanation of the PR, creates a git worktree on
# branch pr-N (synced to the PR head), and opens a Claude Code session seeded
# with the explanation in discussion mode. Re-running resumes the session.
#
# Usage: _gh_pr_chat <PR_NUMBER>
_gh_pr_chat() {
	case "${1:-}" in
	--help | -h | help)
		_show_pr_chat_help
		return 0
		;;
	esac

	local gh_pr_number=""
	_parse_pr_chat_args gh_pr_number "$@"

	if [[ -z "$gh_pr_number" ]]; then
		gum log --level error "No PR number provided"
		gum log --level info "Usage: gh ai pr chat <PR_NUMBER>"
		return 1
	fi

	local repo_name
	_get_repo_name repo_name || return 1

	local git_dir
	_get_git_repo_path git_dir || return 1

	local session_id session_file
	_init_chat_session session_id session_file "$repo_name" "P${gh_pr_number}" "$git_dir"

	local gh_remote_branch
	gh_remote_branch=$(gh pr view "$gh_pr_number" --json headRefName -q '.headRefName' 2>/dev/null || true)
	if [[ -z "$gh_remote_branch" ]]; then
		gum log --level error "Failed to fetch head branch for PR #$gh_pr_number"
		return 1
	fi

	local git_branch="pr-${gh_pr_number}"
	# shellcheck disable=SC2154
	local git_worktree_path="$git_dir/.claude/worktrees/${git_branch}"
	# shellcheck disable=SC2154
	gum spin --title "Setting up Git worktree for GitHub pull request #$gh_pr_number..." -- \
		"$_gh_ai_source_dir/scripts/gh_cmd.sh" worktree-sync "$git_branch" "$git_worktree_path" "$gh_remote_branch" || return 1

	local preamble
	preamble=$(GH_PR_NUMBER="$gh_pr_number" \
		_cmd_render "$_gh_ai_source_dir/templates/gh_pr_chat.tmpl")
	if [[ -z "$preamble" ]]; then
		gum log --level error "Failed to render chat preamble"
		return 1
	fi

	local agent_model
	agent_model=$(gh config get gh-ai.pr.model 2>/dev/null || true)
	if [[ -z "$agent_model" ]]; then
		agent_model=$(gh config get gh-ai.model 2>/dev/null || true)
	fi

	_cmd_chat "$session_file" "$git_branch" "$session_id" "$preamble" "$agent_model" \
		gh ai pr explain "$gh_pr_number"
}

# PR help function
#
# Displays comprehensive help information for all PR subcommands
# including usage examples and available options.
_show_pr_help() {
	cat <<'EOF'
gh ai pr - Pull request commands with AI assistance

USAGE:
    gh ai pr create [-d <DESCRIPTION>] [-B <BASE>] [-- GH_PR_CREATE_OPTIONS]
    gh ai pr edit [PR_NUMBER] -d <DESCRIPTION> [-- GH_PR_EDIT_OPTIONS]
    gh ai pr review [PR_NUMBER] [-d <DESCRIPTION>] [-- GH_PR_REVIEW_OPTIONS]
    gh ai pr explain [PR_NUMBER] [--comment | --edit]
    gh ai pr chat <PR_NUMBER>

DESCRIPTION:
    Creates, edits, reviews, and explains GitHub pull requests with AI-generated content.
    Opens a Claude Code review session seeded with a PR explanation in an isolated worktree.

COMMANDS:
    create      Create PRs with AI-generated titles and descriptions
    edit        Edit an existing PR with AI-generated content
    review      Review PRs with AI-generated feedback
    explain     Generate a plain-language explanation of a PR
    chat        Open a Claude Code review session for a PR

SEE ALSO:
    gh ai pr create --help     # Full list of gh pr create options
    gh ai pr edit --help       # Full list of gh pr edit options
    gh ai pr review --help     # Full list of gh pr review options
    gh ai pr explain --help    # PR explain usage
    gh ai pr chat --help       # PR chat usage
EOF
}

# PR subcommand handler
#
# Routes PR subcommands to their appropriate handler functions.
# Shows help for unknown commands.
#
# Usage: _gh_pr <subcommand> [OPTIONS]
# Subcommands: create, edit, review, explain, chat, help
_gh_pr() {
	local subcommand="${1:-}"
	shift || true

	case $subcommand in
	create)
		_gh_pr_create "$@"
		;;
	edit)
		_gh_pr_edit "$@"
		;;
	review)
		_gh_pr_review "$@"
		;;
	explain)
		_gh_pr_explain "$@"
		;;
	chat)
		_gh_pr_chat "$@"
		;;
	--help | -h | help | "")
		_show_pr_help
		;;
	*)
		gum log --level error "Unknown pr command '$subcommand'"
		gum log --level info "Available commands: create, edit, review, explain, chat"
		gum log --level info "Run 'gh ai pr --help' for usage information"
		return 1
		;;
	esac
}
