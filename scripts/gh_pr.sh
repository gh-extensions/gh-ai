#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# shellcheck source=gh_cmd.sh
source "$(dirname "${BASH_SOURCE[0]}")/gh_cmd.sh"

# PR-related functions for gh-claude

# Detect the PR number for the current branch
#
# Outputs the PR number to stdout, or empty string if detection fails.
# Used by parsers as a fallback when no PR number was given explicitly.
#
# Usage: num=$(_detect_pr_number)
_detect_pr_number() {
	gh pr view --json number -q '.number' 2>/dev/null || true
}

# Extract a PR number from a raw user-supplied argument.
#
# Accepts bare numbers ("42"), hash-prefixed numbers ("#42"), and full
# GitHub PR URLs with optional trailing slash, query string, or fragment:
#   https://github.com/owner/repo/pull/123
#   https://github.com/owner/repo/pull/123/
#   https://github.com/owner/repo/pull/123?tab=files
#   https://github.com/owner/repo/pull/123#issuecomment-456
#
# Outputs the PR number to stdout on success.
# Returns 1 without output if the input is not recognised.
#
# Usage: num=$(_extract_pr_number "$raw_arg") || return 1
_extract_pr_number() {
	local _epn_input="${1#\#}"   # strip leading '#'

	# Fast path: purely numeric
	if [[ "$_epn_input" =~ ^[0-9]+$ ]]; then
		printf '%s\n' "$_epn_input"
		return 0
	fi

	# GitHub PR URL: https://github.com/<owner>/<repo>/pull/<number>[/|?|#|end]
	if [[ "$_epn_input" =~ ^https://github\.com/[^/]+/[^/]+/pull/([0-9]+)(/|\?|#|$) ]]; then
		printf '%s\n' "${BASH_REMATCH[1]}"
		return 0
	fi

	return 1
}

# Shared argument parser for PR commands that accept a PR number and -d/--description.
#
# Extracts the PR number (first numeric arg, with auto-detect fallback)
# and -d/--description value. Unknown flags produce an error that names subcmd.
#
# Usage: _parse_pr_args subcmd num_ref desc_ref [args...]
_parse_pr_args() {
	local _ppa_subcmd="$1"
	local -n _ppa_num="$2"
	local -n _ppa_desc="$3"
	shift 3

	local _ppa_raw=("$@")
	local _ppa_skip=false
	local _ppa_i=0

	while [[ $_ppa_i -lt ${#_ppa_raw[@]} ]]; do
		if [[ "$_ppa_skip" = true ]]; then
			_ppa_skip=false
			((++_ppa_i))
			continue
		fi

		case "${_ppa_raw[$_ppa_i]}" in
		--description | -d)
			if ((_ppa_i + 1 >= ${#_ppa_raw[@]})); then
				gum log --level error -- "${_ppa_raw[$_ppa_i]} requires a value"
				return 1
			fi
			# shellcheck disable=SC2034 # nameref: set by caller
			_ppa_desc="${_ppa_raw[$((_ppa_i + 1))]}"
			_ppa_skip=true
			;;
		--description=*)
			# shellcheck disable=SC2034 # nameref: set by caller
			_ppa_desc="${_ppa_raw[$_ppa_i]#--description=}"
			;;
		-*)
			gum log --level error "unknown flag '${_ppa_raw[$_ppa_i]}' (use -- to pass flags to gh pr $_ppa_subcmd)"
			return 1
			;;
		*)
			if [[ -z "$_ppa_num" ]]; then
				local _ppa_extracted
				if _ppa_extracted=$(_extract_pr_number "${_ppa_raw[$_ppa_i]}"); then
					_ppa_num="$_ppa_extracted"
				else
					gum log --level error "unexpected argument '${_ppa_raw[$_ppa_i]}'"
					return 1
				fi
			else
				gum log --level error "unexpected argument '${_ppa_raw[$_ppa_i]}'"
				return 1
			fi
			;;
		esac
		((++_ppa_i))
	done

	# Auto-detect PR number from current branch if not found in args
	if [[ -z "$_ppa_num" ]]; then
		_ppa_num=$(_detect_pr_number)
	fi
}

# Shared context helper for existing-PR commands.
#
# Fetches PR metadata and diff, saves context files to the context directory,
# and populates the output variables via namerefs.
#
# When type is "chat" the context is written to the pre-resolved session
# directory (set by _resolve_chat_session before this is called).
# For all other types a temporary directory is created.
#
# Usage: _prepare_pr_diff_context type pr_number dir_ref title_ref head_ref url_ref
_prepare_pr_diff_context() {
	local _ctx_type="$1"
	local _ctx_num="$2"
	local -n _ctx_dir="$3"
	local -n _ctx_title="$4"
	local -n _ctx_head="$5"
	local -n _ctx_url="$6"

	local _ctx_meta
	_ctx_meta=$(gum spin --title "Fetching GitHub pull request #$_ctx_num metadata..." -- \
		gh pr view "$_ctx_num" --json title,body,headRefName,commits,url || true)
	if [[ -z "$_ctx_meta" ]]; then
		gum log --level error "Failed to fetch pull request #$_ctx_num metadata"
		return 1
	fi

	# Single jq pass: extract all fields via eval
	local _ctx_body="" _ctx_commits=""
	# shellcheck disable=SC2154
	eval "$(printf '%s' "$_ctx_meta" | jq -rf "$_gh_claude_source_dir/queries/gh_pr_meta.jq")"

	local _ctx_diff
	_ctx_diff=$(gum spin --title "Fetching GitHub pull request #$_ctx_num diff..." -- \
		gh pr diff "$_ctx_num" --patch || true)
	if [[ -z "$_ctx_diff" ]]; then
		gum log --level error "Failed to get diff for pull request #$_ctx_num"
		return 1
	fi

	local _ctx_diff_stat
	_ctx_diff_stat=$(printf '%s' "$_ctx_diff" | git apply --stat 2>/dev/null || true)

	_resolve_context_dir "$_ctx_type" "pull-$_ctx_num" _ctx_dir || return 1

	_save_context_file "$_ctx_dir" "state/pr_body.md" "$_ctx_body"
	_save_context_file "$_ctx_dir" "state/pr_diff.patch" "$_ctx_diff"
	_save_context_file "$_ctx_dir" "state/pr_diff_stat.txt" "$_ctx_diff_stat"
	_save_context_file "$_ctx_dir" "state/pr_commits.txt" "$_ctx_commits"
}

# Parse PR create arguments (before -- separator)
#
# Extracts -d/--description and -B/--base values. Unknown flags produce
# an error with a hint to use --.
#
# Usage: _parse_pr_create_args base_ref desc_ref [args...]
_parse_pr_create_args() {
	local -n _prca_base_ref="$1"
	local -n _prca_desc_ref="$2"
	shift 2

	local _prca_raw=("$@")
	local _prca_skip=false
	local _prca_i=0

	while [[ $_prca_i -lt ${#_prca_raw[@]} ]]; do
		if [[ "$_prca_skip" = true ]]; then
			_prca_skip=false
			((++_prca_i))
			continue
		fi

		case "${_prca_raw[$_prca_i]}" in
		--description | -d)
			if ((_prca_i + 1 >= ${#_prca_raw[@]})); then
				gum log --level error -- "${_prca_raw[$_prca_i]} requires a value"
				return 1
			fi
			# shellcheck disable=SC2034 # nameref: set by caller
			_prca_desc_ref="${_prca_raw[$((_prca_i + 1))]}"
			_prca_skip=true
			;;
		--description=*)
			# shellcheck disable=SC2034 # nameref: set by caller
			_prca_desc_ref="${_prca_raw[$_prca_i]#--description=}"
			;;
		--base | -B)
			if ((_prca_i + 1 >= ${#_prca_raw[@]})); then
				gum log --level error -- "${_prca_raw[$_prca_i]} requires a value"
				return 1
			fi
			# shellcheck disable=SC2034 # nameref: set by caller
			_prca_base_ref="${_prca_raw[$((_prca_i + 1))]}"
			_prca_skip=true
			;;
		--base=*)
			# shellcheck disable=SC2034 # nameref: set by caller
			_prca_base_ref="${_prca_raw[$_prca_i]#--base=}"
			;;
		-*)
			gum log --level error "unknown flag '${_prca_raw[$_prca_i]}' (use -- to pass flags to gh pr create)"
			return 1
			;;
		*)
			gum log --level error "unexpected argument '${_prca_raw[$_prca_i]}'"
			return 1
			;;
		esac
		((++_prca_i))
	done
}

# Context for _gh_pr_create: builds pre-PR diff context from local git history.
#
# Usage: _prepare_pr_create_context gh_pr_dir_ref [base_branch]
_prepare_pr_create_context() {
	local -n _ctx_dir="$1"
	local _ctx_base="${2:-}"

	local _ctx_head
	_ctx_head=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)

	if [[ -z "$_ctx_base" ]]; then
		_ctx_base=$(_git_default_branch)
	fi

	local _ctx_diff="" _ctx_diff_stat="" _ctx_log="" _ctx_commits=""
	_git_branch_diff "$_ctx_base" "$_ctx_head" _ctx_diff _ctx_diff_stat _ctx_log _ctx_commits || return 1

	local _ctx_dir_path
	_create_context_dir _ctx_dir_path
	_ctx_dir="$_ctx_dir_path"

	_save_context_file "$_ctx_dir" "state/pr_diff.patch" "$_ctx_diff"
	_save_context_file "$_ctx_dir" "state/pr_diff_stat.txt" "$_ctx_diff_stat"
	_save_context_file "$_ctx_dir" "state/pr_commits.txt" "$_ctx_commits"
}

# PR create help function
#
# Displays help information for the PR create command
# including usage examples and available options.
_show_pr_create_help() {
	cat <<'EOF'
gh claude pr create - Create PRs with AI-generated titles and descriptions

USAGE:
    gh claude pr create [-d <DESCRIPTION>] [-B <BASE>] [-- GH_PR_CREATE_OPTIONS]

DESCRIPTION:
    Creates a GitHub pull request with an AI-generated title and description
    based on the diff and commit history between the current and base branch.
    Options after -- are passed directly to gh pr create.

FLAGS:
    -d, --description string   Optional guidance for the AI (e.g. focus area)
    -B, --base string          Base branch for the pull request

EXAMPLES:
    gh claude pr create
    gh claude pr create -- --draft
    gh claude pr create -B develop -- --draft
    gh claude pr create -d "focus on the security changes"
EOF
}

# PR Create implementation
#
# Creates a GitHub PR with an AI-generated title and description.
# Renders a prompt template with git diff and commit context,
# sends it to the AI provider, and parses the response.
#
# Usage: _gh_pr_create [-d <DESCRIPTION>] [-B <BASE>] [-- OPTIONS]
_gh_pr_create() {
	case "${1:-}" in
	--help | -h | help)
		_show_pr_create_help
		return 0
		;;
	esac

	local args=()
	local passthrough=()
	_split_on_separator args passthrough "$@"

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_claude_source_dir/templates/gh_pr_create.tmpl"

	local git_base_branch="" gh_pr_description=""
	_parse_pr_create_args git_base_branch gh_pr_description "${args[@]}"

	# Remember whether the user explicitly specified --base so we only
	# forward it to gh pr create when intended (not from fallback defaults).
	if [[ -n "$git_base_branch" ]]; then
		# Inject --base into passthrough only if the user explicitly specified it
		passthrough=("--base" "$git_base_branch" "${passthrough[@]}")
	fi

	local gh_pr_dir=""
	_prepare_pr_create_context gh_pr_dir "$git_base_branch" || return 1

	local gh_pr_agent_model
	gh_pr_agent_model=$(_gh_config_claude_model "pr")

	local gh_pr_content
	# Generate PR content using assistant run
	# *_FILE vars are read by 'gh_cmd.sh render' and inlined as their non-FILE counterparts.
	gh_pr_content=$(
		gum spin --title "Generating GitHub pull request..." -- \
			"$_gh_claude_source_dir/scripts/gh_cmd.sh" ask "$gh_pr_agent_model" < <(
				GH_PR_DIFF_FILE="$gh_pr_dir/state/pr_diff.patch" \
					GH_PR_DIFF_STAT_FILE="$gh_pr_dir/state/pr_diff_stat.txt" \
					GH_PR_COMMITS_FILE="$gh_pr_dir/state/pr_commits.txt" \
					GH_PR_DESCRIPTION="$gh_pr_description" \
					"$_gh_claude_source_dir/scripts/gh_cmd.sh" render "$template_file"
			)
	)

	# Clean up the temp context directory now that the AI call is done.
	rm -rf "$gh_pr_dir"

	# Validate we got PR content
	if [[ -z "$gh_pr_content" ]]; then
		gum log --level error "Failed to generate pull request content"
		gum log --level info "Run with DEBUG=1 for detailed diagnostics"
		return 1
	fi

	local gh_pr_title
	# Parse title from output
	if ! gh_pr_title=$(_parse_title "$gh_pr_content"); then
		gum log --level error "Failed to extract title from AI content"
		return 1
	fi

	local gh_pr_body
	# Parse body from output
	gh_pr_body=$(_parse_body "$gh_pr_content")

	# Create PR with AI-generated content
	gh pr create --title "$gh_pr_title" --body "$gh_pr_body" "${passthrough[@]}"
}

# Parse PR edit arguments (before -- separator).
#
# Extracts PR number and -d/--description from args. Unknown flags hint to use --.
_parse_pr_edit_args() { _parse_pr_args "edit" "$@"; }

# Fetches PR metadata and diff into a temp directory for use by _gh_pr_edit.
_prepare_pr_edit_context() { _prepare_pr_diff_context "edit" "$@"; }

# PR edit help function
#
# Displays help information for the PR edit command
# including usage examples and available options.
_show_pr_edit_help() {
	cat <<'EOF'
gh claude pr edit - Edit an existing PR with AI-generated content

USAGE:
    gh claude pr edit [PR_NUMBER] -d <DESCRIPTION> [-- GH_PR_EDIT_OPTIONS]

DESCRIPTION:
    Edits an existing GitHub pull request using AI. Fetches the current PR
    content and diff, applies the requested changes via AI, and updates the
    PR title and body. Auto-detects PR from the current branch if no number
    is provided. Options after -- are passed directly to gh pr edit.

FLAGS:
    -d, --description string   Description of the changes to make (required)

EXAMPLES:
    gh claude pr edit 42 -d "add testing section"
    gh claude pr edit 42 -d "fix summary" -- --add-label bug
    gh claude pr edit -d "improve description"   # auto-detect PR from current branch
EOF
}

# PR Edit implementation
#
# Edits an existing GitHub PR with AI-generated content.
# Fetches the current PR content and diff, renders a prompt template
# with the description and PR context, sends it to the AI provider,
# and updates the PR with the parsed response.
#
# Usage: _gh_pr_edit [NUMBER] -d <DESCRIPTION> [-- OPTIONS]
_gh_pr_edit() {
	case "${1:-}" in
	--help | -h | help)
		_show_pr_edit_help
		return 0
		;;
	esac

	local args=()
	local passthrough=()
	_split_on_separator args passthrough "$@"

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_claude_source_dir/templates/gh_pr_edit.tmpl"

	local gh_pr_number="" gh_pr_description=""
	_parse_pr_edit_args gh_pr_number gh_pr_description "${args[@]}"

	if [[ -z "$gh_pr_number" ]]; then
		gum log --level error "No pull request number provided and could not detect pull request for current branch"
		gum log --level info "Usage: gh claude pr edit [PR_NUMBER] -d <DESCRIPTION> [-- OPTIONS]"
		return 1
	fi

	if [[ -z "$gh_pr_description" ]]; then
		gum log --level error "No description provided"
		gum log --level info "Usage: gh claude pr edit [PR_NUMBER] -d <DESCRIPTION> [-- OPTIONS]"
		return 1
	fi

	local gh_pr_dir="" gh_pr_title="" gh_pr_head="" gh_pr_url=""
	_prepare_pr_edit_context "$gh_pr_number" gh_pr_dir gh_pr_title gh_pr_head gh_pr_url || return 1

	local gh_pr_agent_model
	gh_pr_agent_model=$(_gh_config_claude_model "pr")

	local gh_pr_content
	# Generate updated PR content using assistant
	# *_FILE vars are read by 'gh_cmd.sh render' and inlined as their non-FILE counterparts.
	gh_pr_content=$(
		gum spin --title "Generating updated GitHub pull request #$gh_pr_number..." -- \
			"$_gh_claude_source_dir/scripts/gh_cmd.sh" ask "$gh_pr_agent_model" < <(
				GH_PR_NUMBER="$gh_pr_number" \
					GH_PR_TITLE="$gh_pr_title" \
					GH_PR_URL="$gh_pr_url" \
					GH_PR_DIFF_FILE="$gh_pr_dir/state/pr_diff.patch" \
					GH_PR_DIFF_STAT_FILE="$gh_pr_dir/state/pr_diff_stat.txt" \
					GH_PR_COMMITS_FILE="$gh_pr_dir/state/pr_commits.txt" \
					GH_PR_BODY_FILE="$gh_pr_dir/state/pr_body.md" \
					GH_PR_DESCRIPTION="$gh_pr_description" \
					"$_gh_claude_source_dir/scripts/gh_cmd.sh" render "$template_file"
			)
	)

	# Clean up the temp context directory now that the AI call is done.
	rm -rf "$gh_pr_dir"

	# Validate we got PR content
	if [[ -z "$gh_pr_content" ]]; then
		gum log --level error "Failed to generate updated pull request content"
		gum log --level info "Run with DEBUG=1 for detailed diagnostics"
		return 1
	fi

	# Parse title from output
	if ! gh_pr_title=$(_parse_title "$gh_pr_content"); then
		gum log --level error "Failed to extract title from AI content"
		return 1
	fi

	local gh_pr_body
	# Parse body from output
	gh_pr_body=$(_parse_body "$gh_pr_content")

	# Edit PR with AI-generated content
	gh pr edit "$gh_pr_number" --title "$gh_pr_title" --body "$gh_pr_body" "${passthrough[@]}"
}

# Parse PR review arguments (before -- separator).
#
# Extracts PR number and -d/--description from args. Unknown flags hint to use --.
_parse_pr_review_args() { _parse_pr_args "review" "$@"; }

# Fetches PR metadata and diff into a temp directory for use by _gh_pr_review.
_prepare_pr_review_context() { _prepare_pr_diff_context "review" "$@"; }

# PR review help function
#
# Displays help information for the PR review command
# including usage examples and available options.
_show_pr_review_help() {
	cat <<'EOF'
gh claude pr review - Review PRs with AI-generated feedback

USAGE:
    gh claude pr review [PR_NUMBER] [-d <DESCRIPTION>] [-- GH_PR_REVIEW_OPTIONS]

DESCRIPTION:
    Submits a GitHub PR review with AI-generated feedback based on the
    diff and commit history. Auto-detects PR from the current branch
    if no number is provided. Options after -- are passed directly to
    gh pr review.

FLAGS:
    -d, --description string   Additional context for AI review generation

EXAMPLES:
    gh claude pr review 42
    gh claude pr review 42 -- --approve
    gh claude pr review -d "focus on security"
    gh claude pr review              # auto-detect PR from current branch
EOF
}

# PR Review implementation
#
# Submits a GitHub PR review with AI-generated feedback.
# Renders a prompt template with the PR diff and commit context,
# sends it to the AI provider, and submits the response as a review.
# Auto-detects PR number from current branch if not provided.
#
# Usage: _gh_pr_review [NUMBER] [-d <DESCRIPTION>] [-- OPTIONS]
_gh_pr_review() {
	case "${1:-}" in
	--help | -h | help)
		_show_pr_review_help
		return 0
		;;
	esac

	local args=()
	local passthrough=()
	_split_on_separator args passthrough "$@"

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_claude_source_dir/templates/gh_pr_review.tmpl"

	local gh_pr_number="" gh_pr_description=""
	_parse_pr_review_args gh_pr_number gh_pr_description "${args[@]}"

	if [[ -z "$gh_pr_number" ]]; then
		gum log --level error "No pull request number provided and could not detect pull request for current branch"
		gum log --level info "Usage: gh claude pr review [PR_NUMBER] [-d <DESCRIPTION>] [-- OPTIONS]"
		return 1
	fi

	local gh_pr_dir="" gh_pr_title="" gh_pr_head="" gh_pr_url=""
	_prepare_pr_review_context "$gh_pr_number" gh_pr_dir gh_pr_title gh_pr_head gh_pr_url || return 1

	local gh_pr_agent_model
	gh_pr_agent_model=$(_gh_config_claude_model "pr")

	local gh_pr_review
	# Generate review content using assistant run
	# *_FILE vars are read by 'gh_cmd.sh render' and inlined as their non-FILE counterparts.
	gh_pr_review=$(
		gum spin --title "Generating GitHub pull request #$gh_pr_number review..." -- \
			"$_gh_claude_source_dir/scripts/gh_cmd.sh" ask "$gh_pr_agent_model" < <(
				GH_PR_NUMBER="$gh_pr_number" \
					GH_PR_TITLE="$gh_pr_title" \
					GH_PR_URL="$gh_pr_url" \
					GH_PR_BODY_FILE="$gh_pr_dir/state/pr_body.md" \
					GH_PR_DIFF_FILE="$gh_pr_dir/state/pr_diff.patch" \
					GH_PR_DIFF_STAT_FILE="$gh_pr_dir/state/pr_diff_stat.txt" \
					GH_PR_COMMITS_FILE="$gh_pr_dir/state/pr_commits.txt" \
					GH_PR_HEAD="$gh_pr_head" \
					GH_PR_DESCRIPTION="$gh_pr_description" \
					"$_gh_claude_source_dir/scripts/gh_cmd.sh" render "$template_file"
			)
	)

	# Clean up the temp context directory now that the AI call is done.
	rm -rf "$gh_pr_dir"

	# Validate we got review content
	if [[ -z "$gh_pr_review" ]]; then
		gum log --level error "Failed to generate review content"
		gum log --level info "Run with DEBUG=1 for detailed diagnostics"
		return 1
	fi

	# Submit review with AI-generated content
	gh pr review "$gh_pr_number" --body "$gh_pr_review" "${passthrough[@]}"
}

# Parse PR explain arguments
#
# Extracts the PR number (first numeric arg, with auto-detect fallback)
# via nameref.
#
# Usage: _parse_pr_explain_args num_ref [args...]
_parse_pr_explain_args() {
	local -n _ppea_num_ref="$1"
	shift

	local _ppea_raw=("$@")
	local _ppea_i=0

	while [[ $_ppea_i -lt ${#_ppea_raw[@]} ]]; do
		case "${_ppea_raw[$_ppea_i]}" in
		-*)
			gum log --level error "unknown flag '${_ppea_raw[$_ppea_i]}'"
			return 1
			;;
		*)
			if [[ -z "$_ppea_num_ref" ]]; then
				local _ppea_extracted
				if _ppea_extracted=$(_extract_pr_number "${_ppea_raw[$_ppea_i]}"); then
					_ppea_num_ref="$_ppea_extracted"
				else
					gum log --level error "unexpected argument '${_ppea_raw[$_ppea_i]}'"
					return 1
				fi
			else
				gum log --level error "unexpected argument '${_ppea_raw[$_ppea_i]}'"
				return 1
			fi
			;;
		esac
		((++_ppea_i))
	done

	# Auto-detect PR number from current branch if not found in args
	if [[ -z "$_ppea_num_ref" ]]; then
		_ppea_num_ref=$(_detect_pr_number)
	fi
}

# Fetches PR metadata and diff into a temp directory for use by _gh_pr_explain.
_prepare_pr_explain_context() { _prepare_pr_diff_context "explain" "$@"; }

# PR explain help function
#
# Displays help information for the PR explain command
# including usage examples and available options.
_show_pr_explain_help() {
	cat <<'EOF'
gh claude pr explain - Generate a plain-language explanation of a PR

USAGE:
    gh claude pr explain [PR_NUMBER]

DESCRIPTION:
    Generates a plain-language explanation of what a pull request does
    and prints it to stdout. Auto-detects PR from the current branch
    if no number is provided.

EXAMPLES:
    gh claude pr explain 42
    gh claude pr explain                              # auto-detect PR
    gh claude pr explain 42 | gh pr comment 42 --body -   # post as comment
    gh claude pr explain 42 | gh pr edit 42 --body -      # replace PR body
EOF
}

# PR Explain implementation
#
# Generates a plain-language explanation of what a PR does
# and prints it to stdout.
#
# Usage: _gh_pr_explain [NUMBER]
_gh_pr_explain() {
	case "${1:-}" in
	--help | -h | help)
		_show_pr_explain_help
		return 0
		;;
	esac

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_claude_source_dir/templates/gh_pr_explain.tmpl"

	local gh_pr_number=""
	_parse_pr_explain_args gh_pr_number "$@"

	if [[ -z "$gh_pr_number" ]]; then
		gum log --level error "No pull request number provided and could not detect pull request for current branch"
		gum log --level info "Usage: gh claude pr explain [PR_NUMBER]"
		return 1
	fi

	local gh_pr_dir="" gh_pr_title="" gh_pr_head="" gh_pr_url=""
	_prepare_pr_explain_context "$gh_pr_number" gh_pr_dir gh_pr_title gh_pr_head gh_pr_url || return 1

	local gh_pr_agent_model
	gh_pr_agent_model=$(_gh_config_claude_model "pr")

	local gh_pr_explain
	# Generate explanation using assistant run
	# *_FILE vars are read by 'gh_cmd.sh render' and inlined as their non-FILE counterparts.
	gh_pr_explain=$(
		gum spin --title "Generating GitHub pull request #$gh_pr_number explanation..." -- \
			"$_gh_claude_source_dir/scripts/gh_cmd.sh" ask "$gh_pr_agent_model" < <(
				GH_PR_NUMBER="$gh_pr_number" \
					GH_PR_TITLE="$gh_pr_title" \
					GH_PR_URL="$gh_pr_url" \
					GH_PR_BODY_FILE="$gh_pr_dir/state/pr_body.md" \
					GH_PR_DIFF_FILE="$gh_pr_dir/state/pr_diff.patch" \
					GH_PR_DIFF_STAT_FILE="$gh_pr_dir/state/pr_diff_stat.txt" \
					GH_PR_COMMITS_FILE="$gh_pr_dir/state/pr_commits.txt" \
					GH_PR_HEAD="$gh_pr_head" \
					"$_gh_claude_source_dir/scripts/gh_cmd.sh" render "$template_file"
			)
	)

	# Clean up the temp context directory now that the AI call is done.
	rm -rf "$gh_pr_dir"

	# Validate we got explanation content
	if [[ -z "$gh_pr_explain" ]]; then
		gum log --level error "Failed to generate explanation"
		gum log --level info "Run with DEBUG=1 for detailed diagnostics"
		return 1
	fi

	printf '%s\n' "$gh_pr_explain"
}

# Argument parser for the pr chat subcommand.
#
# Pre-processes the argument list to convert any GitHub PR URL to a bare
# numeric PR number before delegating to the shared _parse_chat_args.
#
# Usage: _parse_pr_chat_args num_ref desc_ref [args...]
_parse_pr_chat_args() {
	local _ppca_num_ref="$1"
	local _ppca_desc_ref="$2"
	shift 2

	local _ppca_processed=()
	local _ppca_arg
	for _ppca_arg in "$@"; do
		local _ppca_extracted
		if _ppca_extracted=$(_extract_pr_number "$_ppca_arg") 2>/dev/null; then
			_ppca_processed+=("$_ppca_extracted")
		else
			_ppca_processed+=("$_ppca_arg")
		fi
	done

	_parse_chat_args "$_ppca_num_ref" "$_ppca_desc_ref" "${_ppca_processed[@]}"
}

# Fetches PR metadata and diff into the pre-resolved session directory for _gh_pr_chat.
_prepare_pr_chat_context() { _prepare_pr_diff_context "chat" "$@"; }

# PR chat help function
#
# Displays help information for the PR chat command
# including usage examples and available options.
_show_pr_chat_help() {
	cat <<'EOF'
gh claude pr chat - Open an agent session with PR context

USAGE:
    gh claude pr chat [PR_NUMBER] [-d <DESCRIPTION>] [-- AGENT_OPTIONS]

DESCRIPTION:
    Fetches the GitHub PR metadata and diff, renders it as context, and
    pipes it into the configured agent binary (default: claude).
    Auto-detects PR from the current branch if no number is provided.
    Options after -- are passed directly to the agent binary.

    Configure the model: gh config set claude.pr.model <model>

FLAGS:
    -d, --description string   Extra context or focus for the agent (optional)

EXAMPLES:
    gh claude pr chat 42
    gh claude pr chat -d "focus on the security changes"
    gh claude pr chat                          # auto-detect PR from current branch
    gh claude pr chat 42 -- --model sonnet
    gh claude pr chat 42 -- --session-id <UUID>       # named session (reuses on next call)
    gh claude pr chat 42 -- --resume <UUID>           # resume a specific session
EOF
}

# PR Chat implementation
#
# Fetches a GitHub PR's metadata and diff, renders the context template,
# and pipes it into the configured agent binary. Pass --session-id or
# --resume after -- to manage sessions explicitly.
#
# Usage: _gh_pr_chat [NUMBER] [-d <DESCRIPTION>] [-- AGENT_OPTIONS]
_gh_pr_chat() {
	case "${1:-}" in
	--help | -h | help)
		_show_pr_chat_help
		return 0
		;;
	esac

	local args=()
	local passthrough=()
	_split_on_separator args passthrough "$@"

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_claude_source_dir/templates/gh_pr_chat.tmpl"

	local gh_pr_number="" gh_pr_description=""
	_parse_pr_chat_args gh_pr_number gh_pr_description "${args[@]}"

	if [[ -z "$gh_pr_number" ]]; then
		gh_pr_number=$(_detect_pr_number)
	fi

	if [[ -z "$gh_pr_number" ]]; then
		gum log --level error "No pull request number provided and could not detect pull request for current branch"
		gum log --level info "Usage: gh claude pr chat [PR_NUMBER] [-d <DESCRIPTION>]"
		return 1
	fi

	local gh_pr_user_session_id="" gh_pr_user_resume=""
	_extract_chat_passthrough passthrough gh_pr_user_session_id gh_pr_user_resume

	local gh_pr_dir="" gh_pr_is_new_chat="" gh_pr_session_args=()
	_resolve_chat_session "pull-$gh_pr_number" "$gh_pr_user_session_id" "$gh_pr_user_resume" gh_pr_dir gh_pr_is_new_chat gh_pr_session_args || return 1


	local gh_pr_title="" gh_pr_head="" gh_pr_url="" gh_pr_prompt=""
	if [[ -n "$gh_pr_is_new_chat" ]]; then
		_prepare_pr_chat_context "$gh_pr_number" gh_pr_dir gh_pr_title gh_pr_head gh_pr_url || return 1

		if [[ -z "$gh_pr_head" ]]; then
			gum log --level error "Could not determine head branch for pull request #$gh_pr_number"
			return 1
		fi

		local gh_pr_focus=""
		if [[ -n "$gh_pr_description" ]]; then
			gh_pr_focus="<focus>${gh_pr_description}</focus>"
		fi

		# *_FILE vars are read by 'gh_cmd.sh render' and inlined as their non-FILE counterparts.
		gh_pr_prompt=$(
			GH_PR_NUMBER="$gh_pr_number" \
				GH_PR_TITLE="$gh_pr_title" \
				GH_PR_URL="$gh_pr_url" \
				GH_PR_FOCUS="$gh_pr_focus" \
				GH_CLAUDE_SESSION_DIR="$gh_pr_dir" \
				GH_PR_HEAD="$gh_pr_head" \
				"$_gh_claude_source_dir/scripts/gh_cmd.sh" render "$template_file"
		)
	fi

	export GH_PR_NUMBER="$gh_pr_number"
	export GH_CLAUDE_SESSION_DIR="$gh_pr_dir"
	_cmd_chat "$gh_pr_url" "$gh_pr_prompt" "${gh_pr_session_args[@]}" "${passthrough[@]}"
}

# Parse PR comment arguments (before -- separator).
#
# Extracts PR number and -d/--description from args. Unknown flags hint to use --.
_parse_pr_comment_args() { _parse_pr_args "comment" "$@"; }

# Context for _gh_pr_comment: fetches PR body and comments, and reads optional
# stdin into pr_context.md. Uses a temporary directory.
#
# Usage: _prepare_pr_comment_context pr_number gh_pr_dir_ref title_ref url_ref
_prepare_pr_comment_context() {
	local _ctx_num="$1"
	local -n _ctx_dir="$2"
	local -n _ctx_title="$3"
	local -n _ctx_url="$4"

	local _ctx_meta
	_ctx_meta=$(gum spin --title "Fetching GitHub pull request #$_ctx_num metadata..." -- \
		gh pr view "$_ctx_num" --json title,body,comments,url || true)
	if [[ -z "$_ctx_meta" ]]; then
		gum log --level error "Failed to fetch pull request #$_ctx_num"
		return 1
	fi

	# Single jq pass: extract all fields via eval
	local _ctx_body="" _ctx_comments="" _ctx_head="" _ctx_commits=""
	# shellcheck disable=SC2154
	eval "$(printf '%s' "$_ctx_meta" | jq -rf "$_gh_claude_source_dir/queries/gh_pr_meta.jq")"

	local _ctx_dir_path
	_create_context_dir _ctx_dir_path
	_ctx_dir="$_ctx_dir_path"

	local _ctx_context=""
	if [[ ! -t 0 ]]; then
		_ctx_context=$(cat)
	fi

	_save_context_file "$_ctx_dir" "state/pr_body.md" "$_ctx_body"
	_save_context_file "$_ctx_dir" "state/pr_comments.md" "$_ctx_comments"
	_save_context_file "$_ctx_dir" "state/pr_context.md" "$_ctx_context"
}

# PR comment help function
#
# Displays help information for the PR comment command
# including usage examples and available options.
_show_pr_comment_help() {
	cat <<'EOF'
gh claude pr comment - Post an AI-generated comment on a pull request

USAGE:
    gh claude pr comment [PR_NUMBER] -d <DESCRIPTION> [-- GH_PR_COMMENT_OPTIONS]

DESCRIPTION:
    Posts a GitHub PR comment with AI-generated content based on the PR body,
    existing comments, and the description you provide. Auto-detects PR from
    the current branch if no number is provided. Options after -- are passed
    directly to gh pr comment.

FLAGS:
    -d, --description string   Context or instructions for the AI comment (required)

EXAMPLES:
    gh claude pr comment 42 -d "summarise the open review threads"
    gh claude pr comment -d "ask about the migration strategy"
    echo "some notes" | gh claude pr comment 42 -d "incorporate this context"
    gh claude pr comment 42 -d "request changes" -- --edit-last
EOF
}

# PR Comment implementation
#
# Posts a GitHub PR comment with AI-generated content.
# Renders a prompt template with the PR body, existing comments, and
# description context, sends it to the AI provider, and posts the response
# as a comment. Auto-detects PR number from current branch if not provided.
#
# Usage: _gh_pr_comment [NUMBER] -d <DESCRIPTION> [-- OPTIONS]
_gh_pr_comment() {
	case "${1:-}" in
	--help | -h | help)
		_show_pr_comment_help
		return 0
		;;
	esac

	local args=()
	local passthrough=()
	_split_on_separator args passthrough "$@"

	local template_file
	# shellcheck disable=SC2154
	template_file="$_gh_claude_source_dir/templates/gh_pr_comment.tmpl"

	local gh_pr_number="" gh_pr_description=""
	_parse_pr_comment_args gh_pr_number gh_pr_description "${args[@]}"

	if [[ -z "$gh_pr_number" ]]; then
		gum log --level error "No pull request number provided and could not detect pull request for current branch"
		gum log --level info "Usage: gh claude pr comment [PR_NUMBER] -d <DESCRIPTION> [-- OPTIONS]"
		return 1
	fi

	if [[ -z "$gh_pr_description" ]]; then
		gum log --level error "No description provided"
		gum log --level info "Usage: gh claude pr comment [PR_NUMBER] -d <DESCRIPTION> [-- OPTIONS]"
		return 1
	fi

	local gh_pr_dir="" gh_pr_title="" gh_pr_url=""
	_prepare_pr_comment_context "$gh_pr_number" gh_pr_dir gh_pr_title gh_pr_url || return 1

	local gh_pr_agent_model
	gh_pr_agent_model=$(_gh_config_claude_model "pr")

	local gh_pr_comment
	# Generate comment content using assistant
	# *_FILE vars are read by 'gh_cmd.sh render' and inlined as their non-FILE counterparts.
	gh_pr_comment=$(
		gum spin --title "Generating GitHub pull request #$gh_pr_number comment..." -- \
			"$_gh_claude_source_dir/scripts/gh_cmd.sh" ask "$gh_pr_agent_model" < <(
				GH_PR_NUMBER="$gh_pr_number" \
					GH_PR_TITLE="$gh_pr_title" \
					GH_PR_URL="$gh_pr_url" \
					GH_PR_BODY_FILE="$gh_pr_dir/state/pr_body.md" \
					GH_PR_COMMENTS_FILE="$gh_pr_dir/state/pr_comments.md" \
					GH_PR_DESCRIPTION="$gh_pr_description" \
					GH_PR_CONTEXT_FILE="$gh_pr_dir/state/pr_context.md" \
					"$_gh_claude_source_dir/scripts/gh_cmd.sh" render "$template_file"
			)
	)

	# Clean up the temp context directory now that the AI call is done.
	rm -rf "$gh_pr_dir"

	# Validate we got comment content
	if [[ -z "$gh_pr_comment" ]]; then
		gum log --level error "Failed to generate comment content"
		gum log --level info "Run with DEBUG=1 for detailed diagnostics"
		return 1
	fi

	# Post comment with AI-generated content
	gh pr comment "$gh_pr_number" --body "$gh_pr_comment" "${passthrough[@]}"
}

# PR help function
#
# Displays comprehensive help information for all PR subcommands
# including usage examples and available options.
_show_pr_help() {
	cat <<'EOF'
gh claude pr - Pull request commands with AI assistance

USAGE:
    gh claude pr create [-d <DESCRIPTION>] [-B <BASE>] [-- GH_PR_CREATE_OPTIONS]
    gh claude pr edit [PR_NUMBER] -d <DESCRIPTION> [-- GH_PR_EDIT_OPTIONS]
    gh claude pr review [PR_NUMBER] [-d <DESCRIPTION>] [-- GH_PR_REVIEW_OPTIONS]
    gh claude pr explain [PR_NUMBER]
    gh claude pr chat [PR_NUMBER] [-d <DESCRIPTION>] [-- AGENT_OPTIONS]
    gh claude pr comment [PR_NUMBER] -d <DESCRIPTION> [-- GH_PR_COMMENT_OPTIONS]

DESCRIPTION:
    Creates, edits, reviews, explains, and comments on GitHub pull requests
    with AI-generated content. Opens agent sessions with PR context.

COMMANDS:
    create      Create PRs with AI-generated titles and descriptions
    edit        Edit an existing PR with AI-generated content
    review      Review PRs with AI-generated feedback
    explain     Generate a plain-language explanation of a PR
    chat        Open an agent session with PR context
    comment     Post an AI-generated comment on a pull request

SEE ALSO:
    gh claude pr create --help     # Full list of gh pr create options
    gh claude pr edit --help       # Full list of gh pr edit options
    gh claude pr review --help     # Full list of gh pr review options
    gh claude pr explain --help    # PR explain usage
    gh claude pr chat --help       # PR chat usage
    gh claude pr comment --help    # PR comment usage
EOF
}

# PR subcommand handler
#
# Routes PR subcommands to their appropriate handler functions.
# Shows help for unknown commands.
#
# Usage: _gh_pr <subcommand> [OPTIONS]
# Subcommands: create, edit, review, explain, chat, comment, help
_gh_pr() {
	local subcommand="${1:-}"
	shift || true

	case $subcommand in
	create)
		_gh_pr_create "$@"
		;;
	edit)
		_gh_pr_edit "$@"
		;;
	review)
		_gh_pr_review "$@"
		;;
	explain)
		_gh_pr_explain "$@"
		;;
	chat)
		_gh_pr_chat "$@"
		;;
	comment)
		_gh_pr_comment "$@"
		;;
	--help | -h | help | "")
		_show_pr_help
		;;
	*)
		gum log --level error "unknown pr command '$subcommand'"
		gum log --level info "Available commands: create, edit, review, explain, chat, comment"
		gum log --level info "Run 'gh claude pr --help' for usage information"
		return 1
		;;
	esac
}
