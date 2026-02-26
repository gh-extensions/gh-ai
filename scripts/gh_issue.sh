#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# Issue-related functions for gh-ai

# Issue help function
#
# Displays comprehensive help information for all issue subcommands
# including usage examples and available options.
_show_issue_help() {
	cat <<'EOF'
gh ai issue - Issue commands with AI assistance

USAGE:
    gh ai issue create [-d DESCRIPTION] [GH_ISSUE_CREATE_OPTIONS]
    gh ai issue edit <ISSUE_NUMBER> -d <DESCRIPTION> [GH_ISSUE_EDIT_OPTIONS]
    gh ai issue develop <ISSUE_NUMBER> [GH_ISSUE_DEVELOP_OPTIONS]

DESCRIPTION:
    Creates and edits GitHub issues with AI-generated titles and structured
    bodies. Develops issues by creating a branch, generating an implementation
    plan, and opening a pull request.

COMMANDS:
    create      Create issues with AI-generated content
    edit        Edit an existing issue with AI-generated content
    develop     Create a branch and PR with an AI implementation plan

SEE ALSO:
    gh ai issue create --help     # Issue create usage
    gh ai issue edit --help       # Issue edit usage
    gh ai issue develop --help    # Issue develop usage
EOF
}

# Parse issue create arguments in a single pass
#
# Extracts the description, labels (comma-separated for the template),
# and passthrough args for gh issue create via namerefs.
# Labels pass through to gh issue create AND are collected for the template.
# AI-managed flags (--title, --body, --body-file, --template) are stripped.
#
# Example: _parse_issue_create_args desc labels args -d "Login crash" --label bug
_parse_issue_create_args() {
	local -n gh_issue_description_ref="$1"
	local -n gh_issue_labels_ref="$2"
	# shellcheck disable=SC2178
	local -n gh_issue_args_ref="$3"
	shift 3

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
			gh_issue_description_ref="${raw_args[$((i + 1))]}"
			skip_next=true
			;;
		--description=*)
			gh_issue_description_ref="${raw_args[$i]#--description=}"
			;;
		--label | -l)
			gh_issue_labels_ref="${gh_issue_labels_ref:+$gh_issue_labels_ref, }${raw_args[$((i + 1))]}"
			gh_issue_args_ref+=("${raw_args[$i]}" "${raw_args[$((i + 1))]}")
			skip_next=true
			;;
		--label=*)
			gh_issue_labels_ref="${gh_issue_labels_ref:+$gh_issue_labels_ref, }${raw_args[$i]#--label=}"
			gh_issue_args_ref+=("${raw_args[$i]}")
			;;
		--title | -t | --body | -b | --body-file | -F)
			skip_next=true
			;;
		--title=* | --body=* | --body-file=*) ;;
		*)
			gh_issue_args_ref+=("${raw_args[$i]}")
			;;
		esac
		((++i))
	done
}

# Parse issue edit arguments in a single pass
#
# Extracts the issue number (first numeric arg), description, and
# passthrough args for gh issue edit via namerefs.
# AI-managed flags (--title, --body, --body-file) are stripped.
#
# Example: _parse_issue_edit_args num desc args 42 -d "add acceptance criteria" --add-label bug
_parse_issue_edit_args() {
	local -n gh_issue_number_ref="$1"
	local -n gh_issue_description_ref="$2"
	# shellcheck disable=SC2178
	local -n gh_issue_args_ref="$3"
	shift 3

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
			gh_issue_description_ref="${raw_args[$((i + 1))]}"
			skip_next=true
			;;
		--description=*)
			# shellcheck disable=SC2034
			gh_issue_description_ref="${raw_args[$i]#--description=}"
			;;
		--title | -t | --body | -b | --body-file | -F)
			skip_next=true
			;;
		--title=* | --body=* | --body-file=*) ;;
		*)
			if [[ -z "$gh_issue_number_ref" && "${raw_args[$i]}" =~ ^[0-9]+$ ]]; then
				gh_issue_number_ref="${raw_args[$i]}"
			else
				gh_issue_args_ref+=("${raw_args[$i]}")
			fi
			;;
		esac
		((++i))
	done
}

