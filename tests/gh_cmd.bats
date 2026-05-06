#!/usr/bin/env bats

# Unit tests for gh_cmd.sh utilities
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_cmd.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _gh_ai_source_dir="$REPO_ROOT"

	# Initialize global AI args array (set per-test when needed)
	_GH_AI_ARGS=()

	gum() { if [[ "$1" == "log" ]]; then shift; shift; shift; echo "$@"; fi; }
	gh() { echo ""; }
	git() { echo ""; }
	export -f gum gh git

	# shellcheck disable=SC2155
	eval "$(
		export _gh_ai_source_dir="$REPO_ROOT"
		# shellcheck source=../scripts/gh_cmd.sh
		source "$REPO_ROOT/scripts/gh_cmd.sh"
		printf '_gh_cmd_dir=%q\n' "$_gh_cmd_dir"
		declare -f _cmd_render _parse_title _parse_body \
			_gh_repo_name _git_repo_path _git_branch_diff \
			_gh_config_ai_model _extract_ai_arg \
			_get_agent _get_agent_default_model _cmd_ask _cmd_chat \
			_get_claude_default_model _get_codex_default_model _get_gemini_default_model \
			_ask_ai _ask_codex _ask_gemini \
			_chat_ai _chat_codex _chat_gemini
	)"
}

# ---------------------------------------------------------------------------
# Agent resolution
# ---------------------------------------------------------------------------

@test "_get_agent: defaults to ai" {
	gh() { :; }
	export -f gh
	run _get_agent
	[[ "$output" == "ai" ]]
}

@test "_get_agent: respects ai.agent config" {
	gh() { echo "gemini"; }
	export -f gh
	run _get_agent
	[[ "$output" == "gemini" ]]
}

@test "_get_agent_default_model: returns correct defaults" {
	[[ "$(_get_agent_default_model ai)" == "haiku" ]]
	[[ "$(_get_agent_default_model claude)" == "haiku" ]]
	[[ "$(_get_agent_default_model codex)" == "gpt-5.4-mini" ]]
	[[ "$(_get_agent_default_model gemini)" == "gemini-2.0-flash" ]]
}

# ---------------------------------------------------------------------------
# _gh_repo_name
# ---------------------------------------------------------------------------

@test "_gh_repo_name: sets nameref when gh repo view succeeds" {
	gh() { echo "owner/repo"; }
	export -f gh

	local repo=""
	_gh_repo_name repo

	[[ "$repo" == "owner/repo" ]]
}

@test "_gh_repo_name: returns error when gh repo view returns empty" {
	gh() { :; }
	export -f gh

	local repo=""
	run _gh_repo_name repo

	[[ "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# _git_repo_path
# ---------------------------------------------------------------------------

@test "_git_repo_path: sets nameref when git rev-parse succeeds" {
	git() { echo "/home/user/myrepo"; }
	export -f git

	local dir=""
	_git_repo_path dir

	[[ "$dir" == "/home/user/myrepo" ]]
}

@test "_git_repo_path: returns error when git rev-parse returns empty" {
	git() { :; }
	export -f git

	local dir=""
	run _git_repo_path dir

	[[ "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# _git_branch_diff
# ---------------------------------------------------------------------------

@test "_git_branch_diff: populates all four namerefs" {
	git() {
		case "$1 $2" in
		"diff origin/main...feature")
			if [[ "${*}" == *"--stat"* ]]; then
				echo " file.sh | 2 +-"
			else
				echo "diff --git a/file.sh b/file.sh"
			fi
			;;
		"log --oneline") echo "abc1234 first commit" ;;
		esac
	}
	export -f git

	local diff="" stat="" log="" commits=""
	_git_branch_diff main feature diff stat log commits

	[[ "$diff" == "diff --git a/file.sh b/file.sh" ]]
	[[ "$stat" == " file.sh | 2 +-" ]]
	[[ "$log" == "abc1234 first commit" ]]
	[[ "$commits" == "- first commit" ]]
}

@test "_git_branch_diff: falls back to bare branch when origin fails" {
	git() {
		case "$*" in
		*origin/main*)
			return 1
			;;
		"diff main...feature")
			echo "diff --git a/file.sh b/file.sh"
			;;
		"diff main...feature --stat")
			echo " file.sh | 2 +-"
			;;
		"log --oneline main..feature")
			echo "abc1234 first commit"
			;;
		esac
	}
	export -f git

	local diff="" stat="" log="" commits=""
	_git_branch_diff main feature diff stat log commits

	[[ "$diff" == "diff --git a/file.sh b/file.sh" ]]
}

