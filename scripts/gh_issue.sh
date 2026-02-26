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
    gh ai issue create -d <DESCRIPTION> [-- GH_ISSUE_CREATE_OPTIONS]
    gh ai issue edit <ISSUE_NUMBER> -d <DESCRIPTION> [-- GH_ISSUE_EDIT_OPTIONS]
    gh ai issue develop <ISSUE_NUMBER> [-c] [-b BASE] [-n NAME] [--branch-repo REPO] [-- GH_PR_CREATE_OPTIONS]

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

# Parse issue create arguments (before -- separator)
#
# Extracts the -d/--description value. Unknown flags produce an error
# with a hint to use --.
#
# Example: _parse_issue_create_args desc -d "Login crash"
_parse_issue_create_args() {
	local -n gh_issue_description_ref="$1"
	shift

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
				echo "error: ${raw_args[$i]} requires a value" >&2
				return 1
			fi
			gh_issue_description_ref="${raw_args[$((i + 1))]}"
			skip_next=true
			;;
		--description=*)
			gh_issue_description_ref="${raw_args[$i]#--description=}"
			;;
		-*)
			echo "error: unknown flag '${raw_args[$i]}' (use -- to pass flags to gh issue create)" >&2
			return 1
			;;
		*)
			echo "error: unexpected argument '${raw_args[$i]}'" >&2
			return 1
			;;
		esac
		((++i))
	done
}

# Parse issue edit arguments (before -- separator)
#
# Extracts the issue number (first numeric arg) and -d/--description value.
# Unknown flags produce an error with a hint to use --.
#
# Example: _parse_issue_edit_args num desc 42 -d "add acceptance criteria"
_parse_issue_edit_args() {
	local -n gh_issue_number_ref="$1"
	local -n gh_issue_description_ref="$2"
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
				echo "error: ${raw_args[$i]} requires a value" >&2
				return 1
			fi
			gh_issue_description_ref="${raw_args[$((i + 1))]}"
			skip_next=true
			;;
		--description=*)
			# shellcheck disable=SC2034
			gh_issue_description_ref="${raw_args[$i]#--description=}"
			;;
		-*)
			echo "error: unknown flag '${raw_args[$i]}' (use -- to pass flags to gh issue edit)" >&2
			return 1
			;;
		*)
			if [[ -z "$gh_issue_number_ref" && "${raw_args[$i]}" =~ ^[0-9]+$ ]]; then
				gh_issue_number_ref="${raw_args[$i]}"
			else
				echo "error: unexpected argument '${raw_args[$i]}'" >&2
				return 1
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
    gh ai issue edit <ISSUE_NUMBER> -d <DESCRIPTION> [-- GH_ISSUE_EDIT_OPTIONS]

DESCRIPTION:
    Edits an existing GitHub issue using AI. Fetches the current issue
    content, applies the requested changes via AI, and updates the issue
    title and body. Supports piped stdin as additional context. Options
    after -- are passed directly to gh issue edit.

FLAGS:
    -d, --description string   Description of the changes to make (required)

EXAMPLES:
    gh ai issue edit 42 -d "add acceptance criteria"
    gh ai issue edit 42 -d "fix typos and improve clarity"
    gh ai issue edit 42 -d "rephrase as a bug report" -- --add-label bug
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
# Usage: _gh_issue_edit <NUMBER> -d <DESCRIPTION> [-- OPTIONS]
_gh_issue_edit() {
	case "${1:-}" in
	--help | -h | help)
		_show_issue_edit_help
		return 0
		;;
	esac

	local ai_args=()
	local passthrough=()
	_split_on_separator ai_args passthrough "$@"

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_ai_source_dir/templates/gh_issue_edit.tmpl"

	local gh_issue_number=""
	local gh_issue_description=""
	_parse_issue_edit_args gh_issue_number gh_issue_description "${ai_args[@]}"

	if [[ -z "$gh_issue_number" ]]; then
		gum log --level error "No issue number provided"
		gum log --level info "Usage: gh ai issue edit <ISSUE_NUMBER> -d <DESCRIPTION> [-- OPTIONS]"
		return 1
	fi

	if [[ -z "$gh_issue_description" ]]; then
		gum log --level error "No description provided"
		gum log --level info "Usage: gh ai issue edit <ISSUE_NUMBER> -d <DESCRIPTION> [-- OPTIONS]"
		return 1
	fi

	# Read piped stdin context if available
	local gh_issue_context=""
	if [[ ! -t 0 ]]; then
		gh_issue_context=$(cat)
	fi

	# Fetch issue metadata
	local gh_issue_eval
	gh_issue_eval=$(gum spin --title "Fetching GitHub issue metadata..." -- \
		gh issue view "$gh_issue_number" --json title,body,labels,comments \
		-q "$(<"$_gh_ai_source_dir/scripts/gh_issue_meta.jq")" || true)
	if [[ -z "$gh_issue_eval" ]]; then
		gum log --level error "Failed to fetch issue #$gh_issue_number"
		return 1
	fi

	local gh_issue_title gh_issue_body gh_issue_labels gh_issue_comments
	eval "$gh_issue_eval"

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
	gh issue edit "$gh_issue_number" --title "$gh_issue_new_title" --body "$gh_issue_new_body" "${passthrough[@]}"
}