# Issue edit help function
#
# Displays help information for the issue edit command
# including usage examples and available options.
_show_issue_edit_help() {
	cat <<'EOF'
gh ai issue edit - Edit an existing issue with AI-generated content

USAGE:
    gh ai issue edit <ISSUE_NUMBER> -d <DESCRIPTION> [OPTIONS]

DESCRIPTION:
    Edits an existing GitHub issue using AI. Fetches the current issue
    content, applies the requested changes via AI, and updates the issue
    title and body. Supports piped stdin as additional context.

FLAGS:
    -d, --description string   Description of the changes to make (required)

PASSTHROUGH FLAGS:
    All other flags are passed directly to gh issue edit.
    See gh issue edit --help for the full list.

EXAMPLES:
    gh ai issue edit 42 -d "add acceptance criteria"
    gh ai issue edit 42 -d "fix typos and improve clarity"
    gh ai issue edit 42 -d "rephrase as a bug report" --add-label bug
    some_command 2>&1 | gh ai issue edit 42 -d "add error output"
EOF
}

# Issue Edit implementation
#
# Edits an existing GitHub issue with AI-generated content.
# Fetches the current issue, renders a prompt template with the
# description and issue context, sends it to the AI provider,
# and updates the issue with the parsed response.
# Supports piped stdin as additional context.
#
# Usage: _gh_issue_edit <ISSUE_NUMBER> -d <DESCRIPTION> [GH_ISSUE_EDIT_OPTIONS]
_gh_issue_edit() {
	case "${1:-}" in
	--help | -h | help)
		_show_issue_edit_help
		return 0
		;;
	esac

	local args=("$@")

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_ai_source_dir/templates/gh_issue_edit.tmpl"

	local gh_issue_number=""
	local gh_issue_description=""
	local gh_issue_args=()
	_parse_issue_edit_args gh_issue_number gh_issue_description gh_issue_args "${args[@]}"

	if [[ -z "$gh_issue_number" ]]; then
		gum log --level error "No issue number provided"
		gum log --level info "Usage: gh ai issue edit <ISSUE_NUMBER> -d <DESCRIPTION> [OPTIONS]"
		return 1
	fi

	if [[ -z "$gh_issue_description" ]]; then
		gum log --level error "No description provided"
		gum log --level info "Usage: gh ai issue edit <ISSUE_NUMBER> -d <DESCRIPTION> [OPTIONS]"
		return 1
	fi

	# Read piped stdin context if available
	local gh_issue_context=""
	if [[ ! -t 0 ]]; then
		gh_issue_context=$(cat)
	fi

	# Fetch issue metadata
	local gh_issue_meta
	gh_issue_meta=$(gum spin --title "Fetching GitHub issue metadata..." -- \
		gh issue view "$gh_issue_number" --json title,body,labels,comments || true)
	if [[ -z "$gh_issue_meta" ]]; then
		gum log --level error "Failed to fetch issue #$gh_issue_number"
		return 1
	fi

	local gh_issue_title
	gh_issue_title=$(echo "$gh_issue_meta" | jq -r '.title // ""')

	local gh_issue_body
	gh_issue_body=$(echo "$gh_issue_meta" | jq -r '.body // ""')

	local gh_issue_labels
	gh_issue_labels=$(echo "$gh_issue_meta" | jq -r '[.labels[].name] | join(", ")')

	local gh_issue_comments
	gh_issue_comments=$(echo "$gh_issue_meta" | jq -r '[.comments[].body] | join("\n---\n")')

	local agent_model
	agent_model=$(gh config get gh-ai.issue.model 2>/dev/null || true)

	local output
	# Generate updated issue content using assistant
	output=$(
		gum spin --title "Generating updated GitHub issue..." -- \
			"$_gh_ai_source_dir/scripts/gh_cmd.sh" assist "$agent_model" < <(
				GH_ISSUE_NUMBER="$gh_issue_number" GH_ISSUE_TITLE="$gh_issue_title" GH_ISSUE_BODY="$gh_issue_body" GH_ISSUE_LABELS="$gh_issue_labels" GH_ISSUE_COMMENTS="$gh_issue_comments" GH_ISSUE_DESCRIPTION="$gh_issue_description" GH_ISSUE_CONTEXT="$gh_issue_context" \
					"$_gh_ai_source_dir/scripts/gh_cmd.sh" render "$template_file"
			)
	)

	# Validate we got issue content
	if [[ -z "$output" ]]; then
		gum log --level error "Failed to generate updated issue content"
		gum log --level info "Run with DEBUG=1 for detailed diagnostics"
		return 1
	fi

	local gh_issue_new_title
	# Parse title from output
	if ! gh_issue_new_title=$(_get_title "$output"); then
		gum log --level error "Failed to extract title from AI content"
		return 1
	fi

	local gh_issue_new_body
	# Parse body from output
	gh_issue_new_body=$(_get_body "$output")

	# Validate we got body content
	if [[ -z "$gh_issue_new_body" ]]; then
		gum log --level error "Failed to extract body from AI content"
		return 1
	fi

	# Edit issue with AI-generated content
	gh issue edit "$gh_issue_number" --title "$gh_issue_new_title" --body "$gh_issue_new_body" "${gh_issue_args[@]}"
}

