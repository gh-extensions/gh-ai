#!/usr/bin/env bats

# Unit tests for session management functions in gh_cmd.sh
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_session.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _gh_ai_source_dir="$REPO_ROOT"
	export HOME="$BATS_TEST_TMPDIR"
	unset XDG_STATE_HOME

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
		export _gh_ai_source_dir="$REPO_ROOT"
		# shellcheck source=../scripts/gh_cmd.sh
		source "$REPO_ROOT/scripts/gh_cmd.sh"
		declare -f _gh_context_base_dir _create_context_dir _resolve_context_dir _save_context_file _extract_ai_arg
	)"
}

# ---------------------------------------------------------------------------
# _gh_context_base_dir
# ---------------------------------------------------------------------------

@test "_gh_context_base_dir: returns default path" {
	local result
	result=$(_gh_context_base_dir)
	echo "HOME: $HOME"
	echo "result: $result"
	[[ "$result" == "$HOME/.local/state/gh/ai/context" ]]
}

# ---------------------------------------------------------------------------
# _gh_context_base_dir
# ---------------------------------------------------------------------------

@test "_gh_context_base_dir: respects XDG_STATE_HOME" {
	export XDG_STATE_HOME="/tmp/state"
	local result
	result=$(_gh_context_base_dir)
	[[ "$result" == "/tmp/state/gh/ai/context" ]]
}

# ---------------------------------------------------------------------------
# _create_context_dir
# ---------------------------------------------------------------------------

@test "_create_context_dir: creates a temporary directory" {
	local dir=""
	_create_context_dir dir

	[[ -d "$dir" ]]
	[[ "$dir" == *"gh-ai-ctx."* ]]
	rm -rf "$dir"
}

# ---------------------------------------------------------------------------
# _resolve_context_dir
# ---------------------------------------------------------------------------

@test "_resolve_context_dir: creates persistent dir for analyze" {
	local dir=""
	_resolve_context_dir "analyze" "pull-42" dir

	[[ -d "$dir" ]]
	[[ "$dir" == "$HOME/.local/state/gh/ai/context/pull-42" ]]
}

@test "_resolve_context_dir: creates temp dir for non-analyze" {
	local dir=""
	_resolve_context_dir "edit" "issue-1" dir

	[[ -d "$dir" ]]
	[[ "$dir" == *"gh-ai-ctx."* ]]
	rm -rf "$dir"
}

@test "_resolve_context_dir: re-creates analyze dir on each call" {
	local dir1=""
	_resolve_context_dir "analyze" "pull-42" dir1

	local dir2=""
	_resolve_context_dir "analyze" "pull-42" dir2

	[[ "$dir1" == "$dir2" ]]
	[[ -d "$dir1" ]]
}

# ---------------------------------------------------------------------------
# _extract_ai_arg
# ---------------------------------------------------------------------------

@test "_extract_ai_arg: extracts flag value" {
	_GH_AI_ARGS=(--model sonnet --verbose)
	local result
	result=$(_extract_ai_arg --model)

	[[ "$result" == "sonnet" ]]
}
