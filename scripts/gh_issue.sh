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

# Extract issue description from arguments
#
# Looks for -d/--description flag or first positional argument.
# Flag takes priority over positional.
#
# Example: _get_issue_description -d "Login crash" --label bug  # Returns: Login crash
# Example: _get_issue_description "Login crash" --label bug     # Returns: Login crash
_get_issue_description() {
	local issue_description=""
	local positional=""
	local consume=""

	local arg
	for arg in "$@"; do
		if [[ -n "$consume" ]]; then
			issue_description="$arg"
			consume=""
			continue
		fi

		case "$arg" in
		--description | -d) consume=yes ;;
		--description=*) issue_description="${arg#--description=}" ;;
		--*) ;;
		*)
			if [[ -z "$positional" ]]; then
				positional="$arg"
			fi
			;;
		esac
	done

	# Flag takes priority over positional
	if [[ -n "$issue_description" ]]; then
		echo "$issue_description"
	elif [[ -n "$positional" ]]; then
		echo "$positional"
	fi
}

# Extract labels from arguments
#
# Collects values from -l/--label flags into a comma-separated string
# for use in the prompt template context.
#
# Example: _get_issue_labels --label bug -l "high priority"  # Returns: bug, high priority
_get_issue_labels() {
	local issue_labels=""
	local consume=false

	local arg
	for arg in "$@"; do
		if [ "$consume" = true ]; then
			issue_labels="${issue_labels:+$issue_labels, }$arg"
			consume=false
			continue
		fi

		case "$arg" in
		--label | -l) consume=true ;;
		--label=*) issue_labels="${issue_labels:+$issue_labels, }${arg#--label=}" ;;
		esac
	done

	[[ -n "$issue_labels" ]] && echo "$issue_labels" || true
}

# Filter out flags managed by gh-ai from issue create arguments
#
# Removes description, title, body, template flags (and their values),
# and the first positional argument (description fallback).
# Flags that take values (--label, --assignee, etc.) are preserved
# along with their values.
_filter_issue_create_args() {
	local filtered=()
	local skip_next=false
	local pass_next=false
	local first_positional=true
	local arg

	for arg in "$@"; do
		if [ "$skip_next" = true ]; then
			skip_next=false
			continue
		fi

		if [ "$pass_next" = true ]; then
			filtered+=("$arg")
			pass_next=false
			continue
		fi

		case "$arg" in
		--description | -d | --title | -t | --body | -b | --body-file | -F | --template | -T)
			skip_next=true
			;;
		--description=* | --title=* | --body=* | --body-file=* | --template=*) ;;
		--assignee | -a | --label | -l | --milestone | -m | --project | -p)
			filtered+=("$arg")
			pass_next=true
			;;
		--*)
			filtered+=("$arg")
			;;
		*)
			# Skip first positional (description fallback)
			if [ "$first_positional" = true ]; then
				first_positional=false
			else
				filtered+=("$arg")
			fi
			;;
		esac
	done

	[[ ${#filtered[@]} -gt 0 ]] && printf '%s\n' "${filtered[@]}" || true
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
	local clean_args

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_ai_source_dir/templates/gh_issue_create.tmpl"

	local filtered_args
	filtered_args=$(_filter_issue_create_args "${args[@]}")
	if [[ -n "$filtered_args" ]]; then
		IFS=$'\n' read -rd '' -a clean_args <<<"$filtered_args" || true
	else
		clean_args=()
	fi

	local issue_description
	issue_description=$(_get_issue_description "${args[@]}")

	local issue_labels
	issue_labels=$(_get_issue_labels "${args[@]}")

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
				GH_ISSUE_DESCRIPTION="$issue_description" GH_LABELS="$issue_labels" GH_ISSUES="$gh_issues" EXTRA_CONTEXT="$extra_context" \
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
