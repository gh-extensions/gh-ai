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
    gh ai issue plan <ISSUE_NUMBER>
    gh ai issue chat <ISSUE_NUMBER> [-d <DESCRIPTION>] [-- AGENT_OPTIONS]

DESCRIPTION:
    Creates and edits GitHub issues with AI-generated titles and structured
    bodies. Generates implementation plans from issues and prints them to stdout.
    Opens agent sessions with issue context.

COMMANDS:
    create      Create issues with AI-generated content
    edit        Edit an existing issue with AI-generated content
    plan        Generate an AI implementation plan from an issue
    chat        Open an agent session with issue context

SEE ALSO:
    gh ai issue create --help     # Issue create usage
    gh ai issue edit --help       # Issue edit usage
    gh ai issue plan --help       # Issue plan usage
    gh ai issue chat --help       # Issue chat usage
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
				gum log --level error "${raw_args[$i]} requires a value"
				return 1
			fi
			gh_issue_description_ref="${raw_args[$((i + 1))]}"
			skip_next=true
			;;
		--description=*)
			gh_issue_description_ref="${raw_args[$i]#--description=}"
			;;
		-*)
			gum log --level error "unknown flag '${raw_args[$i]}' (use -- to pass flags to gh issue create)"
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
				gum log --level error "${raw_args[$i]} requires a value"
				return 1
			fi
			gh_issue_description_ref="${raw_args[$((i + 1))]}"
			skip_next=true
			;;
		--description=*)
			# shellcheck disable=SC2034 # nameref: set by caller
			gh_issue_description_ref="${raw_args[$i]#--description=}"
			;;
		-*)
			gum log --level error "unknown flag '${raw_args[$i]}' (use -- to pass flags to gh issue edit)"
			return 1
			;;
		*)
			local arg="${raw_args[$i]#\#}"
			if [[ -z "$gh_issue_number_ref" && "$arg" =~ ^[0-9]+$ ]]; then
				gh_issue_number_ref="$arg"
			else
				gum log --level error "unexpected argument '${raw_args[$i]}'"
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
	gh_issue_eval=$(gum spin --title "Fetching GitHub issue #$gh_issue_number metadata..." -- \
		gh issue view "$gh_issue_number" --json title,body,labels,comments \
		-q "$(<"$_gh_ai_source_dir/scripts/gh_issue_meta.jq")" || true)
	if [[ -z "$gh_issue_eval" ]]; then
		gum log --level error "Failed to fetch issue #$gh_issue_number"
		return 1
	fi

	local gh_issue_title gh_issue_body gh_issue_labels gh_issue_comments
	eval "$gh_issue_eval"

	local agent_model
	agent_model=$(gh config get ai.issue.model 2>/dev/null || true)

	local output
	# Generate updated issue content using assistant
	output=$(
		gum spin --title "Generating updated GitHub issue #$gh_issue_number..." -- \
			"$_gh_ai_source_dir/scripts/gh_cmd.sh" ask "$agent_model" < <(
				GH_ISSUE_NUMBER="$gh_issue_number" \
					GH_ISSUE_TITLE="$gh_issue_title" \
					GH_ISSUE_BODY="$gh_issue_body" \
					GH_ISSUE_LABELS="$gh_issue_labels" \
					GH_ISSUE_COMMENTS="$gh_issue_comments" \
					GH_ISSUE_DESCRIPTION="$gh_issue_description" \
					GH_ISSUE_CONTEXT="$gh_issue_context" \
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
	if ! gh_issue_new_title=$(_parse_title "$output"); then
		gum log --level error "Failed to extract title from AI content"
		return 1
	fi

	local gh_issue_new_body
	# Parse body from output
	gh_issue_new_body=$(_parse_body "$output")

	# Edit issue with AI-generated content
	gh issue edit "$gh_issue_number" --title "$gh_issue_new_title" --body "$gh_issue_new_body" "${passthrough[@]}"
}

# Parse issue plan arguments
#
# Extracts the issue number (first numeric positional arg) and optional
# -d/--description value. Unknown flags produce an error.
#
# Example: _parse_issue_plan_args num desc 42 -d "focus on auth"
_parse_issue_plan_args() {
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
				gum log --level error "${raw_args[$i]} requires a value"
				return 1
			fi
			gh_issue_description_ref="${raw_args[$((i + 1))]}"
			skip_next=true
			;;
		--description=*)
			# shellcheck disable=SC2034 # nameref: set by caller
			gh_issue_description_ref="${raw_args[$i]#--description=}"
			;;
		-*)
			gum log --level error "unknown flag '${raw_args[$i]}'"
			return 1
			;;
		*)
			local arg="${raw_args[$i]#\#}"
			if [[ -z "$gh_issue_number_ref" && "$arg" =~ ^[0-9]+$ ]]; then
				gh_issue_number_ref="$arg"
			else
				gum log --level error "unexpected argument '${raw_args[$i]}'"
				return 1
			fi
			;;
		esac
		((++i))
	done
}

