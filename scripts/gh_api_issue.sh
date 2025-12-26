#!/usr/bin/env bash

# Issue API functions for gh-assistant
#
# Low-level GitHub API wrappers for issue operations.
# These functions provide direct access to the GitHub REST API.
#
# Requires: gh_api.sh (provides _gh_api_repo_view, _gh_api_get_me, _gh_api_field_pairs)

# JQ filter for issue response normalization
#
# Returns a jq filter string that extracts standardized issue fields.
# Includes type extraction and parent issue number parsing.
#
# Usage: _gh_api_issue_jq
# Returns: jq filter string
_gh_api_issue_jq() {
	echo '{id, number, title, body: (.body // ""), type: (.type.name // "Task"), parent_issue_number: (.parent_issue_url // null | if . then sub("/ *$";"") | split("/")[-1] else null end)}'
}

# Get issue details by number
#
# Fetches issue information from the GitHub API.
#
# Usage: _gh_api_issue_view <issue_number>
# Example: _gh_api_issue_view 42
# Returns: JSON object with id, number, title, body, type, parent_issue_number
_gh_api_issue_view() {
	local repo
	local number=$1

	repo=$(_gh_api_repo_view)
	gh api \
		--method GET "/repos/${repo}/issues/${number}" \
		--jq "$(_gh_api_issue_jq)"
}

# Link an issue as a sub-issue to a parent
#
# Creates a parent-child relationship between two issues.
#
# Usage: _gh_api_issue_link <parent_number> <child_number>
# Example: _gh_api_issue_link 10 42
# Returns: JSON object with linked issue details
_gh_api_issue_link() {
	local repo
	local parent=$1
	local number=$2

	repo=$(_gh_api_repo_view)
	gh api \
		--method POST "/repos/${repo}/issues/${parent}/sub_issues" \
		--field "sub_issue_id=${number}" \
		--jq "$(_gh_api_issue_jq)"
}

# Create a new issue
#
# Creates an issue via the GitHub API with the provided fields.
#
# Usage: _gh_api_issue_create "title=Issue Title" "body=Description"
# Example: _gh_api_issue_create "title=Bug report" "body=Details" "assignee=@me"
# Returns: JSON object with created issue details
_gh_api_issue_create() {
	local repo

	repo=$(_gh_api_repo_view)
	_gh_api_field_pairs "$@" |
		xargs -0 gh api \
			--method POST "/repos/${repo}/issues" \
			--jq "$(_gh_api_issue_jq)"
}

# Update an existing issue
#
# Updates issue fields via the GitHub API.
#
# Usage: _gh_api_issue_update <issue_number> "title=New Title" "body=Updated"
# Example: _gh_api_issue_update 42 "state=closed"
# Returns: JSON object with updated issue details
_gh_api_issue_update() {
	local repo
	local number=$1
	shift 1

	repo=$(_gh_api_repo_view)
	_gh_api_field_pairs "$@" |
		xargs -0 gh api \
			--method PATCH "/repos/${repo}/issues/${number}" \
			--jq "$(_gh_api_issue_jq)"
}

# Start development on an issue
#
# Creates a new branch for the issue, checks it out, creates an
# initial empty commit, and pushes to origin. Branch name is
# derived from issue type and number (e.g., "bug-42", "feature-10").
#
# Usage: _gh_api_issue_develop <issue_number>
# Example: _gh_api_issue_develop 42
# Returns: Branch name string (e.g., "bug-42")
_gh_api_issue_develop() {
	local repo
	local issue
	local issue_type
	local issue_number="$1"
	local pr_branch
	shift 1

	issue="$(_gh_api_issue_view "$issue_number")"
	issue_type="$(echo "$issue" | jq -r ".type | ascii_downcase")"
	issue_number="$(echo "$issue" | jq -r ".number")"

	pr_branch="$issue_type-$issue_number"

	# Create and checkout branch linked to issue
	gh issue develop "$issue_number" --base main --name "$pr_branch" --checkout

	# Create initial commit and push
	git commit --allow-empty -m "Starts #$issue_number"
	git push -u origin "$pr_branch"

	echo "$pr_branch"
}

# Issue API help function
#
# Displays comprehensive help information for all issue API subcommands
# including usage examples and available options.
_show_api_issue_help() {
	cat <<'EOF'
gh assistant api issue - GitHub Issue API operations

USAGE:
    gh assistant api issue view <number>
    gh assistant api issue create <field=value>...
    gh assistant api issue update <number> <field=value>...
    gh assistant api issue link <parent> <child>
    gh assistant api issue develop <number>

DESCRIPTION:
    Low-level GitHub API wrappers for issue operations.
    Provides direct access to the GitHub REST API.

COMMANDS:
    view      Get issue details by number
    link      Link child issue to parent
    create    Create a new issue
    update    Update an existing issue
    develop   Create branch and start development

SEE ALSO:
    gh issue --help    # Full list of gh issue options
EOF
}

# Main entry point
#
# Routes commands to appropriate handler functions.
#
# Usage: gh_api_issue.sh <command> [arguments]
_gh_api_issue() {
	local subcommand="$1"
	shift

	case "$subcommand" in
	view)
		_gh_api_issue_view "$@"
		;;
	link)
		_gh_api_issue_link "$@"
		;;
	create)
		_gh_api_issue_create "$@"
		;;
	update)
		_gh_api_issue_update "$@"
		;;
	develop)
		_gh_api_issue_develop "$@"
		;;
	--help | -h | help | "")
		_show_api_issue_help
		;;
	*)
		gum log --level error "Unknown issue command '$subcommand'"
		gum log --level info "Available commands: view, link, create, update, develop"
		gum log --level info "Run 'gh assistant api issue --help' for usage information"
		exit 1
		;;
	esac
}