# Parse issue develop arguments in a single pass
#
# Extracts the issue number (first numeric arg), gh issue develop flags
# (--base, --name, --branch-repo), and gh pr create passthrough args
# via namerefs. Develop-only flags are a small explicit set; everything
# else passes through to gh pr create.
#
# Example: _parse_issue_develop_args num devargs prargs 42 --name my-branch --draft
_parse_issue_develop_args() {
	local -n gh_issue_number_ref="$1"
	# shellcheck disable=SC2178
	local -n gh_issue_args_ref="$2"
	local -n gh_pr_args_ref="$3"
	shift 3

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
		--base | -b | --name | -n | --branch-repo)
			gh_issue_args_ref+=("${raw_args[$i]}" "${raw_args[$((i + 1))]}")
			skip_next=true
			;;
		--base=* | --name=* | --branch-repo=*)
			gh_issue_args_ref+=("${raw_args[$i]}")
			;;
		--checkout | -c) ;;
		--head | -H | -B)
			skip_next=true
			;;
		--head=*) ;;
		--title | -t | --body | --body-file | -F)
			skip_next=true
			;;
		--title=* | --body=* | --body-file=*) ;;
		*)
			if [[ -z "$gh_issue_number_ref" && "${raw_args[$i]}" =~ ^[0-9]+$ ]]; then
				gh_issue_number_ref="${raw_args[$i]}"
			else
				gh_pr_args_ref+=("${raw_args[$i]}")
			fi
			;;
		esac
		((++i))
	done
}

# Issue develop help function
#
# Displays help information for the issue develop command
# including usage examples and available options.
_show_issue_develop_help() {
	cat <<'EOF'
gh ai issue develop - Create a branch and PR with an AI implementation plan

USAGE:
    gh ai issue develop <ISSUE_NUMBER> [OPTIONS]

DESCRIPTION:
    Creates a development branch from a GitHub issue, generates an AI
    implementation plan, and opens a pull request with that plan.

    Combines gh issue develop (branch creation) with gh pr create
    (pull request). Title and body are AI-generated from the issue.

BRANCH FLAGS (gh issue develop):
    -b, --base string          Name of the remote branch to branch from
    -n, --name string          Name of the branch to create
        --branch-repo string   Name or URL of the repo for the new branch

PR FLAGS (gh pr create):
    -a, --assignee login       Assign people by their login
    -d, --draft                Mark pull request as a draft
        --dry-run              Print details instead of creating the PR
    -e, --editor               Open text editor for title and body
    -l, --label name           Add labels by name
    -m, --milestone name       Add the pull request to a milestone
        --no-maintainer-edit   Disable maintainer's ability to modify PR
    -p, --project title        Add the pull request to projects
    -r, --reviewer handle      Request reviews from people or teams
    -w, --web                  Open the web browser to create the PR

EXAMPLES:
    gh ai issue develop 42
    gh ai issue develop 42 --draft
    gh ai issue develop 42 --base develop --label enhancement
    gh ai issue develop 42 --reviewer monalisa --milestone v1.0
EOF
}