# Issue plan help function
#
# Displays help information for the issue plan command
# including usage examples and available options.
_show_issue_plan_help() {
	cat <<'EOF'
gh ai issue plan - Generate an AI implementation plan from a GitHub issue

USAGE:
    gh ai issue plan <ISSUE_NUMBER> [-d <DESCRIPTION>]

DESCRIPTION:
    Fetches the GitHub issue and generates an AI implementation plan,
    printing it to stdout. Compose it with any tool using pipes.
    Use -d to provide extra context or constraints that guide the AI.

FLAGS:
    -d, --description string   Extra context or focus for the plan (optional)

EXAMPLES:
    gh ai issue plan 42
    gh ai issue plan 42 -d "focus on the auth module"
    gh ai issue plan 42 | pbcopy
    gh ai issue plan 42 | claude
    gh ai issue plan 42 | jules new
    gh ai issue plan 42 | gh agent-task create --body -
    gh issue develop 42 --checkout && git commit --allow-empty -m "chore: start work on #42" && gh ai issue plan 42 | gh pr create --body -
EOF
}

# Issue Plan implementation
#
# Fetches a GitHub issue, generates an AI implementation plan,
# and prints it to stdout.
#
# Usage: _gh_issue_plan <NUMBER> [-d <DESCRIPTION>]
_gh_issue_plan() {
	case "${1:-}" in
	--help | -h | help)
		_show_issue_plan_help
		return 0
		;;
	esac

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_ai_source_dir/templates/gh_issue_plan.tmpl"

	local gh_issue_number=""
	local gh_issue_description=""
	_parse_issue_plan_args gh_issue_number gh_issue_description "$@"

	if [[ -z "$gh_issue_number" ]]; then
		gum log --level error "No issue number provided"
		gum log --level info "Usage: gh ai issue plan <ISSUE_NUMBER> [-d <DESCRIPTION>]"
		return 1
	fi

	# Fetch issue metadata
	local gh_issue_eval
	gh_issue_eval=$(gum spin --title "Fetching GitHub issue #$gh_issue_number metadata..." -- \
		gh issue view "$gh_issue_number" --json title,body,labels,comments \
		-q "$(<"$_gh_ai_source_dir/scripts/gh_issue_meta.jq")" || true)
	if [[ -z "$gh_issue_eval" ]]; then
		gum log --level error "Failed to fetch issue #$gh_issue_number"
		return 1
	fi

	local gh_issue_title gh_issue_body gh_issue_labels gh_issue_comments
	eval "$gh_issue_eval"

	local agent_model
	agent_model=$(gh config get ai.issue.model 2>/dev/null || true)

	local gh_issue_focus=""
	if [[ -n "$gh_issue_description" ]]; then
		gh_issue_focus="<focus>${gh_issue_description}</focus>"
	fi

	local output
	# Generate implementation plan using assistant
	output=$(
		gum spin --title "Generating GitHub issue #$gh_issue_number implementation plan..." -- \
			"$_gh_ai_source_dir/scripts/gh_cmd.sh" ask "$agent_model" < <(
				GH_ISSUE_NUMBER="$gh_issue_number" \
					GH_ISSUE_TITLE="$gh_issue_title" \
					GH_ISSUE_BODY="$gh_issue_body" \
					GH_ISSUE_LABELS="$gh_issue_labels" \
					GH_ISSUE_COMMENTS="$gh_issue_comments" \
					GH_ISSUE_FOCUS="$gh_issue_focus" \
					"$_gh_ai_source_dir/scripts/gh_cmd.sh" render "$template_file"
			)
	)

	# Validate we got content
	if [[ -z "$output" ]]; then
		gum log --level error "Failed to generate implementation plan"
		gum log --level info "Run with DEBUG=1 for detailed diagnostics"
		return 1
	fi

	printf '%s\n' "$output"
}

