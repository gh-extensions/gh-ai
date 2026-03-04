#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# Issue-related functions for gh-ai

# Shared argument parser for issue commands that accept an issue number and -d/--description.
#
# Extracts the issue number (first numeric arg) and -d/--description value.
# Unknown flags produce an error; if subcmd is non-empty, the error hints to use --.
#
# Usage: _parse_issue_args subcmd num_ref desc_ref [args...]
_parse_issue_args() {
	local _pia_subcmd="$1"
	local -n _pia_num="$2"
	local -n _pia_desc="$3"
	shift 3

	local _pia_raw=("$@")
	local _pia_skip=false
	local _pia_i=0

	while [[ $_pia_i -lt ${#_pia_raw[@]} ]]; do
		if [[ "$_pia_skip" = true ]]; then
			_pia_skip=false
			((++_pia_i))
			continue
		fi

		case "${_pia_raw[$_pia_i]}" in
		--description | -d)
			if ((_pia_i + 1 >= ${#_pia_raw[@]})); then
				gum log --level error "${_pia_raw[$_pia_i]} requires a value"
				return 1
			fi
			# shellcheck disable=SC2034 # nameref: set by caller
			_pia_desc="${_pia_raw[$((_pia_i + 1))]}"
			_pia_skip=true
			;;
		--description=*)
			# shellcheck disable=SC2034 # nameref: set by caller
			_pia_desc="${_pia_raw[$_pia_i]#--description=}"
			;;
		-*)
			if [[ -n "$_pia_subcmd" ]]; then
				gum log --level error "unknown flag '${_pia_raw[$_pia_i]}' (use -- to pass flags to gh issue $_pia_subcmd)"
			else
				gum log --level error "unknown flag '${_pia_raw[$_pia_i]}'"
			fi
			return 1
			;;
		*)
			local _pia_arg="${_pia_raw[$_pia_i]#\#}"
			if [[ -z "$_pia_num" && "$_pia_arg" =~ ^[0-9]+$ ]]; then
				_pia_num="$_pia_arg"
			else
				gum log --level error "unexpected argument '${_pia_raw[$_pia_i]}'"
				return 1
			fi
			;;
		esac
		((++_pia_i))
	done
}

# Shared context helper for existing-issue commands.
#
# Fetches issue metadata, saves context files to the context directory,
# and populates the output variables via namerefs. Reads optional stdin
# into issue_context.md.
#
# When type is "chat" the context is written to the persistent session directory
# .claude/sessions/issue-<num> so Claude can resume across invocations.
# For all other types a temporary directory is created.
#
# Usage: _prepare_issue_context type issue_number dir_ref title_ref labels_ref
_prepare_issue_context() {
	local _ctx_type="$1"
	local _ctx_num="$2"
	local -n _ctx_dir="$3"
	local -n _ctx_title="$4"
	local -n _ctx_labels="$5"

	local _ctx_meta
	_ctx_meta=$(gum spin --title "Fetching GitHub issue #$_ctx_num metadata..." -- \
		gh issue view "$_ctx_num" --json title,body,labels,comments || true)
	if [[ -z "$_ctx_meta" ]]; then
		gum log --level error "Failed to fetch issue #$_ctx_num"
		return 1
	fi

	# Single jq pass: extract all fields via eval
	local _ctx_body="" _ctx_comments=""
	# shellcheck disable=SC2154
	eval "$(printf '%s' "$_ctx_meta" | jq -rf "$_gh_ai_source_dir/scripts/gh_issue_meta.jq")"

	_resolve_context_dir "$_ctx_type" "issue-$_ctx_num" _ctx_dir || return 1

	local _ctx_context=""
	if [[ ! -t 0 ]]; then
		_ctx_context=$(cat)
	fi

	_save_context_file "$_ctx_dir" "issue_body.md" "$_ctx_body"
	_save_context_file "$_ctx_dir" "issue_comments.md" "$_ctx_comments"
	_save_context_file "$_ctx_dir" "issue_context.md" "$_ctx_context"
}

# Parse issue create arguments (before -- separator)
#
# Extracts -d/--description value. Unknown flags produce an error
# with a hint to use --.
#
# Usage: _parse_issue_create_args desc_ref [args...]
_parse_issue_create_args() {
	local -n _pica_desc="$1"
	shift

	local _pica_raw=("$@")
	local _pica_skip=false
	local _pica_i=0

	while [[ $_pica_i -lt ${#_pica_raw[@]} ]]; do
		if [[ "$_pica_skip" = true ]]; then
			_pica_skip=false
			((++_pica_i))
			continue
		fi

		case "${_pica_raw[$_pica_i]}" in
		--description | -d)
			if ((_pica_i + 1 >= ${#_pica_raw[@]})); then
				gum log --level error "${_pica_raw[$_pica_i]} requires a value"
				return 1
			fi
			# shellcheck disable=SC2034 # nameref: set by caller
			_pica_desc="${_pica_raw[$((_pica_i + 1))]}"
			_pica_skip=true
			;;
		--description=*)
			# shellcheck disable=SC2034 # nameref: set by caller
			_pica_desc="${_pica_raw[$_pica_i]#--description=}"
			;;
		-*)
			gum log --level error "unknown flag '${_pica_raw[$_pica_i]}' (use -- to pass flags to gh issue create)"
			return 1
			;;
		*)
			gum log --level error "unexpected argument '${_pica_raw[$_pica_i]}'"
			return 1
			;;
		esac
		((++_pica_i))
	done
}

# Context for _gh_issue_create: creates the context directory and reads optional stdin into issue_context.md.
#
# Usage: _prepare_issue_create_context dir_ref
_prepare_issue_create_context() {
	local -n _ctx_dir="$1"

	local _ctx_dir_path
	_create_context_dir _ctx_dir_path
	_ctx_dir="$_ctx_dir_path"

	local _ctx_context=""
	if [[ ! -t 0 ]]; then
		_ctx_context=$(cat)
	fi

	_save_context_file "$_ctx_dir" "issue_context.md" "$_ctx_context"
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
# Renders a prompt template with the description and optional stdin context,
# sends it to the AI provider, and parses the response.
#
# Usage: _gh_issue_create -d <DESCRIPTION> [-- OPTIONS]
_gh_issue_create() {
	case "${1:-}" in
	--help | -h | help)
		_show_issue_create_help
		return 0
		;;
	esac

	local args=()
	local passthrough=()
	_split_on_separator args passthrough "$@"

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_ai_source_dir/templates/gh_issue_create.tmpl"

	local gh_issue_description=""
	_parse_issue_create_args gh_issue_description "${args[@]}"

	if [[ -z "$gh_issue_description" ]]; then
		gum log --level error "No description provided"
		gum log --level info "Usage: gh ai issue create -d <DESCRIPTION> [-- OPTIONS]"
		return 1
	fi

	local gh_issue_dir=""
	_prepare_issue_create_context gh_issue_dir || return 1

	local gh_issue_agent_model
	gh_issue_agent_model=$(gh config get ai.issue.model 2>/dev/null || true)

	local gh_issue_content
	# Generate issue content using assistant run
	# *_FILE vars are read by 'gh_cmd.sh render' and inlined as their non-FILE counterparts.
	gh_issue_content=$(
		gum spin --title "Generating GitHub issue..." -- \
			"$_gh_ai_source_dir/scripts/gh_cmd.sh" ask "$gh_issue_agent_model" < <(
				GH_ISSUE_DESCRIPTION="$gh_issue_description" \
					GH_ISSUE_LABELS="" \
					GH_ISSUE_CONTEXT_FILE="$gh_issue_dir/issue_context.md" \
					"$_gh_ai_source_dir/scripts/gh_cmd.sh" render "$template_file"
			)
	)

	# Clean up the temp context directory now that the AI call is done.
	rm -rf "$gh_issue_dir"

	# Validate we got issue content
	if [[ -z "$gh_issue_content" ]]; then
		gum log --level error "Failed to generate issue content"
		gum log --level info "Run with DEBUG=1 for detailed diagnostics"
		return 1
	fi

	local gh_issue_title
	# Parse title from output
	if ! gh_issue_title=$(_parse_title "$gh_issue_content"); then
		gum log --level error "Failed to extract title from AI content"
		return 1
	fi

	local gh_issue_body
	# Parse body from output
	gh_issue_body=$(_parse_body "$gh_issue_content")

	# Create issue with AI-generated content
	gh issue create --title "$gh_issue_title" --body "$gh_issue_body" "${passthrough[@]}"
}

# Parse issue edit arguments (before -- separator).
#
# Extracts issue number and -d/--description from args. Unknown flags hint to use --.
_parse_issue_edit_args() { _parse_issue_args "edit" "$@"; }

# Fetches issue metadata into a temp directory for use by _gh_issue_edit.
_prepare_issue_edit_context() { _prepare_issue_context "edit" "$@"; }

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
#
# Usage: _gh_issue_edit <NUMBER> -d <DESCRIPTION> [-- OPTIONS]
_gh_issue_edit() {
	case "${1:-}" in
	--help | -h | help)
		_show_issue_edit_help
		return 0
		;;
	esac

	local args=()
	local passthrough=()
	_split_on_separator args passthrough "$@"

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_ai_source_dir/templates/gh_issue_edit.tmpl"

	local gh_issue_number="" gh_issue_description=""
	_parse_issue_edit_args gh_issue_number gh_issue_description "${args[@]}"

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

	local gh_issue_dir="" gh_issue_title="" gh_issue_labels=""
	_prepare_issue_edit_context "$gh_issue_number" gh_issue_dir gh_issue_title gh_issue_labels || return 1

	local gh_issue_agent_model
	gh_issue_agent_model=$(gh config get ai.issue.model 2>/dev/null || true)

	local gh_issue_content
	# Generate updated issue content using assistant
	# *_FILE vars are read by 'gh_cmd.sh render' and inlined as their non-FILE counterparts.
	gh_issue_content=$(
		gum spin --title "Generating updated GitHub issue #$gh_issue_number..." -- \
			"$_gh_ai_source_dir/scripts/gh_cmd.sh" ask "$gh_issue_agent_model" < <(
				GH_ISSUE_NUMBER="$gh_issue_number" \
					GH_ISSUE_TITLE="$gh_issue_title" \
					GH_ISSUE_BODY_FILE="$gh_issue_dir/issue_body.md" \
					GH_ISSUE_LABELS="$gh_issue_labels" \
					GH_ISSUE_COMMENTS_FILE="$gh_issue_dir/issue_comments.md" \
					GH_ISSUE_DESCRIPTION="$gh_issue_description" \
					GH_ISSUE_CONTEXT_FILE="$gh_issue_dir/issue_context.md" \
					"$_gh_ai_source_dir/scripts/gh_cmd.sh" render "$template_file"
			)
	)

	# Clean up the temp context directory now that the AI call is done.
	rm -rf "$gh_issue_dir"

	# Validate we got issue content
	if [[ -z "$gh_issue_content" ]]; then
		gum log --level error "Failed to generate updated issue content"
		gum log --level info "Run with DEBUG=1 for detailed diagnostics"
		return 1
	fi

	# Parse title from output
	if ! gh_issue_title=$(_parse_title "$gh_issue_content"); then
		gum log --level error "Failed to extract title from AI content"
		return 1
	fi

	local gh_issue_body
	# Parse body from output
	gh_issue_body=$(_parse_body "$gh_issue_content")

	# Edit issue with AI-generated content
	gh issue edit "$gh_issue_number" --title "$gh_issue_title" --body "$gh_issue_body" "${passthrough[@]}"
}

# Parse issue comment arguments (before -- separator).
#
# Extracts issue number and -d/--description from args. Unknown flags hint to use --.
_parse_issue_comment_args() { _parse_issue_args "comment" "$@"; }

# Fetches issue metadata into a temp directory for use by _gh_issue_comment.
_prepare_issue_comment_context() { _prepare_issue_context "comment" "$@"; }

# Issue comment help function
#
# Displays help information for the issue comment command
# including usage examples and available options.
_show_issue_comment_help() {
	cat <<'EOF'
gh ai issue comment - Post an AI-generated comment on an existing issue

USAGE:
    gh ai issue comment <ISSUE_NUMBER> -d <DESCRIPTION> [-- GH_ISSUE_COMMENT_OPTIONS]

DESCRIPTION:
    Posts an AI-generated comment on an existing GitHub issue. Fetches the
    current issue content and existing comments for context, generates the
    comment body via AI, and posts it. Supports piped stdin as additional
    context. Options after -- are passed directly to gh issue comment.

FLAGS:
    -d, --description string   Instructions for the comment (required)

EXAMPLES:
    gh ai issue comment 42 -d "post a status update: implementation is in progress"
    gh ai issue comment 42 -d "acknowledge the report and ask for more details"
    gh ai issue comment 42 -d "summarize the discussion so far"
    echo "error: connection refused" | gh ai issue comment 42 -d "add this error as context"
    some_command 2>&1 | gh ai issue comment 42 -d "add the output as context"
    gh ai issue comment 42 -d "acknowledge the report" -- --edit
EOF
}

# Issue Comment implementation
#
# Posts an AI-generated comment on an existing GitHub issue.
# Fetches the current issue, renders a prompt template with the
# description and issue context, sends it to the AI provider,
# and posts the comment.
#
# Usage: _gh_issue_comment <NUMBER> -d <DESCRIPTION> [-- OPTIONS]
_gh_issue_comment() {
	case "${1:-}" in
	--help | -h | help)
		_show_issue_comment_help
		return 0
		;;
	esac

	local args=()
	local passthrough=()
	_split_on_separator args passthrough "$@"

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_ai_source_dir/templates/gh_issue_comment.tmpl"

	local gh_issue_number="" gh_issue_description=""
	_parse_issue_comment_args gh_issue_number gh_issue_description "${args[@]}"

	if [[ -z "$gh_issue_number" ]]; then
		gum log --level error "No issue number provided"
		gum log --level info "Usage: gh ai issue comment <ISSUE_NUMBER> -d <DESCRIPTION> [-- OPTIONS]"
		return 1
	fi

	if [[ -z "$gh_issue_description" ]]; then
		gum log --level error "No description provided"
		gum log --level info "Usage: gh ai issue comment <ISSUE_NUMBER> -d <DESCRIPTION> [-- OPTIONS]"
		return 1
	fi

	local gh_issue_dir="" gh_issue_title="" gh_issue_labels=""
	_prepare_issue_comment_context "$gh_issue_number" gh_issue_dir gh_issue_title gh_issue_labels || return 1

	local gh_issue_agent_model
	gh_issue_agent_model=$(gh config get ai.issue.model 2>/dev/null || true)

	local gh_issue_comment
	# Generate comment using assistant
	# *_FILE vars are read by 'gh_cmd.sh render' and inlined as their non-FILE counterparts.
	gh_issue_comment=$(
		gum spin --title "Generating comment for GitHub issue #$gh_issue_number..." -- \
			"$_gh_ai_source_dir/scripts/gh_cmd.sh" ask "$gh_issue_agent_model" < <(
				GH_ISSUE_NUMBER="$gh_issue_number" \
					GH_ISSUE_TITLE="$gh_issue_title" \
					GH_ISSUE_BODY_FILE="$gh_issue_dir/issue_body.md" \
					GH_ISSUE_LABELS="$gh_issue_labels" \
					GH_ISSUE_COMMENTS_FILE="$gh_issue_dir/issue_comments.md" \
					GH_ISSUE_DESCRIPTION="$gh_issue_description" \
					GH_ISSUE_CONTEXT_FILE="$gh_issue_dir/issue_context.md" \
					"$_gh_ai_source_dir/scripts/gh_cmd.sh" render "$template_file"
			)
	)

	# Clean up the temp context directory now that the AI call is done.
	rm -rf "$gh_issue_dir"

	# Validate we got comment content
	if [[ -z "$gh_issue_comment" ]]; then
		gum log --level error "Failed to generate comment content"
		gum log --level info "Run with DEBUG=1 for detailed diagnostics"
		return 1
	fi

	# Post comment with AI-generated content
	gh issue comment "$gh_issue_number" --body "$gh_issue_comment" "${passthrough[@]}"
}

# Parse issue plan arguments.
#
# Extracts issue number and -d/--description from args. Unknown flags produce an error.
_parse_issue_plan_args() { _parse_issue_args "" "$@"; }

# Fetches issue metadata into a temp directory for use by _gh_issue_plan.
_prepare_issue_plan_context() { _prepare_issue_context "plan" "$@"; }

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

	local gh_issue_number="" gh_issue_description=""
	_parse_issue_plan_args gh_issue_number gh_issue_description "$@"

	if [[ -z "$gh_issue_number" ]]; then
		gum log --level error "No issue number provided"
		gum log --level info "Usage: gh ai issue plan <ISSUE_NUMBER> [-d <DESCRIPTION>]"
		return 1
	fi

	local gh_issue_dir="" gh_issue_title="" gh_issue_labels=""
	_prepare_issue_plan_context "$gh_issue_number" gh_issue_dir gh_issue_title gh_issue_labels || return 1

	local gh_issue_agent_model
	gh_issue_agent_model=$(gh config get ai.issue.model 2>/dev/null || true)

	local gh_issue_focus=""
	if [[ -n "$gh_issue_description" ]]; then
		gh_issue_focus="<focus>${gh_issue_description}</focus>"
	fi

	local gh_issue_plan
	# Generate implementation plan using assistant
	# *_FILE vars are read by 'gh_cmd.sh render' and inlined as their non-FILE counterparts.
	gh_issue_plan=$(
		gum spin --title "Generating GitHub issue #$gh_issue_number implementation plan..." -- \
			"$_gh_ai_source_dir/scripts/gh_cmd.sh" ask "$gh_issue_agent_model" < <(
				GH_ISSUE_NUMBER="$gh_issue_number" \
					GH_ISSUE_TITLE="$gh_issue_title" \
					GH_ISSUE_BODY_FILE="$gh_issue_dir/issue_body.md" \
					GH_ISSUE_LABELS="$gh_issue_labels" \
					GH_ISSUE_COMMENTS_FILE="$gh_issue_dir/issue_comments.md" \
					GH_ISSUE_FOCUS="$gh_issue_focus" \
					GH_ISSUE_CONTEXT_FILE="$gh_issue_dir/issue_context.md" \
					"$_gh_ai_source_dir/scripts/gh_cmd.sh" render "$template_file"
			)
	)

	# Clean up the temp context directory now that the AI call is done.
	rm -rf "$gh_issue_dir"

	# Validate we got content
	if [[ -z "$gh_issue_plan" ]]; then
		gum log --level error "Failed to generate implementation plan"
		gum log --level info "Run with DEBUG=1 for detailed diagnostics"
		return 1
	fi

	printf '%s\n' "$gh_issue_plan"
}

# Thin wrapper around _parse_chat_args for the chat subcommand.
_parse_issue_chat_args() { _parse_chat_args "$@"; }

# Fetches issue metadata into .claude/sessions/issue-<num> for use by _gh_issue_chat.
# The session directory persists across invocations so Claude can resume context.
# _resolve_chat_session tracks the Claude session UUID separately via a
# "session.id" file written inside the session directory.
_prepare_issue_chat_context() { _prepare_issue_context "chat" "$@"; }

# Issue chat help function
#
# Displays help information for the issue chat command
# including usage examples and available options.
_show_issue_chat_help() {
	cat <<'EOF'
gh ai issue chat - Open an agent session with issue context

USAGE:
    gh ai issue chat <ISSUE_NUMBER> [-d <DESCRIPTION>] [-n] [-- AGENT_OPTIONS]

DESCRIPTION:
    Fetches the GitHub issue metadata, renders it as context, and pipes
    it into the configured agent binary (default: claude).
    Options after -- are passed directly to the agent binary.

    Configure the agent: gh config set ai.agent <binary>
    Configure the model: gh config set ai.issue.model <model>

FLAGS:
    -d, --description string   Extra context or focus for the agent (optional)
    -n, --new-session          Start a new session

EXAMPLES:
    gh ai issue chat 42
    gh ai issue chat 42 -d "focus on the auth module"
    gh ai issue chat 42 --new-session
    gh ai issue chat 42 -- --model sonnet --verbose
EOF
}

# Issue Chat implementation
#
# Fetches a GitHub issue, renders the context template, and pipes it
# into the configured agent binary. Session continuity is managed via
# _resolve_chat_session — subsequent invocations resume the previous
# session automatically; --new-session forces a fresh session ID.
#
# Usage: _gh_issue_chat <NUMBER> [-d <DESCRIPTION>] [-n] [-- AGENT_OPTIONS]
_gh_issue_chat() {
	case "${1:-}" in
	--help | -h | help)
		_show_issue_chat_help
		return 0
		;;
	esac

	local args=()
	local passthrough=()
	_split_on_separator args passthrough "$@"
	_validate_chat_passthrough passthrough || return 1

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_ai_source_dir/templates/gh_issue_chat.tmpl"

	local gh_issue_number="" gh_issue_description="" gh_issue_new_session=""
	_parse_issue_chat_args gh_issue_number gh_issue_description gh_issue_new_session "${args[@]}"

	if [[ -z "$gh_issue_number" ]]; then
		gum log --level error "No issue number provided"
		gum log --level info "Usage: gh ai issue chat <ISSUE_NUMBER> [-d <DESCRIPTION>] [-n]"
		return 1
	fi

	local gh_issue_dir="" gh_issue_title="" gh_issue_labels=""
	_prepare_issue_chat_context "$gh_issue_number" gh_issue_dir gh_issue_title gh_issue_labels || return 1

	local gh_issue_focus=""
	if [[ -n "$gh_issue_description" ]]; then
		gh_issue_focus="<focus>${gh_issue_description}</focus>"
	fi

	local gh_issue_worktree
	gh_issue_worktree="issue-$gh_issue_number"
	_save_worktree_state "$gh_issue_dir" "$gh_issue_worktree" "" ""

	local gh_issue_is_new_chat="" gh_issue_session_args=()
	_resolve_chat_session "$gh_issue_dir" "$gh_issue_new_session" gh_issue_is_new_chat gh_issue_session_args || return 1

	local gh_issue_preamble=""
	if [[ -n "$gh_issue_is_new_chat" ]]; then
		gh_issue_preamble=$(
			GH_ISSUE_NUMBER="$gh_issue_number" \
				GH_ISSUE_TITLE="$gh_issue_title" \
				GH_ISSUE_LABELS="$gh_issue_labels" \
				GH_ISSUE_FOCUS="$gh_issue_focus" \
				GH_SESSION_DIR="$gh_issue_dir" \
				"$_gh_ai_source_dir/scripts/gh_cmd.sh" render "$template_file"
		)
	fi

	_cmd_chat "$gh_issue_preamble" --worktree "$gh_issue_worktree" "${gh_issue_session_args[@]}" "${passthrough[@]}"
}

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
    gh ai issue comment <ISSUE_NUMBER> -d <DESCRIPTION> [-- GH_ISSUE_COMMENT_OPTIONS]
    gh ai issue plan <ISSUE_NUMBER> [-d <DESCRIPTION>]
    gh ai issue chat <ISSUE_NUMBER> [-d <DESCRIPTION>] [-n] [-- AGENT_OPTIONS]

DESCRIPTION:
    Creates and edits GitHub issues with AI-generated titles and structured
    bodies. Posts AI-generated comments on existing issues. Generates
    implementation plans from issues and prints them to stdout.
    Opens agent sessions with issue context.

COMMANDS:
    create      Create issues with AI-generated content
    edit        Edit an existing issue with AI-generated content
    comment     Post an AI-generated comment on an existing issue
    plan        Generate an AI implementation plan from an issue
    chat        Open an agent session with issue context

SEE ALSO:
    gh ai issue create --help     # Issue create usage
    gh ai issue edit --help       # Issue edit usage
    gh ai issue comment --help    # Issue comment usage
    gh ai issue plan --help       # Issue plan usage
    gh ai issue chat --help       # Issue chat usage
EOF
}

# Issue subcommand handler
#
# Routes issue subcommands to their appropriate handler functions.
# Shows help for unknown commands.
#
# Usage: _gh_issue <subcommand> [OPTIONS]
# Subcommands: create, edit, comment, plan, chat, help
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
	comment)
		_gh_issue_comment "$@"
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
		gum log --level info "Available commands: create, edit, comment, plan, chat"
		gum log --level info "Run 'gh ai issue --help' for usage information"
		return 1
		;;
	esac
}