# Issue Develop implementation
#
# Creates a development branch from an issue, generates an AI implementation
# plan, and opens a pull request with that plan as the body.
# Uses native `gh issue develop` for branch creation.
#
# Usage: _gh_issue_develop <ISSUE_NUMBER> [OPTIONS]
_gh_issue_develop() {
	case "${1:-}" in
	--help | -h | help)
		_show_issue_develop_help
		return 0
		;;
	esac

	local args=("$@")

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_ai_source_dir/templates/gh_issue_develop.tmpl"

	local gh_issue_number=""
	local gh_issue_args=()
	local gh_pr_args=()
	_parse_issue_develop_args gh_issue_number gh_issue_args gh_pr_args "${args[@]}"

	# Reject flags that are incompatible with AI content generation
	for arg in "${gh_pr_args[@]}"; do
		case "$arg" in
		--fill | --fill-first | --fill-verbose | -T | --template | --template=*)
			gum log --level error "'$arg' is not supported by gh ai issue develop"
			gum log --level info "Use 'gh pr create $arg' directly instead"
			return 1
			;;
		esac
	done

	if [[ -z "$gh_issue_number" ]]; then
		gum log --level error "No issue number provided"
		gum log --level info "Usage: gh ai issue develop <ISSUE_NUMBER> [OPTIONS]"
		return 1
	fi

	# Fetch issue metadata
	local gh_issue_meta
	gh_issue_meta=$(gum spin --title "Fetching GitHub issue metadata..." -- \
		gh issue view "$gh_issue_number" --json title,body,labels,comments || true)
	if [[ -z "$gh_issue_meta" ]]; then
		gum log --level error "Failed to fetch issue #$gh_issue_number"
		return 1
	fi

	local gh_issue_title
	gh_issue_title=$(echo "$gh_issue_meta" | jq -r '.title // ""')

	local gh_issue_body
	gh_issue_body=$(echo "$gh_issue_meta" | jq -r '.body // ""')

	local gh_issue_labels
	gh_issue_labels=$(echo "$gh_issue_meta" | jq -r '[.labels[].name] | join(", ")')

	local gh_issue_comments
	gh_issue_comments=$(echo "$gh_issue_meta" | jq -r '[.comments[].body] | join("\n---\n")')

	local agent_model
	agent_model=$(gh config get gh-ai.issue.model 2>/dev/null || true)

	local output
	# Generate implementation plan using assistant
	output=$(
		gum spin --title "Generating GitHub issue implementation plan..." -- \
			"$_gh_ai_source_dir/scripts/gh_cmd.sh" assist "$agent_model" < <(
				GH_ISSUE_NUMBER="$gh_issue_number" GH_ISSUE_TITLE="$gh_issue_title" GH_ISSUE_BODY="$gh_issue_body" GH_ISSUE_LABELS="$gh_issue_labels" GH_ISSUE_COMMENTS="$gh_issue_comments" \
					"$_gh_ai_source_dir/scripts/gh_cmd.sh" render "$template_file"
			)
	)

	# Validate we got content
	if [[ -z "$output" ]]; then
		gum log --level error "Failed to generate implementation plan"
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

	# Create the development branch and checkout
	gh issue develop "$gh_issue_number" --checkout "${gh_issue_args[@]}"

	# Empty commit so the PR has a diff against the base branch
	git commit --allow-empty -m "chore: start work on #$gh_issue_number"
	git push -u origin HEAD

	# Create the pull request
	gh pr create --title "$gh_pr_title" --body "$gh_pr_body" "${gh_pr_args[@]}"
}

# Issue create help function
#
# Displays help information for the issue create command
# including usage examples and available options.
_show_issue_create_help() {
	cat <<'EOF'
gh ai issue create - Create issues with AI-generated content

USAGE:
    gh ai issue create -d <DESCRIPTION> [OPTIONS]

DESCRIPTION:
    Creates a GitHub issue with an AI-generated title and structured body
    from a brief description. Supports piped stdin as additional context.

FLAGS:
    -d, --description string   Brief description of the issue (required)

PASSTHROUGH FLAGS:
    All other flags are passed directly to gh issue create.
    See gh issue create --help for the full list.

EXAMPLES:
    gh ai issue create -d "Login page crashes with special chars"
    gh ai issue create -d "Login crash" --label bug --assignee @me
    some_command 2>&1 | gh ai issue create -d "Command X fails"
EOF
}