# Parse issue chat arguments
#
# Extracts the issue number (first numeric positional arg), optional
# -d/--description value, and -n/--new-session flag. Unknown flags produce an error.
#
# Example: _parse_issue_chat_args num desc new_session 42 -d "focus on auth"
_parse_issue_chat_args() {
	local -n gh_issue_number_ref="$1"
	local -n gh_issue_description_ref="$2"
	local -n gh_issue_new_session_ref="$3"
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
			if ((i + 1 >= ${#raw_args[@]})); then
				gum log --level error "${raw_args[$i]} requires a value"
				return 1
			fi
			gh_issue_description_ref="${raw_args[$((i + 1))]}"
			skip_next=true
			;;
		--description=*)
			# shellcheck disable=SC2034 # nameref: set by caller
			gh_issue_description_ref="${raw_args[$i]#--description=}"
			;;
		--new-session | -n)
			# shellcheck disable=SC2034 # nameref: set by caller
			gh_issue_new_session_ref=1
			;;
		-*)
			gum log --level error "unknown flag '${raw_args[$i]}' (use -- to pass flags to the agent)"
			return 1
			;;
		*)
			local arg="${raw_args[$i]#\#}"
			if [[ -z "$gh_issue_number_ref" && "$arg" =~ ^[0-9]+$ ]]; then
				gh_issue_number_ref="$arg"
			else
				gum log --level error "unexpected argument '${raw_args[$i]}'"
				return 1
			fi
			;;
		esac
		((++i))
	done
}

# Issue chat help function
#
# Displays help information for the issue chat command
# including usage examples and available options.
_show_issue_chat_help() {
	cat <<'EOF'
gh ai issue chat - Open an agent session with issue context

USAGE:
    gh ai issue chat <ISSUE_NUMBER> [-d <DESCRIPTION>] [-- AGENT_OPTIONS]

DESCRIPTION:
    Fetches the GitHub issue metadata, renders it as context, and pipes
    it into the configured agent binary (default: claude). Options after
    -- are passed directly to the agent.

    Configure the agent: gh config set ai.agent <binary>

FLAGS:
    -d, --description string   Extra context or focus for the agent (optional)
    -n, --new-session          Start a new session

EXAMPLES:
    gh ai issue chat 42
    gh ai issue chat 42 -d "focus on the auth module"
    gh ai issue chat 42 --new-session
    gh ai issue chat 42 -- --model sonnet
EOF
}