@test "_git_branch_diff: returns error when diff is empty" {
	git() { return 1; }
	export -f git

	local diff="" stat="" log="" commits=""
	run _git_branch_diff main feature diff stat log commits

	[[ "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# _cmd_render
# ---------------------------------------------------------------------------

@test "_cmd_render: substitutes env vars in template" {
	local tmpdir="$BATS_TMPDIR/render-test-$$"
	mkdir -p "$tmpdir"
	printf 'Hello ${MY_NAME}, welcome to ${MY_PLACE}.\n' >"$tmpdir/test.tmpl"

	local output
	output=$(MY_NAME="Alice" MY_PLACE="Wonderland" _cmd_render "$tmpdir/test.tmpl")

	[[ "$output" == *"Hello Alice, welcome to Wonderland."* ]]
}

@test "_cmd_render: leaves unset vars as empty strings" {
	local tmpdir="$BATS_TMPDIR/render-unset-test-$$"
	mkdir -p "$tmpdir"
	printf 'Value: [${UNSET_VAR}]\n' >"$tmpdir/test.tmpl"

	local output
	output=$(_cmd_render "$tmpdir/test.tmpl")

	[[ "$output" == *"Value: []"* ]]
}

@test "_cmd_render: does not re-expand vars inside substituted values" {
	local tmpdir="$BATS_TMPDIR/render-safe-test-$$"
	mkdir -p "$tmpdir"
	printf 'Diff: ${GH_PR_DIFF}\n' >"$tmpdir/test.tmpl"

	local output
	output=$(GH_PR_DIFF='contains ${SECRET} token' _cmd_render "$tmpdir/test.tmpl")

	[[ "$output" == *'contains ${SECRET} token'* ]]
}

@test "_cmd_render: returns error for missing template file" {
	run _cmd_render "/nonexistent/template.tmpl"

	[[ "$status" -eq 1 ]]
}

@test "_cmd_render: preserves multiline content in substituted values" {
	local tmpdir="$BATS_TMPDIR/render-multiline-test-$$"
	mkdir -p "$tmpdir"
	printf 'Log:\n${MY_LOG}\nEnd.\n' >"$tmpdir/test.tmpl"

	local output
	output=$(MY_LOG=$'line one\nline two\nline three' _cmd_render "$tmpdir/test.tmpl")

	[[ "$output" == *"line one"* ]]
	[[ "$output" == *"line two"* ]]
	[[ "$output" == *"line three"* ]]
}

# File-backed _cmd_render tests
# These test the *_FILE env var support for bypassing ARG_MAX

@test "_cmd_render: reads file content from VAR_FILE env var" {
	local tmpdir="$BATS_TMPDIR/render-file-test-$$"
	mkdir -p "$tmpdir"
	printf 'Diff:\n${GH_PR_DIFF}\nEnd.\n' >"$tmpdir/test.tmpl"
	printf 'line one\nline two\nline three' >"$tmpdir/diff.patch"

	local output
	output=$(GH_PR_DIFF_FILE="$tmpdir/diff.patch" _cmd_render "$tmpdir/test.tmpl")

	[[ "$output" == *"line one"* ]]
	[[ "$output" == *"line two"* ]]
	[[ "$output" == *"line three"* ]]
}

@test "_cmd_render: direct env var takes priority over _FILE" {
	local tmpdir="$BATS_TMPDIR/render-priority-test-$$"
	mkdir -p "$tmpdir"
	printf 'Value: ${MY_VAR}\n' >"$tmpdir/test.tmpl"
	printf 'from file' >"$tmpdir/value.txt"

	local output
	output=$(MY_VAR="from env" MY_VAR_FILE="$tmpdir/value.txt" _cmd_render "$tmpdir/test.tmpl")

	[[ "$output" == *"Value: from env"* ]]
	[[ "$output" != *"from file"* ]]
}

@test "_cmd_render: nonexistent _FILE path produces empty string" {
	local tmpdir="$BATS_TMPDIR/render-missing-test-$$"
	mkdir -p "$tmpdir"
	printf 'Value: [${MY_VAR}]\n' >"$tmpdir/test.tmpl"

	local output
	output=$(MY_VAR_FILE="/nonexistent/file.txt" _cmd_render "$tmpdir/test.tmpl")

	[[ "$output" == *"Value: []"* ]]
}

@test "_cmd_render: multiline file content preserved in _FILE" {
	local tmpdir="$BATS_TMPDIR/render-multiline-file-test-$$"
	mkdir -p "$tmpdir"
	printf 'Content:\n${MY_CONTENT}\nEnd.\n' >"$tmpdir/test.tmpl"
	printf 'line one\nline two\nline three' >"$tmpdir/content.txt"

	local output
	output=$(MY_CONTENT_FILE="$tmpdir/content.txt" _cmd_render "$tmpdir/test.tmpl")

	[[ "$output" == *"line one"* ]]
	[[ "$output" == *"line two"* ]]
	[[ "$output" == *"line three"* ]]
}

@test "_cmd_render: patterns in file content not re-expanded" {
	local tmpdir="$BATS_TMPDIR/render-safety-file-test-$$"
	mkdir -p "$tmpdir"
	printf 'Diff:\n${GH_DIFF}\nEnd.\n' >"$tmpdir/test.tmpl"
	printf 'contains ${SECRET_TOKEN} and ${OTHER} patterns' >"$tmpdir/diff.patch"

	local output
	output=$(GH_DIFF_FILE="$tmpdir/diff.patch" _cmd_render "$tmpdir/test.tmpl")

	# Patterns from file should be preserved as-is, not re-expanded
	[[ "$output" == *'contains ${SECRET_TOKEN} and ${OTHER} patterns'* ]]
}

# ---------------------------------------------------------------------------
# _parse_title
# ---------------------------------------------------------------------------

@test "_parse_title: extracts title from markdown heading" {
	local output
	output=$(_parse_title "# Fix bug in parser

Description of the fix.")

	[[ "$output" == "Fix bug in parser" ]]
}

@test "_parse_title: extracts title without heading prefix" {
	local output
	output=$(_parse_title "Add new feature

Body text here.")

	[[ "$output" == "Add new feature" ]]
}

@test "_parse_title: returns error for empty content" {
	run _parse_title ""

	[[ "$status" -eq 1 ]]
}

@test "_parse_title: strips only the first heading hash" {
	local output
	output=$(_parse_title "## Sub heading title")

	[[ "$output" == "# Sub heading title" ]]
}

# ---------------------------------------------------------------------------
# _parse_body
# ---------------------------------------------------------------------------

@test "_parse_body: extracts body after title line with footer" {
	local output
	output=$(_parse_body "# Title

Body paragraph one.

Body paragraph two.")

	[[ "$output" == *"Body paragraph one."* ]]
	[[ "$output" == *"Body paragraph two."* ]]
	[[ "$output" == *"markdownlint-disable-file"* ]]
}

@test "_parse_body: strips leading blank lines" {
	local output
	output=$(_parse_body "# Title


Actual body.")

	# First char of output should not be a newline
	[[ "${output:0:1}" != $'\n' ]]
	[[ "$output" == *"Actual body."* ]]
}

@test "_parse_body: returns only footer for title-only content" {
	local output
	output=$(_parse_body "# Title only")

	[[ "$output" == *"markdownlint-disable-file"* ]]
}

# ---------------------------------------------------------------------------
# _gh_config_ai_model
# ---------------------------------------------------------------------------

@test "_gh_config_ai_model: returns agent default when no config set" {
	gh() {
		case "$*" in
		"config get ai.agent"*) echo "gemini" ;;
		*) :; ;;
		esac
	}
	export -f gh

	local output
	output=$(_gh_config_ai_model)

	[[ "$output" == "gemini-2.0-flash" ]]
}

@test "_gh_config_ai_model: returns haiku by default with no scope and no config" {
	gh() { :; }
	export -f gh

	local output
	output=$(_gh_config_ai_model)

	[[ "$output" == "haiku" ]]
}

@test "_gh_config_ai_model: returns ai.model when set, no scope" {
	gh() {
		case "$*" in
		"config get ai.agent"*) echo "claude" ;;
		"config get ai.model"*) echo "sonnet" ;;
		*) :; ;;
		esac
	}
	export -f gh

	local output
	output=$(_gh_config_ai_model)

	[[ "$output" == "sonnet" ]]
}

@test "_gh_config_ai_model: returns ai.pr.model when set with pr scope" {
	gh() {
		case "$*" in
		*"ai.pr.model"*) echo "opus" ;;
		*) :; ;;
		esac
	}
	export -f gh

	local output
	output=$(_gh_config_ai_model "pr")

	[[ "$output" == "opus" ]]
}

