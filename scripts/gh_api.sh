#!/usr/bin/env bash

# GitHub API functions for gh-assistant
#
# Unified entry point for GitHub API operations.
# Routes commands to PR and Issue API modules.

_gh_api_source_dir=$(dirname "${BASH_SOURCE[0]}")

# Get repository owner/repo from git remote
#
# Extracts the owner/repo path from the origin remote URL.
# Handles both SSH (git@github.com:owner/repo.git) and
# HTTPS (https://github.com/owner/repo.git) formats.
#
# Usage: _gh_api_repo_view
# Returns: owner/repo string (e.g., "octocat/hello-world")
_gh_api_repo_view() {
	local remote_url

	remote_url=$(git remote get-url origin 2>/dev/null)
	echo "$remote_url" | sed -E 's#^(git@|https://)([^:/]+)[:/]##; s#\.git$##'
}

# Get current authenticated user's login
#
# Fetches the username of the currently authenticated GitHub user.
#
# Usage: _gh_api_get_me
# Returns: GitHub username string
_gh_api_get_me() {
	gh api --method GET /user --jq '.login'
}

# Convert key=value pairs to gh api --field arguments
#
# Transforms an array of key=value strings into --field arguments
# for gh api. Special handling for "assignee=@me" to resolve
# the current user's login.
#
# Usage: _gh_api_field_pairs output_array "title=My Title" "body=Content"
# Example: _gh_api_field_pairs fields "title=Bug fix" "assignee=@me"
_gh_api_field_pairs() {
	local -n _out=$1
	shift

	_out=()
	for pair in "$@"; do
		if [[ "$pair" == "assignee=@me" ]]; then
			_out+=(--field "assignee=$(_gh_api_get_me)")
		else
			_out+=(--field "$pair")
		fi
	done
}

# Source API modules
source "$_gh_api_source_dir/gh_api_pr.sh"
source "$_gh_api_source_dir/gh_api_issue.sh"

# API help function
#
# Displays comprehensive help information for all API subcommands
# including usage examples and available options.
_show_api_help() {
	cat <<'EOF'
gh assistant api - GitHub API operations

USAGE:
    gh assistant api pr <command> [arguments]
    gh assistant api issue <command> [arguments]

DESCRIPTION:
    Low-level GitHub API wrappers for PR and issue operations.
    Provides direct access to the GitHub REST API.

COMMANDS:
    pr        Pull request API operations
    issue     Issue API operations

SEE ALSO:
    gh assistant api pr --help       # PR API commands
    gh assistant api issue --help    # Issue API commands
EOF
}

# API subcommand handler
#
# Routes API subcommands (pr, issue) to their appropriate
# handler functions. Shows help for unknown commands.
#
# Usage: _gh_api <subcommand> [OPTIONS]
# Subcommands: pr, issue, help
_gh_api() {
	local subcommand="$1"
	shift

	case $subcommand in
	pr)
		_gh_api_pr "$@"
		;;
	issue)
		_gh_api_issue "$@"
		;;
	--help | -h | help | "")
		_show_api_help
		;;
	*)
		gum log --level error "Unknown api command '$subcommand'"
		gum log --level info "Available commands: pr, issue"
		gum log --level info "Run 'gh assistant api --help' for usage information"
		exit 1
		;;
	esac
}
