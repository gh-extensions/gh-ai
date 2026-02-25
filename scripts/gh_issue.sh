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

DESCRIPTION:
    Creates GitHub issues with AI-generated titles and structured bodies.

COMMANDS:
    create      Create issues with AI-generated content

SEE ALSO:
    gh ai issue create --help    # Issue create usage
EOF
}

# Issue create help function
_show_issue_create_help() {
	cat <<'EOF'
gh ai issue create - Create issues with AI-generated content

USAGE:
    gh ai issue create [-d DESCRIPTION] [GH_ISSUE_CREATE_OPTIONS]

DESCRIPTION:
    Generates a structured GitHub issue from a brief description using AI.
    Any extra options are passed to gh issue create.

OPTIONS:
    -d, --description    Brief description of the issue (also accepted as positional arg)

EXAMPLES:
    gh ai issue create -d "Login page crashes with special chars"
    gh ai issue create --label bug --assignee @me "Login crash"
    gh ai issue create                     # interactive prompt
    some_command 2>&1 | gh ai issue create -d "Command X fails"

SEE ALSO:
    gh issue create --help    # Full list of gh issue create options
EOF
}

# Issue Create implementation
#
# Creates a GitHub issue with an AI-generated title and structured body.
# Renders a prompt template with the description and repo context,
# sends it to the AI provider, and parses the response.
# Supports interactive mode (no args) and piped stdin context.
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

	# Single pass: extract description, labels, and build clean args
	local issue_description=""
	local gh_labels=""
	local clean_args=()
	local positional_desc=""
	local consume=""

	local arg
	for arg in "${args[@]}"; do
		if [[ -n "$consume" ]]; then
			case "$consume" in
			description) issue_description="$arg" ;;
			label) gh_labels="${gh_labels:+$gh_labels, }$arg"; clean_args+=("$arg") ;;
			strip) ;;
			*) clean_args+=("$arg") ;;
			esac
			consume=""
			continue
		fi

		case "$arg" in
		--description | -d) consume=description ;;
		--description=*) issue_description="${arg#--description=}" ;;
		--label | -l) consume=label; clean_args+=("$arg") ;;
		--label=*) gh_labels="${gh_labels:+$gh_labels, }${arg#--label=}"; clean_args+=("$arg") ;;
		--title | -t | --body | -b | --body-file | -F | --template | -T) consume=strip ;;
		--title=* | --body=* | --body-file=* | --template=* | --description=*) ;;
		--assignee | -a | --milestone | -m | --project | -p) consume=keep; clean_args+=("$arg") ;;
		--*) clean_args+=("$arg") ;;
		*)
			# First positional is description fallback
			if [[ -z "$positional_desc" ]]; then
				positional_desc="$arg"
			else
				clean_args+=("$arg")
			fi
			;;
		esac
	done

	# --description/-d flag takes priority over positional arg
	if [[ -z "$issue_description" ]]; then
		issue_description="$positional_desc"
	elif [[ -n "$positional_desc" ]]; then
		clean_args+=("$positional_desc")
	fi

	# If no description, try interactive or error
	if [[ -z "$issue_description" ]]; then
		if [[ -t 0 ]]; then
			# Interactive mode: prompt with gum
			issue_description=$(gum write --placeholder "Describe the issue..." --header "Issue Description")
			if [[ -z "$issue_description" ]]; then
				gum log --level error "No description provided"
				return 1
			fi
		else
			gum log --level error "No description provided"
			gum log --level info "Usage: gh ai issue create <DESCRIPTION> [OPTIONS]"
			return 1
		fi
	fi

	# Read piped stdin context if available
	local extra_context=""
	if [[ ! -t 0 ]]; then
		extra_context=$(cat)
	fi

	local gh_issues
	gh_issues=$(gh issue list --limit 5 --state all --json number,title -q '.[] | "#" + (.number | tostring) + " " + .title' 2>/dev/null || true)

	local agent_model
	agent_model=$(gh config get gh-ai.issue.model 2>/dev/null || true)

	local output
	# Generate issue content using assistant run
	output=$(
		gum spin --title "Generating GitHub issue..." -- \
			"$_gh_ai_source_dir/scripts/gh_cmd.sh" assist "$agent_model" < <(
				GH_ISSUE_DESCRIPTION="$issue_description" GH_LABELS="$gh_labels" GH_ISSUES="$gh_issues" EXTRA_CONTEXT="$extra_context" \
					"$_gh_ai_source_dir/scripts/gh_cmd.sh" render "$template_file"
			)
	)

	# Validate we got issue content
	if [[ -z "$output" ]]; then
		gum log --level error "Failed to generate issue content"
		gum log --level info "Run with DEBUG=1 for detailed diagnostics"
		return 1
	fi

	local issue_title
	# Parse title from output
	if ! issue_title=$(_get_title "$output"); then
		gum log --level error "Failed to extract title from AI content"
		return 1
	fi

	local issue_body
	# Parse body from output
	issue_body=$(_get_body "$output")

	# Validate we got body content
	if [[ -z "$issue_body" ]]; then
		gum log --level error "Failed to extract body from AI content"
		return 1
	fi

	# Create issue with AI-generated content
	gh issue create --title "$issue_title" --body "$issue_body" "${clean_args[@]}"
}

# Issue subcommand handler
#
# Routes issue subcommands to their appropriate handler functions.
# Shows help for unknown commands.
#
# Usage: _gh_issue <subcommand> [OPTIONS]
# Subcommands: create, help
_gh_issue() {
	local subcommand="${1:-}"
	shift || true

	case $subcommand in
	create)
		_gh_issue_create "$@"
		;;
	--help | -h | help | "")
		_show_issue_help
		;;
	*)
		gum log --level error "Unknown issue command '$subcommand'"
		gum log --level info "Available commands: create"
		gum log --level info "Run 'gh ai issue --help' for usage information"
		exit 1
		;;
	esac
}