# Parse issue develop arguments (before -- separator)
#
# Extracts the issue number (first numeric arg), -c/--checkout flag,
# gh issue develop scalars (-b/--base, -n/--name, --branch-repo), and
# the --agent handle (@claude, @copilot, @jules).
# Unknown flags produce an error with a hint to use --.
#
# Example: _parse_issue_develop_args num checkout base name branch_repo agent 42 -c -b develop
_parse_issue_develop_args() {
	local -n gh_issue_number_ref="$1"
	local -n gh_checkout_ref="$2"
	local -n gh_develop_base_ref="$3"
	local -n gh_develop_name_ref="$4"
	local -n gh_develop_branch_repo_ref="$5"
	local -n gh_agent_ref="$6"
	shift 6

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
		--base | -b)
			if ((i + 1 >= ${#raw_args[@]})); then
				echo "error: ${raw_args[$i]} requires a value" >&2
				return 1
			fi
			gh_develop_base_ref="${raw_args[$((i + 1))]}"
			skip_next=true
			;;
		--base=*)
			# shellcheck disable=SC2034
			gh_develop_base_ref="${raw_args[$i]#--base=}"
			;;
		--name | -n)
			if ((i + 1 >= ${#raw_args[@]})); then
				echo "error: ${raw_args[$i]} requires a value" >&2
				return 1
			fi
			gh_develop_name_ref="${raw_args[$((i + 1))]}"
			skip_next=true
			;;
		--name=*)
			# shellcheck disable=SC2034
			gh_develop_name_ref="${raw_args[$i]#--name=}"
			;;
		--branch-repo)
			if ((i + 1 >= ${#raw_args[@]})); then
				echo "error: ${raw_args[$i]} requires a value" >&2
				return 1
			fi
			gh_develop_branch_repo_ref="${raw_args[$((i + 1))]}"
			skip_next=true
			;;
		--branch-repo=*)
			# shellcheck disable=SC2034
			gh_develop_branch_repo_ref="${raw_args[$i]#--branch-repo=}"
			;;
		# -c mirrors the short form of `gh issue develop --checkout`
		--checkout | -c)
			# shellcheck disable=SC2034
			gh_checkout_ref=true
			;;
		--agent)
			if ((i + 1 >= ${#raw_args[@]})); then
				echo "error: ${raw_args[$i]} requires a value" >&2
				return 1
			fi
			gh_agent_ref="${raw_args[$((i + 1))]}"
			skip_next=true
			;;
		--agent=*)
			# shellcheck disable=SC2034
			gh_agent_ref="${raw_args[$i]#--agent=}"
			;;
		-*)
			echo "error: unknown flag '${raw_args[$i]}' (use -- to pass flags to gh pr create)" >&2
			return 1
			;;
		*)
			if [[ -z "$gh_issue_number_ref" && "${raw_args[$i]}" =~ ^[0-9]+$ ]]; then
				gh_issue_number_ref="${raw_args[$i]}"
			else
				echo "error: unexpected argument '${raw_args[$i]}'" >&2
				return 1
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
    gh ai issue develop <ISSUE_NUMBER> [-c] [-b BASE] [-n NAME] [--branch-repo REPO] [--agent HANDLE] [-- OPTIONS]

DESCRIPTION:
    Creates a development branch from a GitHub issue, generates an AI
    implementation plan, and opens a pull request with that plan.

    Combines gh issue develop (branch creation) with gh pr create
    (pull request). Title and body are AI-generated from the issue.
    Options after -- are passed directly to gh pr create.

    With --agent, the AI-generated plan is passed as a prompt to the
    specified agent CLI. No branch or PR is created locally.

BRANCH FLAGS (gh issue develop):
    -b, --base string          Name of the remote branch to branch from
    -n, --name string          Name of the branch to create
        --branch-repo string   Name or URL of the repo for the new branch

WORKFLOW FLAGS:
    -c, --checkout             Check out the new branch locally after creating it.
                               Default: branch is created remotely and an initial commit
                               is added without switching your working tree.
        --agent HANDLE         Delegate implementation to a remote AI agent.
                               Supported: @claude, @copilot, @jules

EXAMPLES:
    gh ai issue develop 42
    gh ai issue develop 42 --checkout
    gh ai issue develop 42 -b develop -- --draft
    gh ai issue develop 42 -- --label enhancement --reviewer monalisa
    gh ai issue develop 42 --agent @claude
    gh ai issue develop 42 --agent @copilot
    gh ai issue develop 42 --agent @jules
EOF
}

# Delegate issue development to a remote AI agent.
#
# Renders the agent instruction template from the AI-generated plan and
# pipes the result to the appropriate agent CLI via _cmd_assist_remotely.
# No branch or PR is created locally — the agent handles everything.
#
# Usage: _gh_issue_develop_remotely <agent> <issue_number> <pr_title> <pr_body>
_gh_issue_develop_remotely() {
	local gh_agent="$1"
	local gh_issue_number="$2"
	local gh_pr_title="$3"
	local gh_pr_body="$4"

	local agent_template_file
	# shellcheck disable=SC2154
	agent_template_file="$_gh_ai_source_dir/templates/gh_issue_develop_agent.tmpl"

	local agent_prompt
	agent_prompt=$(
		GH_PR_TITLE="$gh_pr_title" GH_PR_BODY="$gh_pr_body" \
			"$_gh_ai_source_dir/scripts/gh_cmd.sh" render "$agent_template_file"
	)

	local gh_repo
	gh_repo=$(gh repo view --json nameWithOwner -q '.nameWithOwner')

	gum spin --title "Delegating GitHub issue #$gh_issue_number to $gh_agent..." -- \
		"$_gh_ai_source_dir/scripts/gh_cmd.sh" remotely "$gh_agent" "$gh_repo" "$agent_prompt"

	gum log --level info "GitHub Issue #$gh_issue_number delegated to $gh_agent"
}

# No-checkout develop path: create branch remotely via commit-tree
#
# Creates the development branch using `gh issue develop`, adds an initial
# empty commit via git commit-tree without switching the local working tree,
# then opens a pull request with --head set to the new branch.
#
# Usage: _gh_issue_develop_no_checkout <issue_number> <pr_title> <pr_body> <issue_args_name> <passthrough_name>
_gh_issue_develop_no_checkout() {
	local gh_issue_number="$1"
	local gh_pr_title="$2"
	local gh_pr_body="$3"
	local -n _issue_args_ref="$4"
	local -n _passthrough_ref="$5"

	local gh_develop_url
	gh_develop_url=$(gum spin --title "Creating Git branch #$gh_issue_number..." -- \
		gh issue develop "$gh_issue_number" "${_issue_args_ref[@]}")
	if [[ -z "$gh_develop_url" ]]; then
		gum log --level error "Failed to create development branch for #$gh_issue_number"
		return 1
	fi

	# gh issue develop outputs a GitHub web URL ending with /tree/<branch>.
	# Strip the prefix rather than using basename to handle branch names
	# that contain '/' (e.g. feature/my-topic).
	local git_branch_name
	git_branch_name="${gh_develop_url##*/tree/}"
	if [[ -z "$git_branch_name" ]]; then
		gum log --level error "Failed to determine branch name from: $gh_develop_url"
		return 1
	fi

	gum spin --title "Fetching Git branch $git_branch_name..." -- \
		git fetch origin "$git_branch_name"

	local git_tree_sha
	# shellcheck disable=SC1083  # braces are git rev-parse syntax, not a shell expansion
	git_tree_sha=$(git rev-parse FETCH_HEAD^{tree})

	local git_parent_sha
	git_parent_sha=$(git rev-parse FETCH_HEAD)

	local git_commit_sha
	git_commit_sha=$(git commit-tree "$git_tree_sha" -p "$git_parent_sha" \
		-m "chore: start work on #$gh_issue_number")

	gum spin --title "Pushing Git initial commit..." -- \
		git push origin "$git_commit_sha:refs/heads/$git_branch_name"

	# Create the pull request, explicitly naming the head branch
	gh pr create --title "$gh_pr_title" --body "$gh_pr_body" \
		--head "$git_branch_name" "${_passthrough_ref[@]}"
}

# Issue Develop implementation
#
# Creates a development branch from an issue, generates an AI implementation
# plan, and opens a pull request with that plan as the body.
# Uses native `gh issue develop` for branch creation.
#
# Usage: _gh_issue_develop <ISSUE_NUMBER> [-c] [-b BASE] [-n NAME] [--branch-repo REPO] [--agent HANDLE] [-- OPTIONS]
_gh_issue_develop() {
	case "${1:-}" in
	--help | -h | help)
		_show_issue_develop_help
		return 0
		;;
	esac

	local ai_args=()
	local passthrough=()
	_split_on_separator ai_args passthrough "$@"

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_ai_source_dir/templates/gh_issue_develop.tmpl"

	local gh_issue_number=""
	local gh_checkout=false
	local gh_develop_base=""
	local gh_develop_name=""
	local gh_develop_branch_repo=""
	local gh_agent=""
	_parse_issue_develop_args gh_issue_number gh_checkout gh_develop_base gh_develop_name gh_develop_branch_repo gh_agent "${ai_args[@]}"

	if [[ -n "$gh_agent" ]]; then
		case "$gh_agent" in
		@claude | @jules | @copilot) ;;
		*)
			gum log --level error "Unknown agent '$gh_agent' (supported: @claude, @jules, @copilot)"
			return 1
			;;
		esac
	fi

	# Build gh issue develop args from scalars
	local gh_issue_args=()
	[[ -n "$gh_develop_base" ]] && gh_issue_args+=("--base" "$gh_develop_base")
	[[ -n "$gh_develop_name" ]] && gh_issue_args+=("--name" "$gh_develop_name")
	[[ -n "$gh_develop_branch_repo" ]] && gh_issue_args+=("--branch-repo" "$gh_develop_branch_repo")

	if [[ -z "$gh_issue_number" ]]; then
		gum log --level error "No issue number provided"
		gum log --level info "Usage: gh ai issue develop <ISSUE_NUMBER> [-- OPTIONS]"
		return 1
	fi

	# Fetch issue metadata
	local gh_issue_eval
	gh_issue_eval=$(gum spin --title "Fetching GitHub issue metadata..." -- \
		gh issue view "$gh_issue_number" --json title,body,labels,comments \
		-q "$(<"$_gh_ai_source_dir/scripts/gh_issue_meta.jq")" || true)
	if [[ -z "$gh_issue_eval" ]]; then
		gum log --level error "Failed to fetch issue #$gh_issue_number"
		return 1
	fi

	local gh_issue_title gh_issue_body gh_issue_labels gh_issue_comments
	eval "$gh_issue_eval"

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

	if [[ -n "$gh_agent" ]]; then
		_gh_issue_develop_remotely "$gh_agent" "$gh_issue_number" "$gh_pr_title" "$gh_pr_body"
		return 0
	fi

	if [ "$gh_checkout" = "true" ]; then
		# Standard approach: checkout branch locally
		gum spin --title "Creating Git branch #$gh_issue_number..." -- \
			gh issue develop "$gh_issue_number" --checkout "${gh_issue_args[@]}"

		# Empty commit so the PR has a diff against the base branch
		git commit --allow-empty -m "chore: start work on #$gh_issue_number"
		gum spin --title "Pushing Git initial commit..." -- git push -u origin HEAD

		# Create the pull request
		gh pr create --title "$gh_pr_title" --body "$gh_pr_body" "${passthrough[@]}"
	else
		_gh_issue_develop_no_checkout "$gh_issue_number" "$gh_pr_title" "$gh_pr_body" gh_issue_args passthrough
	fi
}

