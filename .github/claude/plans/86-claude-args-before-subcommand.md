<!-- gh-claude:issue-plan issue=86 -->

# Move claude agent args before subcommand — Execution Plan

**Issue:** [#86](https://github.com/gh-extensions/gh-claude/issues/86) — Move claude agent args before subcommand to eliminate -- separator
**Branch:** `86/claude-args-before-subcommand`
**Type:** Refactor
**Estimate:** Small (1-2 days)
**Risk:** Medium — touches argument parsing in every command path; breaking change to CLI interface
**Created:** 2026-03-19

---

## Goal

Eliminate the `--` separator for claude agent args by collecting them before the subcommand keyword (e.g., `gh claude --model sonnet pr chat 42` instead of `gh claude pr chat 42 -- --model sonnet`). The `--` separator remains only for `gh` CLI passthrough args in create/edit/comment/review commands. No backward compatibility — the old `--` syntax for agent args stops working.

## Approach

Add an arg collection loop to `main()` in `gh-claude` that scans arguments until it hits a recognized subcommand keyword (`pr`, `issue`, `run`). Everything before the keyword goes into a script-scoped `_GH_CLAUDE_ARGS=()` array. The subcommand dispatchers (`_gh_pr`, `_gh_issue`, `_gh_run`) don't need signature changes since `_GH_CLAUDE_ARGS` is visible as a script-level variable. Chat commands forward the full array to `_cmd_chat` (called in-process). Ask-mode commands extract `--model` from the array to override config. Chat commands stop using `_split_on_separator` and `_extract_chat_passthrough` entirely — those functions remain only for create/edit/comment/review `gh` passthrough.

## Affected Areas

- `gh-claude:L82-L109` — `main()` arg collection loop
- `scripts/gh_cmd.sh:L58-L72` — `_cmd_ask` model override
- `scripts/gh_cmd.sh:L105-L125` — `_cmd_chat` forwarding `_GH_CLAUDE_ARGS`
- `scripts/gh_cmd.sh:L415-L453` — `_extract_chat_passthrough` (remove usage from chat path)
- `scripts/gh_pr.sh:L798-L860` — `_gh_pr_chat` simplified
- `scripts/gh_pr.sh:L758-L789` — `_show_pr_chat_help` updated
- `scripts/gh_pr.sh:L1012-L1044` — `_show_pr_help` updated
- `scripts/gh_issue.sh:L738-L790` — `_gh_issue_chat` simplified
- `scripts/gh_issue.sh:L699-L729` — `_show_issue_chat_help` updated
- `scripts/gh_issue.sh:L796-L827` — `_show_issue_help` updated
- `scripts/gh_run.sh:L241-L296` — `_gh_run_chat` simplified
- `scripts/gh_run.sh:L202-L232` — `_show_run_chat_help` updated
- `scripts/gh_run.sh:L298-L322` — `_show_run_help` updated
- `tests/gh_pr_chat.bats` — update passthrough tests
- `tests/gh_issue_chat.bats` — update passthrough tests
- `tests/gh_run_chat.bats` — update passthrough tests
- `tests/gh_cmd.bats` — new tests for arg collection and `_extract_claude_arg`

## Tasks

### Task 1: Collect claude args in `main()` — S — [x] Complete

**What:** Replace the `cmd="${1:-}"; shift` pattern in `gh-claude:main()` with a loop that collects all arguments before the first recognized subcommand keyword (`pr`, `issue`, `run`) into a script-scoped `_GH_CLAUDE_ARGS=()` array. Handle `--help`/`--version` as early exits during scanning. The keyword and everything after dispatch normally.

**Files:**

- Modify: `gh-claude`

**Test strategy:** Test in Task 5. Key scenarios: no claude args (just subcommand), single flag (`--model sonnet`), multiple flags, `--help` before subcommand, `--version`, unknown arg before subcommand, no subcommand at all.

**Acceptance criteria:**

- [ ] `gh claude --model sonnet pr chat 42` collects `--model sonnet` into `_GH_CLAUDE_ARGS` and dispatches `pr chat 42`
- [ ] `gh claude pr chat 42` works with empty `_GH_CLAUDE_ARGS`
- [ ] `gh claude --help` and `gh claude --version` still work
- [ ] `gh claude` with no args shows help

**Commit message:** `refactor(main): collect claude args before subcommand keyword`

---

### Task 2: Forward `_GH_CLAUDE_ARGS` in `_cmd_chat` and extract model for ask-mode — M — [x] Complete

**What:** In `_cmd_chat`, append `"${_GH_CLAUDE_ARGS[@]}"` to the `claude` invocation (after session args). Add a helper `_extract_claude_arg` that reads a named flag's value from `_GH_CLAUDE_ARGS` (e.g., `_extract_claude_arg --model` returns the model value). In each ask-mode caller, use `_extract_claude_arg --model` to override `_gh_config_claude_model` when `--model` was passed globally. The `_cmd_ask` subprocess receives the model via its existing positional parameter, so no subprocess interface changes.

**Files:**

- Modify: `scripts/gh_cmd.sh` — add `_extract_claude_arg`, update `_cmd_chat`
- Modify: `scripts/gh_pr.sh` — all ask-mode callers (`_gh_pr_create`, `_gh_pr_edit`, `_gh_pr_review`, `_gh_pr_explain`, `_gh_pr_comment`) use `_extract_claude_arg --model` to override model
- Modify: `scripts/gh_issue.sh` — ask-mode callers (`_gh_issue_create`, `_gh_issue_edit`, `_gh_issue_comment`, `_gh_issue_plan`) use override
- Modify: `scripts/gh_run.sh` — ask-mode caller (`_gh_run_explain`) uses override

**Test strategy:** Test `_extract_claude_arg` in `gh_cmd.bats`. Verify model override works when `_GH_CLAUDE_ARGS` contains `--model sonnet`. Verify `_cmd_chat` forwards all `_GH_CLAUDE_ARGS` to claude.

**Acceptance criteria:**

- [ ] `_extract_claude_arg --model` returns value when `_GH_CLAUDE_ARGS=(--model sonnet)`
- [ ] `_extract_claude_arg --model` returns empty when `_GH_CLAUDE_ARGS` has no `--model`
- [ ] `_cmd_chat` forwards `_GH_CLAUDE_ARGS` entries to the claude binary
- [ ] Ask-mode commands use `--model` from `_GH_CLAUDE_ARGS` over config

**Commit message:** `refactor(cmd): forward _GH_CLAUDE_ARGS to claude and extract model for ask-mode`

---

### Task 3: Simplify chat commands — remove `--` splitting for agent args — M — [x] Complete

**What:** In `_gh_pr_chat`, `_gh_issue_chat`, and `_gh_run_chat`: remove the `_split_on_separator` call and `_extract_chat_passthrough` call. Parse subcommand args (resource ID, `-d`/`--description`) directly from `$@`. Extract `--session-id`/`--resume` from `_GH_CLAUDE_ARGS` using `_extract_claude_arg`. The `_cmd_chat` call simplifies to `_cmd_chat "$url" "$prompt" "${session_args[@]}"` — the `_GH_CLAUDE_ARGS` are forwarded by `_cmd_chat` internally. Delete `_extract_chat_passthrough` from `gh_cmd.sh` since no callers remain.

**Files:**

- Modify: `scripts/gh_pr.sh` — `_gh_pr_chat` (remove split/extract, use `_extract_claude_arg` for session)
- Modify: `scripts/gh_issue.sh` — `_gh_issue_chat` (same)
- Modify: `scripts/gh_run.sh` — `_gh_run_chat` (same)
- Modify: `scripts/gh_cmd.sh` — delete `_extract_chat_passthrough`

**Test strategy:** Test that chat commands work with session args in `_GH_CLAUDE_ARGS`. Test that `--resume` and `--session-id` are extracted correctly. Test that `_cmd_chat` is called with session args only (no leftover passthrough).

**Acceptance criteria:**

- [ ] `_GH_CLAUDE_ARGS=(--resume abc123)` is correctly extracted for session resolution
- [ ] `_GH_CLAUDE_ARGS=(--session-id my-session)` is correctly extracted for session resolution
- [ ] Chat commands no longer split on `--`
- [ ] `_extract_chat_passthrough` is deleted from `gh_cmd.sh`

**Commit message:** `refactor(chat): extract session args from _GH_CLAUDE_ARGS, remove -- splitting`

---

### Task 4: Update help text — S — [x] Complete

**What:** Update all help functions to reflect the new arg placement. Remove `[-- AGENT_OPTIONS]` from chat command USAGE lines. Show agent flags before the subcommand in examples. Keep `[-- GH_*_OPTIONS]` in create/edit/comment/review help unchanged. Update the top-level `_show_help` to mention global flags.

**Files:**

- Modify: `gh-claude` — `_show_help`
- Modify: `scripts/gh_pr.sh` — `_show_pr_chat_help`, `_show_pr_help`
- Modify: `scripts/gh_issue.sh` — `_show_issue_chat_help`, `_show_issue_help`
- Modify: `scripts/gh_run.sh` — `_show_run_chat_help`, `_show_run_help`

**Test strategy:** Existing help tests check for key strings. Update assertions if output strings changed.

**Acceptance criteria:**

- [ ] Chat help shows `gh claude [AGENT_OPTIONS] pr chat [PR_NUMBER]` style usage
- [ ] Chat help examples show `gh claude --model sonnet pr chat 42`
- [ ] Non-chat help still shows `[-- GH_*_OPTIONS]` for gh passthrough
- [ ] Top-level help mentions agent options placement

**Commit message:** `docs(help): update usage examples for pre-subcommand agent args`

---

### Task 5: Update tests — L — [x] Complete

**What:** Update `gh_pr_chat.bats`, `gh_issue_chat.bats`, `gh_run_chat.bats`: change all tests that pass claude args after `--` to set `_GH_CLAUDE_ARGS` instead. Remove `_extract_chat_passthrough` from the `declare -f` lists in test setup blocks. Add `_extract_claude_arg` to the `declare -f` lists. Add new tests in `gh_cmd.bats` for `_extract_claude_arg` helper. Add tests for `main()` arg collection (may need a new test file or integration-style tests).

**Files:**

- Modify: `tests/gh_pr_chat.bats` — update passthrough tests, setup blocks
- Modify: `tests/gh_issue_chat.bats` — update passthrough tests, setup blocks
- Modify: `tests/gh_run_chat.bats` — update passthrough tests, setup blocks
- Modify: `tests/gh_cmd.bats` — add `_extract_claude_arg` tests

**Test strategy:** Run full test suite (`bats tests/`). Verify all existing tests pass with modifications. New tests cover: `_extract_claude_arg` with various flag positions, `_GH_CLAUDE_ARGS` forwarding in `_cmd_chat`, session arg extraction from `_GH_CLAUDE_ARGS`.

**Acceptance criteria:**

- [ ] All existing bats tests pass (with updates)
- [ ] `_extract_claude_arg` has unit tests for: flag present, flag absent, flag at different positions
- [ ] Chat tests verify `_GH_CLAUDE_ARGS` forwarding works
- [ ] No test references `_extract_chat_passthrough`

**Commit message:** `test: update tests for pre-subcommand claude args`

## Task Dependencies

Task 1 → Tasks 2, 3 (both need the global array). Task 4 is independent. Task 5 depends on all others.

Critical path: **Task 1 → Task 3 → Task 5**

## Open Questions

- Should `--effort` also be extracted and forwarded to `_cmd_ask` (prompt mode) alongside `--model`, or is `--model` the only relevant ask-mode override?

## Dependencies & Blockers

- None
