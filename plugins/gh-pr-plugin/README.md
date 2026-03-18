# gh-pr-plugin

A Claude Code plugin that provides slash commands for working with GitHub pull requests inside `gh claude pr chat` sessions.

## Slash Commands

Available inside a `gh claude pr chat` session. The PR number is already known from the session — no need to pass it.

```
/gh:pr:comment [what to say]
/gh:pr:edit    [what to change]
/gh:pr:review  [approve|request-changes|comment] [focus area]
```

All three commands follow a **draft → iterate → confirm → execute** workflow: generate a draft, show it, accept revisions, and only run the `gh` CLI command once confirmed.

> These are Claude Code skill equivalents to `gh claude pr comment`, `gh claude pr edit`, and `gh claude pr review`.

## Skills

### gh:pr:comment

Drafts a comment on the current PR and posts it after you confirm.

**Triggers:** "write a comment on this PR", "draft a response", "add a comment saying...", "reply to this pull request", "respond to a review"

**Usage:**

```
/gh:pr:comment
/gh:pr:comment ask the author to add tests for the edge cases
```

**Workflow:** Draft → show preview → iterate on feedback → confirm → post via `gh pr comment`.

**Notes:**

- If no argument is given, the skill infers a helpful comment from the PR context.
- The draft is saved to `$GH_CLAUDE_SESSION_DIR/drafts/pr_comment_draft.md` before posting.

---

### gh:pr:edit

Edits the title and/or body of the current PR and applies the change after you confirm.

**Triggers:** "edit this PR", "update the PR body", "rewrite the description", "fix the PR title", "add a testing section", "update the checklist"

**Usage:**

```
/gh:pr:edit
/gh:pr:edit add a testing section and update the summary
/gh:pr:edit shorten the title
```

**Workflow:** Apply changes → show full updated PR as a draft → iterate → confirm → apply via `gh pr edit`.

**Notes:**

- Only the requested changes are applied; existing wording is preserved unless explicitly changed.
- Titles are kept under 72 characters.

---

### gh:pr:review

Generates a structured code review for the current PR and submits it after you confirm. Supports approve, request-changes, and comment outcomes.

**Triggers:** "review this PR", "approve PR #42", "request changes on this PR", "give feedback on this pull request", "do a code review focusing on security"

**Usage:**

```
/gh:pr:review
/gh:pr:review approve
/gh:pr:review request-changes
/gh:pr:review comment focus on error handling
/gh:pr:review approve focus on the auth changes
```

**Workflow:** Check for prior AI review → fetch diff → analyze changes → draft review with outcome → show preview → iterate → confirm → submit via `gh pr review`.

**Notes:**

- Before generating, the skill checks whether an AI review already exists for the current head commit (via the `<!-- gh-claude:pr-review pr=N commit=SHA -->` marker). If one exists, it asks whether to proceed.
- If no review type is specified, the outcome is chosen based on findings: approve (no blocking issues), request-changes (high-severity issues), or comment (observations only).
- Findings use severity levels: **High** (blocks approval), **Medium** (logic/edge cases), **Low** (minor improvements).
- Inline diff comments are not supported — file and line references in the review body are informational pointers only.
- GitHub has no "reject" action; requests to reject are mapped to request-changes.

## Environment variables

| Variable | Used by |
|----------|---------|
| `GH_PR_NUMBER` | All skills — identifies the PR to operate on |
| `GH_CLAUDE_SESSION_DIR` | All skills — root for `drafts/` and `state/` subdirectories |
| `CLAUDE_PLUGIN_ROOT` | All skills — path to jq query files |