# Issue Create implementation
#
# Creates a GitHub issue with an AI-generated title and structured body.
# Renders a prompt template with the description and repo context,
# sends it to the AI provider, and parses the response.
# Supports piped stdin as additional context.
#
# Usage: _gh_issue_create [-d DESCRIPTION] [GH_ISSUE_CREATE_OPTIONS]
_gh_issue_create() {
	case "${1:-}" in
	--help | -h | help)
		_show_issue_create_help
		return 0
		;;
	esac

	local args=("$@")

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_ai_source_dir/templates/gh_issue_create.tmpl"

	local gh_issue_description=""
	local gh_issue_labels=""
	local gh_issue_args=()
	_parse_issue_create_args gh_issue_description gh_issue_labels gh_issue_args "${args[@]}"

	# Reject flags that are incompatible with AI content generation
	for arg in "${gh_issue_args[@]}"; do
		case "$arg" in
		-T | --template | --template=*)
			gum log --level error "'$arg' is not supported by gh ai issue create"
			gum log --level info "Use 'gh issue create $arg' directly instead"
			return 1
			;;
		esac
	done

	# If no description, error out
	if [[ -z "$gh_issue_description" ]]; then
		gum log --level error "No description provided"
		gum log --level info "Usage: gh ai issue create -d <DESCRIPTION> [OPTIONS]"
		return 1
	fi

	# Read piped stdin context if available
	local gh_issue_context=""
	if [[ ! -t 0 ]]; then
		gh_issue_context=$(cat)
	fi

	local agent_model
	agent_model=$(gh config get gh-ai.issue.model 2>/dev/null || true)

	local output
	# Generate issue content using assistant run
	output=$(
		gum spin --title "Generating GitHub issue..." -- \
			"$_gh_ai_source_dir/scripts/gh_cmd.sh" assist "$agent_model" < <(
				GH_ISSUE_DESCRIPTION="$gh_issue_description" GH_ISSUE_LABELS="$gh_issue_labels" GH_ISSUE_CONTEXT="$gh_issue_context" \
					"$_gh_ai_source_dir/scripts/gh_cmd.sh" render "$template_file"
			)
	)

	# Validate we got issue content
	if [[ -z "$output" ]]; then
		gum log --level error "Failed to generate issue content"
		gum log --level info "Run with DEBUG=1 for detailed diagnostics"
		return 1
	fi

	local gh_issue_title
	# Parse title from output
	if ! gh_issue_title=$(_get_title "$output"); then
		gum log --level error "Failed to extract title from AI content"
		return 1
	fi

	local gh_issue_body
	# Parse body from output
	gh_issue_body=$(_get_body "$output")

	# Validate we got body content
	if [[ -z "$gh_issue_body" ]]; then
		gum log --level error "Failed to extract body from AI content"
		return 1
	fi

	# Create issue with AI-generated content
	gh issue create --title "$gh_issue_title" --body "$gh_issue_body" "${gh_issue_args[@]}"
}

# Issue subcommand handler
#
# Routes issue subcommands to their appropriate handler functions.
# Shows help for unknown commands.
#
# Usage: _gh_issue <subcommand> [OPTIONS]
# Subcommands: create, edit, develop, help
_gh_issue() {
	local subcommand="${1:-}"
	shift || true

	case $subcommand in
	create)
		_gh_issue_create "$@"
		;;
	edit)
		_gh_issue_edit "$@"
		;;
	develop)
		_gh_issue_develop "$@"
		;;
	--help | -h | help | "")
		_show_issue_help
		;;
	*)
		gum log --level error "Unknown issue command '$subcommand'"
		gum log --level info "Available commands: create, edit, develop"
		gum log --level info "Run 'gh ai issue --help' for usage information"
		exit 1
		;;
	esac
}
