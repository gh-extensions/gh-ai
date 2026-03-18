#!/usr/bin/env bats

# Unit tests for _extract_issue_number
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/gh_issue_args.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
	export _gh_claude_source_dir="$REPO_ROOT"

	gum() { if [[ "$1" == "log" ]]; then shift; shift; shift; echo "$@"; fi; }
	gh() { echo ""; }
	git() { echo ""; }
	export -f gum gh git

	# shellcheck disable=SC2155
	eval "$(
		export _gh_claude_source_dir="$REPO_ROOT"
		# shellcheck source=../scripts/gh_cmd.sh
		source "$REPO_ROOT/scripts/gh_cmd.sh"
		# shellcheck source=../scripts/gh_issue.sh
		source "$REPO_ROOT/scripts/gh_issue.sh"
		declare -f _extract_issue_number
	)"
}

# ---------------------------------------------------------------------------
# Bare integers
# ---------------------------------------------------------------------------

@test "_extract_issue_number: bare integer returns the number" {
	run _extract_issue_number "42"

	[[ "$status" -eq 0 ]]
	[[ "$output" == "42" ]]
}

@test "_extract_issue_number: bare integer with many digits" {
	run _extract_issue_number "12345"

	[[ "$status" -eq 0 ]]
	[[ "$output" == "12345" ]]
}

# ---------------------------------------------------------------------------
# Hash-prefixed numbers
# ---------------------------------------------------------------------------

@test "_extract_issue_number: hash-prefixed number strips the hash" {
	run _extract_issue_number "#42"

	[[ "$status" -eq 0 ]]
	[[ "$output" == "42" ]]
}

# ---------------------------------------------------------------------------
# Canonical GitHub issue URLs
# ---------------------------------------------------------------------------

@test "_extract_issue_number: canonical GitHub issue URL" {
	run _extract_issue_number "https://github.com/owner/repo/issues/123"

	[[ "$status" -eq 0 ]]
	[[ "$output" == "123" ]]
}

@test "_extract_issue_number: URL with trailing slash" {
	run _extract_issue_number "https://github.com/owner/repo/issues/123/"

	[[ "$status" -eq 0 ]]
	[[ "$output" == "123" ]]
}

@test "_extract_issue_number: URL with query string" {
	run _extract_issue_number "https://github.com/owner/repo/issues/123?tab=timeline"

	[[ "$status" -eq 0 ]]
	[[ "$output" == "123" ]]
}

@test "_extract_issue_number: URL with fragment" {
	run _extract_issue_number "https://github.com/owner/repo/issues/123#issuecomment-456"

	[[ "$status" -eq 0 ]]
	[[ "$output" == "123" ]]
}

@test "_extract_issue_number: URL with org and hyphenated repo name" {
	run _extract_issue_number "https://github.com/my-org/my-repo/issues/7"

	[[ "$status" -eq 0 ]]
	[[ "$output" == "7" ]]
}

# ---------------------------------------------------------------------------
# Error cases
# ---------------------------------------------------------------------------

@test "_extract_issue_number: empty string returns error" {
	run _extract_issue_number ""

	[[ "$status" -eq 1 ]]
	[[ -z "$output" ]]
}

@test "_extract_issue_number: non-numeric string returns error" {
	run _extract_issue_number "foo"

	[[ "$status" -eq 1 ]]
	[[ -z "$output" ]]
}

@test "_extract_issue_number: PR URL returns error" {
	run _extract_issue_number "https://github.com/owner/repo/pull/123"

	[[ "$status" -eq 1 ]]
	[[ -z "$output" ]]
}

@test "_extract_issue_number: non-GitHub URL returns error" {
	run _extract_issue_number "https://gitlab.com/owner/repo/issues/42"

	[[ "$status" -eq 1 ]]
	[[ -z "$output" ]]
}

@test "_extract_issue_number: URL without a number returns error" {
	run _extract_issue_number "https://github.com/owner/repo/issues/"

	[[ "$status" -eq 1 ]]
	[[ -z "$output" ]]
}

@test "_extract_issue_number: flag-like string returns error" {
	run _extract_issue_number "--comment"

	[[ "$status" -eq 1 ]]
	[[ -z "$output" ]]
}
