# gh-issue-plugin

A Claude Code plugin that provides slash commands for working with GitHub issues inside `gh claude issue chat` sessions.

## Slash Commands

Available inside a `gh claude issue chat` session. The issue number is already known from the session — no need to pass it. Each command follows a **draft → iterate → confirm → execute** workflow.

> These are Claude Code skill equivalents to `gh claude issue comment`, `gh claude issue edit`, and `gh claude issue plan`.

### /gh:issue:comment

Drafts a comment on the current issue and posts it after you confirm.

**Use cases:** "write a comment on this issue", "draft a response", "add a comment saying...", "reply to this issue"

```
/gh:issue:comment thank the reporter and ask for a reproduction case
/gh:issue:comment summarize the discussion so far
```

**Notes:**

- If no argument is given, the skill infers a helpful comment from the issue context.
- The draft is saved to `$GH_CLAUDE_SESSION_DIR/drafts/issue_comment_draft.md` before posting.

---

### /gh:issue:edit

Edits the title and/or body of the current issue and applies the change after you confirm.

**Use cases:** "edit this issue", "update the issue body", "rewrite the description", "fix the issue title", "add acceptance criteria"

```
/gh:issue:edit add a definition of done section
/gh:issue:edit shorten the title and add reproduction steps
/gh:issue:edit rewrite the description as a bug report
```

**Notes:**

- Only the requested changes are applied; existing wording is preserved unless explicitly changed.
- Titles are kept under 72 characters.

---

### /gh:issue:plan

Generates an implementation plan for the current issue and posts it as a comment after you confirm. The plan is a proposal for discussion — it does not execute any code.

**Use cases:** "plan this issue", "create an implementation plan", "break down this issue into tasks", "what steps do I need to implement #N?"

```
/gh:issue:plan focus on the database migration
/gh:issue:plan focus on the auth module
```

**Notes:**

- Idempotent: if a plan comment already exists on the issue (identified by the `<!-- gh-claude:issue-plan issue=N -->` marker), the skill updates that comment instead of creating a duplicate.
- Tasks use sequential labels (Task 1, Task 2, ...) for easy reference.
- If a focus area is provided, the plan is scoped to that area only.

## Environment variables

| Variable | Used by |
|----------|---------|
| `GH_ISSUE_NUMBER` | All commands — identifies the issue to operate on |
| `GH_CLAUDE_SESSION_DIR` | All commands — root for `drafts/` and `state/` subdirectories |
| `CLAUDE_PLUGIN_ROOT` | All commands — path to jq query files |