@test "_gh_config_ai_model: falls back to ai.model when ai.pr.model unset" {
	gh() {
		case "$*" in
		*"ai.pr.model"*) :; ;;
		*"ai.model"*) echo "sonnet" ;;
		*) :; ;;
		esac
	}
	export -f gh

	local output
	output=$(_gh_config_ai_model "pr")

	[[ "$output" == "sonnet" ]]
}

@test "_gh_config_ai_model: falls back to agent default when config keys unset" {
	gh() {
		case "$*" in
		"config get ai.agent"*) echo "codex" ;;
		*) :; ;;
		esac
	}
	export -f gh

	local output
	output=$(_gh_config_ai_model "pr")

	[[ "$output" == "gpt-5.4-mini" ]]
}

@test "_gh_config_ai_model: _GH_AI_ARGS --model overrides config" {
	gh() { echo "sonnet"; }
	export -f gh

	_GH_AI_ARGS=(--model opus)
	local output
	output=$(_gh_config_ai_model "pr")

	[[ "$output" == "opus" ]]
}

# ---------------------------------------------------------------------------
# Dispatch tests
# ---------------------------------------------------------------------------

@test "_cmd_ask: dispatches to correct agent" {
	gh() { echo "codex"; }
	export -f gh

	_ask_codex() { echo "called codex with $1"; }
	export -f _ask_codex

	run _cmd_ask "custom-model"
	[[ "$output" == "called codex with custom-model" ]]
}

