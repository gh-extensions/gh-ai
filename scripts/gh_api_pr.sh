#!/usr/bin/env bash

# PR API functions for gh-assistant
#
# Low-level GitHub API wrappers for pull request operations.
# These functions provide direct access to the GitHub REST API.
#
# Requires: gh_api.sh (provides _gh_api_repo_view, _gh_api_get_me, _gh_api_field_pairs)

# JQ filter for PR response normalization
#
# Returns a jq filter string that extracts standardized PR fields.
#
# Usage: _gh_api_pr_jq
# Returns: jq filter string
_gh_api_pr_jq() {
	echo '{id, number, title, body: (.body // "")}'
}

# Get pull request details by number
#
# Fetches PR information from the GitHub API.
#
# Usage: _gh_api_pr_view <pr_number>
# Example: _gh_api_pr_view 123
# Returns: JSON object with id, number, title, body
_gh_api_pr_view() {
	local repo
	local number=$1

	repo=$(_gh_api_repo_view)
	gh api \
		--method GET "/repos/${repo}/pulls/${number}" \
		--jq "$(_gh_api_pr_jq)"
}

# Create a new pull request
#
# Creates a PR via the GitHub API with the provided fields.
#
# Usage: _gh_api_pr_create "title=PR Title" "body=Description" "head=branch" "base=main"
# Returns: JSON object with created PR details
_gh_api_pr_create() {
	local repo
	local fields

	_gh_api_field_pairs fields "$@"

	repo=$(_gh_api_repo_view)
	gh api \
		--method POST "/repos/${repo}/pulls" "${fields[@]}" \
		--jq "$(_gh_api_pr_jq)"
}

# Update an existing pull request
#
# Updates PR fields via the GitHub API.
#
# Usage: _gh_api_pr_update <pr_number> "title=New Title" "body=Updated"
# Example: _gh_api_pr_update 123 "state=closed"
# Returns: JSON object with updated PR details
_gh_api_pr_update() {
	local repo
	local fields
	local number=$1
	shift 1

	_gh_api_field_pairs fields "$@"

	repo=$(_gh_api_repo_view)
	gh api \
		--method PATCH "/repos/${repo}/pulls/${number}" "${fields[@]}" \
		--jq "$(_gh_api_pr_jq)"
}

# PR API help function
#
# Displays comprehensive help information for all PR API subcommands
# including usage examples and available options.
_show_api_pr_help() {
	cat <<'EOF'
gh assistant api pr - GitHub PR API operations

USAGE:
    gh assistant api pr view <number>
    gh assistant api pr create <field=value>...
    gh assistant api pr update <number> <field=value>...

DESCRIPTION:
    Low-level GitHub API wrappers for pull request operations.
    Provides direct access to the GitHub REST API.

COMMANDS:
    view      Get PR details by number
    create    Create a new PR
    update    Update an existing PR

SEE ALSO:
    gh pr --help    # Full list of gh pr options
EOF
}

# PR API subcommand handler
#
# Routes PR API subcommands to their appropriate handler functions.
# Shows help for unknown commands.
#
# Usage: _gh_api_pr <subcommand> [OPTIONS]
# Subcommands: view, create, update, help
_gh_api_pr() {
	local subcommand="$1"
	shift

	case $subcommand in
	view)
		_gh_api_pr_view "$@"
		;;
	create)
		_gh_api_pr_create "$@"
		;;
	update)
		_gh_api_pr_update "$@"
		;;
	--help | -h | help | "")
		_show_api_pr_help
		;;
	*)
		gum log --level error "Unknown pr command '$subcommand'"
		gum log --level info "Available commands: view, create, update"
		gum log --level info "Run 'gh assistant api pr --help' for usage information"
		exit 1
		;;
	esac
}
