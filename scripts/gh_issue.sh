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

# Extract issue description from arguments
#
# Looks for -d/--description flag value.
#
# Example: _get_issue_description -d "Login crash" --label bug  # Returns: Login crash
_get_issue_description() {
	local consume=false

	local arg
	for arg in "$@"; do
		if [ "$consume" = true ]; then
			echo "$arg"
			return 0
		fi

		case "$arg" in
		--description | -d) consume=true ;;
		--description=*)
			echo "${arg#--description=}"
			return 0
			;;
		esac
	done
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
# Removes description, title, body, and template flags (and their values)
# since the issue content is AI-generated. All other flags pass through.
_filter_issue_create_args() {
	local filtered=()
	local skip_next=false
	local arg

	for arg in "$@"; do
		if [ "$skip_next" = true ]; then
			skip_next=false
			continue
		fi

		case "$arg" in
		--description | -d | --title | -t | --body | -b | --body-file | -F | --template | -T)
			skip_next=true
			;;
		--description=* | --title=* | --body=* | --body-file=* | --template=*) ;;
		*)
			filtered+=("$arg")
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
# Supports piped stdin as additional context.
#
# Usage: _gh_issue_create [-d DESCRIPTION] [GH_ISSUE_CREATE_OPTIONS]
_gh_issue_create() {
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

	local gh_issue_description
	gh_issue_description=$(_get_issue_description "${args[@]}")

	local gh_issue_labels
	gh_issue_labels=$(_get_issue_labels "${args[@]}")

	# If no description, error out
	if [[ -z "$gh_issue_description" ]]; then
		gum log --level error "No description provided"
		gum log --level info "Usage: gh ai issue create -d <DESCRIPTION> [OPTIONS]"
		return 1
	fi

	# Read piped stdin context if available
	local extra_context=""
	if [[ ! -t 0 ]]; then
		extra_context=$(cat)
	fi

	local agent_model
	agent_model=$(gh config get gh-ai.issue.model 2>/dev/null || true)

	local output
	# Generate issue content using assistant run
	output=$(
		gum spin --title "Generating GitHub issue..." -- \
			"$_gh_ai_source_dir/scripts/gh_cmd.sh" assist "$agent_model" < <(
				GH_ISSUE_DESCRIPTION="$gh_issue_description" GH_LABELS="$gh_issue_labels" EXTRA_CONTEXT="$extra_context" \
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
	gh issue create --title "$gh_issue_title" --body "$gh_issue_body" "${clean_args[@]}"
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