# Issue Chat implementation
#
# Fetches a GitHub issue, renders the context template, and pipes it
# into the configured agent binary.
#
# Usage: _gh_issue_chat <NUMBER> [-d <DESCRIPTION>] [-- AGENT_OPTIONS]
_gh_issue_chat() {
	case "${1:-}" in
	--help | -h | help)
		_show_issue_chat_help
		return 0
		;;
	esac

	local ai_args=()
	local passthrough=()
	_split_on_separator ai_args passthrough "$@"

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_ai_source_dir/templates/gh_issue_chat.tmpl"

	local gh_issue_number=""
	local gh_issue_description=""
	local gh_issue_new_session=""
	_parse_issue_chat_args gh_issue_number gh_issue_description gh_issue_new_session "${ai_args[@]}"

	if [[ -z "$gh_issue_number" ]]; then
		gum log --level error "No issue number provided"
		gum log --level info "Usage: gh ai issue chat <ISSUE_NUMBER> [-d <DESCRIPTION>] [-- AGENT_OPTIONS]"
		return 1
	fi

	# Try to resume existing session before expensive API calls
	local gh_repo=""
	_gh_repo_name gh_repo || return 1
	local gh_issue_url="https://github.com/${gh_repo}/issues/${gh_issue_number}"

	local session_args=()
	if _try_resume_chat_session session_args "$gh_issue_url" "$gh_issue_new_session" "${passthrough[@]}"; then
		_cmd_chat "" "${session_args[@]}" "${passthrough[@]}"
		return
	fi

	# Fetch issue metadata
	local gh_issue_eval
	gh_issue_eval=$(gum spin --title "Fetching GitHub issue #$gh_issue_number metadata..." -- \
		gh issue view "$gh_issue_number" --json title,body,labels,comments \
		-q "$(<"$_gh_ai_source_dir/scripts/gh_issue_meta.jq")" || true)
	if [[ -z "$gh_issue_eval" ]]; then
		gum log --level error "Failed to fetch issue #$gh_issue_number"
		return 1
	fi

	local gh_issue_title gh_issue_body gh_issue_labels gh_issue_comments
	eval "$gh_issue_eval"

	local gh_issue_focus=""
	if [[ -n "$gh_issue_description" ]]; then
		gh_issue_focus="<focus>${gh_issue_description}</focus>"
	fi

	# Render context and pipe to agent
	local preamble
	preamble=$(
		GH_ISSUE_NUMBER="$gh_issue_number" \
			GH_ISSUE_TITLE="$gh_issue_title" \
			GH_ISSUE_BODY="$gh_issue_body" \
			GH_ISSUE_LABELS="$gh_issue_labels" \
			GH_ISSUE_COMMENTS="$gh_issue_comments" \
			GH_ISSUE_FOCUS="$gh_issue_focus" \
			"$_gh_ai_source_dir/scripts/gh_cmd.sh" render "$template_file"
	)

	session_args=()
	_resolve_chat_session session_args "$gh_issue_url" "$gh_issue_new_session" "" "${passthrough[@]}"

	_cmd_chat "$preamble" "${session_args[@]}" "${passthrough[@]}"
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
	agent_model=$(gh config get ai.issue.model 2>/dev/null || true)

	local output
	# Generate issue content using assistant run
	output=$(
		gum spin --title "Generating GitHub issue..." -- \
			"$_gh_ai_source_dir/scripts/gh_cmd.sh" ask "$agent_model" < <(
				GH_ISSUE_DESCRIPTION="$gh_issue_description" \
					GH_ISSUE_LABELS="" \
					GH_ISSUE_CONTEXT="$gh_issue_context" \
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
	if ! gh_issue_title=$(_parse_title "$output"); then
		gum log --level error "Failed to extract title from AI content"
		return 1
	fi

	local gh_issue_body
	# Parse body from output
	gh_issue_body=$(_parse_body "$output")

	# Create issue with AI-generated content
	gh issue create --title "$gh_issue_title" --body "$gh_issue_body" "${passthrough[@]}"
}

# Issue subcommand handler
#
# Routes issue subcommands to their appropriate handler functions.
# Shows help for unknown commands.
#
# Usage: _gh_issue <subcommand> [OPTIONS]
# Subcommands: create, edit, plan, chat, help
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
	plan)
		_gh_issue_plan "$@"
		;;
	chat)
		_gh_issue_chat "$@"
		;;
	--help | -h | help | "")
		_show_issue_help
		;;
	*)
		gum log --level error "Unknown issue command '$subcommand'"
		gum log --level info "Available commands: create, edit, plan, chat"
		gum log --level info "Run 'gh ai issue --help' for usage information"
		return 1
		;;
	esac
}