# Issue create help function
#
# Displays help information for the issue create command
# including usage examples and available options.
_show_issue_create_help() {
	cat <<'EOF'
gh ai issue create - Create issues with AI-generated content

USAGE:
    gh ai issue create -d <DESCRIPTION> [-- GH_ISSUE_CREATE_OPTIONS]

DESCRIPTION:
    Creates a GitHub issue with an AI-generated title and structured body
    from a brief description. Supports piped stdin as additional context.
    Options after -- are passed directly to gh issue create.

FLAGS:
    -d, --description string   Brief description of the issue (required)

EXAMPLES:
    gh ai issue create -d "Login page crashes with special chars"
    gh ai issue create -d "Login crash" -- --label bug --assignee @me
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
# Usage: _gh_issue_create -d <DESCRIPTION> [-- OPTIONS]
_gh_issue_create() {
	case "${1:-}" in
	--help | -h | help)
		_show_issue_create_help
		return 0
		;;
	esac

	local ai_args=()
	local passthrough=()
	_split_on_separator ai_args passthrough "$@"

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_ai_source_dir/templates/gh_issue_create.tmpl"

	local gh_issue_description=""
	_parse_issue_create_args gh_issue_description "${ai_args[@]}"

	# If no description, error out
	if [[ -z "$gh_issue_description" ]]; then
		gum log --level error "No description provided"
		gum log --level info "Usage: gh ai issue create -d <DESCRIPTION> [-- OPTIONS]"
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
				GH_ISSUE_DESCRIPTION="$gh_issue_description" GH_ISSUE_LABELS="" GH_ISSUE_CONTEXT="$gh_issue_context" \
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
	gh issue create --title "$gh_issue_title" --body "$gh_issue_body" "${passthrough[@]}"
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
