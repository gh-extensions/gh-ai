# gh-issue-plugin

A Claude Code plugin that provides slash commands for working with GitHub issues inside `gh claude issue chat` sessions.

## Skills

### gh:issue:comment

Drafts a comment on the current issue and posts it after you confirm.

**Triggers:** "write a comment on this issue", "draft a response", "add a comment saying...", "reply to this issue"

**Usage:**

```
/gh:issue:comment
/gh:issue:comment thank the reporter and ask for a reproduction case
```

**Workflow:** Draft → show preview → iterate on feedback → confirm → post via `gh issue comment`.

**Notes:**

- If no argument is given, the skill infers a helpful comment from the issue context.
- The draft is saved to `$GH_CLAUDE_SESSION_DIR/drafts/issue_comment_draft.md` before posting.

---

### gh:issue:edit

Edits the title and/or body of the current issue and applies the change after you confirm.

**Triggers:** "edit this issue", "update the issue body", "rewrite the description", "fix the issue title", "add acceptance criteria"

**Usage:**

```
/gh:issue:edit
/gh:issue:edit add a definition of done section
/gh:issue:edit shorten the title and add reproduction steps
```

**Workflow:** Apply changes → show full updated issue as a draft → iterate → confirm → apply via `gh issue edit`.

**Notes:**

- Only the requested changes are applied; existing wording is preserved unless explicitly changed.
- Titles are kept under 72 characters.

---

### gh:issue:plan

Generates an implementation plan for the current issue and posts it as a comment after you confirm. The plan is a proposal for discussion — it does not execute any code.

**Triggers:** "plan this issue", "create an implementation plan", "break down this issue into tasks", "what steps do I need to implement #N?"

**Usage:**

```
/gh:issue:plan
/gh:issue:plan focus on the database migration
```

**Workflow:** Analyze requirements → draft plan with task IDs (T001, T002, ...) → show preview → iterate → confirm → post or update comment.

**Notes:**

- Idempotent: if a plan comment already exists on the issue (identified by the `<!-- gh-claude:issue-plan issue=N -->` marker), the skill updates that comment instead of creating a duplicate.
- Tasks use sequential IDs (T001, T002, ...) for easy reference.
- If a focus area is provided, the plan is scoped to that area only.

## Environment variables

| Variable | Used by |
|----------|---------|
| `GH_ISSUE_NUMBER` | All skills — identifies the issue to operate on |
| `GH_CLAUDE_SESSION_DIR` | All skills — root for `drafts/` and `state/` subdirectories |
| `CLAUDE_PLUGIN_ROOT` | All skills — path to jq query files |
