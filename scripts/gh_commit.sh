#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# Commit help function
#
# Displays help information for the commit command
# including usage examples and available options.
_show_commit_help() {
	cat <<'EOF'
gh ai commit - Create commits with AI-generated messages

USAGE:
    gh ai commit [-d <DESCRIPTION>] [GIT_COMMIT_OPTIONS]

DESCRIPTION:
    Generates a conventional commit message from staged changes using AI,
    then creates the commit. Any extra options are passed to git commit.

OPTIONS:
    -d, --description <TEXT>    Additional context for AI commit message generation

EXAMPLES:
    gh ai commit                                        # Generate message and commit
    gh ai commit -d "focus on security improvements"   # With additional context
    gh ai commit --signoff                              # Commit with sign-off
    gh ai commit --no-verify                            # Skip pre-commit hooks

SEE ALSO:
    git commit --help    # Full list of git commit options
EOF
}

# Parse commit arguments in a single pass
#
# Extracts the optional description and collects passthrough args for
# git commit via namerefs. AI-managed flags (-m/--message, -F/--file)
# and the -d/--description flag are stripped from git commit args.
#
# Example: _parse_commit_args desc args --signoff -d "context" -m "ignored"
_parse_commit_args() {
	local -n gh_commit_description_ref="$1"
	local -n git_commit_args_ref="$2"
	shift 2

	local _argv=("$@")
	local skip_next=false
	local i=0

	while [[ $i -lt ${#_argv[@]} ]]; do
		if [ "$skip_next" = true ]; then
			skip_next=false
			((++i))
			continue
		fi

		case "${_argv[$i]}" in
		--description | -d)
			gh_commit_description_ref="${_argv[$((i + 1))]}"
			skip_next=true
			;;
		--description=*)
			gh_commit_description_ref="${_argv[$i]#--description=}"
			;;
		-m | --message | -F | --file)
			skip_next=true
			;;
		--message=* | --file=*) ;;
		*)
			git_commit_args_ref+=("${_argv[$i]}")
			;;
		esac
		((++i))
	done
}

# Main commit command implementation
#
# Creates a git commit with an AI-generated message based on staged changes.
# Renders a prompt template with the staged diff and branch context,
# sends it to the AI provider, and commits with the response.
#
# Usage: _gh_commit [-d <DESCRIPTION>] [GIT_COMMIT_OPTIONS]
_gh_commit() {
	case "${1:-}" in
	--help | -h | help)
		_show_commit_help
		return 0
		;;
	esac

	local args=("$@")

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_ai_source_dir/templates/gh_commit.tmpl"

	local gh_commit_description=""
	local git_commit_args=()
	_parse_commit_args gh_commit_description git_commit_args "${args[@]}"

	# Gather git context
	local git_diff_staged
	git_diff_staged=$(git diff --staged)

	# Check if there are staged changes
	if [[ -z "$git_diff_staged" ]]; then
		gum log --level error "No staged changes found"
		gum log --level info "Stage your changes with 'git add' first"
		return 1
	fi

	local git_diff_staged_stat
	git_diff_staged_stat=$(git diff --staged --stat)

	local git_branch
	git_branch=$(git rev-parse --abbrev-ref HEAD)

	local git_log_oneline
	git_log_oneline=$(git log --oneline -5 2>/dev/null | sed 's/^[a-f0-9]* /- /')

	local agent_model
	agent_model=$(gh config get gh-ai.commit.model 2>/dev/null || true)

	# Format description as context block if provided
	local gh_commit_description_context=""
	if [[ -n "$gh_commit_description" ]]; then
		gh_commit_description_context="<description>$gh_commit_description</description>"
	fi

	local git_commit_message
	# Generate commit message using assistant run
	git_commit_message=$(
		gum spin --title "Generating Git commit message..." -- \
			"$_gh_ai_source_dir/scripts/gh_cmd.sh" assist "$agent_model" < <(
				GIT_DIFF_STAGED="$git_diff_staged" GIT_DIFF_STAGED_STAT="$git_diff_staged_stat" GIT_BRANCH="$git_branch" GIT_COMMITS="$git_log_oneline" GH_COMMIT_DESCRIPTION="$gh_commit_description_context" \
					"$_gh_ai_source_dir/scripts/gh_cmd.sh" render "$template_file"
			)
	)

	# Validate we got a commit message
	if [[ -z "$git_commit_message" ]]; then
		gum log --level error "Failed to generate commit message"
		gum log --level info "Run with DEBUG=1 for detailed diagnostics"
		return 1
	fi

	# Commit with the generated message and pass through any extra args
	git commit -m "$git_commit_message" "${git_commit_args[@]}"
}
