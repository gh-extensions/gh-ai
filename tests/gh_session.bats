#!/usr/bin/env bats

# Unit tests for session management functions in gh_cmd.sh
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_session.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _gh_claude_source_dir="$REPO_ROOT"
	export HOME="$BATS_TEST_TMPDIR"

	gum() { if [[ "$1" == "log" ]]; then shift; shift; shift; echo "$@"; fi; }
	git() {
		case "$1 $2" in
		"rev-parse --show-toplevel") echo "$BATS_TEST_TMPDIR" ;;
		"rev-parse --abbrev-ref") echo "" ;;
		"rev-parse --git-common-dir") echo "$BATS_TEST_TMPDIR/.git" ;;
		esac
	}
	export -f gum git

	# shellcheck disable=SC2155
	eval "$(
		export _gh_claude_source_dir="$REPO_ROOT"
		# shellcheck source=../scripts/gh_cmd.sh
		source "$REPO_ROOT/scripts/gh_cmd.sh"
		declare -f _create_context_dir _resolve_context_dir _save_context_file _extract_claude_arg
	)"
}

# ---------------------------------------------------------------------------
# _create_context_dir
# ---------------------------------------------------------------------------

@test "_create_context_dir: creates a temporary directory" {
	local dir=""
	_create_context_dir dir

	[[ -d "$dir" ]]
	[[ "$dir" == *"gh-claude-ctx."* ]]
	rm -rf "$dir"
}

# ---------------------------------------------------------------------------
# _resolve_context_dir
# ---------------------------------------------------------------------------

@test "_resolve_context_dir: always creates a temporary directory" {
	local dir=""
	_resolve_context_dir "chat" "pull-42" dir

	[[ -d "$dir" ]]
	[[ "$dir" == *"gh-claude-ctx."* ]]
	rm -rf "$dir"
}

# ---------------------------------------------------------------------------
# _extract_claude_arg
# ---------------------------------------------------------------------------

@test "_extract_claude_arg: extracts flag value" {
	_GH_CLAUDE_ARGS=(--model sonnet --verbose)
	local result
	result=$(_extract_claude_arg --model)

	[[ "$result" == "sonnet" ]]
}
