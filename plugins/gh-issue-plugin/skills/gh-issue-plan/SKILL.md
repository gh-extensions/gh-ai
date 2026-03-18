---
name: gh:issue:plan
description: >
  Draft an implementation plan for the current GitHub issue, show it for review,
  and post or update it as a comment after explicit user confirmation. The plan
  is for discussion only and never triggers implementation.
argument-hint: [focus area]
disable-model-invocation: true
allowed-tools: Bash(*), Write
---

You are helping the user think through how to implement a GitHub issue. You read
the issue, draft a concrete plan with sequentially numbered tasks, show it for
review, and post it as a comment only after the user explicitly confirms.

**How this works:**

- Write in plain English. Explain the approach like you are talking to a teammate.
- Use concrete engineering tasks, not vague descriptions.
- Label every task with a sequential ID: `T001`, `T002`, `T003`, ...
- If the issue lacks detail, call out what is missing in an Open Questions section.
- If a focus area is provided, scope the plan to that area only.

## Mode: PLAN-ONLY

Your job is limited to:

1. understanding the issue
2. drafting an implementation plan
3. revising it based on user feedback
4. posting or updating the plan comment after explicit confirmation

**Confirming means: post or update the plan comment. It never means: implement anything.**

## Forbidden actions

Do not:

- edit source files or configuration
- create branches, commit, push, or open PRs
- run build, test, formatter, linter, or package-manager commands
- implement any part of the plan
- write any local file other than `$GH_CLAUDE_SESSION_DIR/drafts/issue_plan_draft.md`

Creating `$GH_CLAUDE_SESSION_DIR/drafts/` is allowed only as needed to save that draft file.

## Issue context

!`gh issue view "$GH_ISSUE_NUMBER" --json number,title,url,body,labels,comments 2>/dev/null | jq -r -f "$CLAUDE_PLUGIN_ROOT/queries/gh_issue_view.jq" || echo "Unable to fetch issue. Check the issue number and gh auth status."`

## Focus

!`echo "$ARGUMENTS"`

If no focus is provided, plan the full implementation.

## Workflow

1. Inspect the working tree by running:
   - `git status --short`
   - `git diff --stat HEAD`
2. If local changes are present, include this note at the top of the draft:
   > **Note:** Local changes were detected in your working tree that may relate to this issue.
   > This plan reflects the issue as described — not the current working-tree state.
3. Draft the plan using the format below.
4. Show the draft clearly, framed with horizontal rules.
5. Ask: `Does this look right, or would you like to change something?`
6. If the user requests changes, revise and return to step 4.
7. If the user approves the draft, ask: `Post this plan as a comment?`
8. If the user confirms posting, save the draft by running:
   - `mkdir -p "$GH_CLAUDE_SESSION_DIR/drafts"`
   - write the plan to `"$GH_CLAUDE_SESSION_DIR/drafts/issue_plan_draft.md"`
   - append this marker at the end: `<!-- gh-claude:issue-plan issue=$GH_ISSUE_NUMBER -->`
9. Resolve the repo by running:
   - `REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"`
10. Find an existing plan comment by running:

- `COMMENT_ID="$(gh api "repos/$REPO/issues/$GH_ISSUE_NUMBER/comments" --paginate | jq -s --arg n "$GH_ISSUE_NUMBER" '[.[][] | select(.body | contains("<!-- gh-claude:issue-plan issue=\($n) -->"))] | last | .id // empty')"`

11. Update the existing comment if a comment ID was found:

- `jq -Rs '{body: .}' "$GH_CLAUDE_SESSION_DIR/drafts/issue_plan_draft.md" | gh api "repos/$REPO/issues/comments/$COMMENT_ID" -X PATCH --input - --jq .html_url`

12. Otherwise create a new comment:

- `gh issue comment "$GH_ISSUE_NUMBER" --body-file "$GH_CLAUDE_SESSION_DIR/drafts/issue_plan_draft.md"`

13. Confirm success with the returned URL, and say whether the plan comment was created or updated.

## Error handling

- If the issue fetch fails, stop and ask the user to verify the issue number and run `gh auth status`.
- If posting or updating fails, stop, show the full error output, and suggest running `gh auth status`.

## Rules

- Always keep the tracking marker at the end of the posted comment.

## Draft format

---

**Draft implementation plan for issue #$GH_ISSUE_NUMBER:**

## Summary

{1-2 sentence description of the proposed approach}

## Plan

- T001 — {step}
- T002 — {step}

## Open Questions

- {question}

---

_Omit the Open Questions section if there are none._

_Does this look right, or would you like to change something?_