@test "_cmd_chat: dispatches to correct agent" {
	gh() { echo "gemini"; }
	export -f gh

	# Mock command -v to succeed for gemini
	command() { [[ "$2" == "gemini" ]] && return 0 || builtin command "$@"; }
	export -f command

	_chat_gemini() { echo "called gemini chat"; }
	export -f _chat_gemini

	run _cmd_chat "my prompt"
	[[ "$output" == "called gemini chat" ]]
}

# ---------------------------------------------------------------------------
# _extract_ai_arg
# ---------------------------------------------------------------------------

@test "_extract_ai_arg: returns value for present flag" {
	_GH_AI_ARGS=(--model sonnet)
	local output
	output=$(_extract_ai_arg --model)

	[[ "$output" == "sonnet" ]]
}

@test "_extract_ai_arg: returns empty for absent flag" {
	_GH_AI_ARGS=(--verbose)
	local output
	output=$(_extract_ai_arg --model)

	[[ -z "$output" ]]
}

@test "_extract_ai_arg: returns empty with empty array" {
	_GH_AI_ARGS=()
	local output
	output=$(_extract_ai_arg --model)

	[[ -z "$output" ]]
}

@test "_extract_ai_arg: handles flag at end without value" {
	_GH_AI_ARGS=(--model)
	local output
	output=$(_extract_ai_arg --model)

	[[ -z "$output" ]]
}
