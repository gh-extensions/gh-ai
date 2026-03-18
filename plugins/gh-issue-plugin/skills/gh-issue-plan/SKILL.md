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

Draft an implementation plan for a GitHub issue, then post or update it as a comment after confirmation.

## Mode

You are in PLAN-ONLY mode.

Your job is limited to:

1. understanding the issue
2. drafting an implementation plan
3. revising it based on user feedback
4. posting or updating the plan comment after explicit confirmation

User confirmation in this skill only authorizes posting/updating the plan comment.
It never authorizes implementation.

## Forbidden actions

Do not:

- edit source files or configuration
- create branches, commit, push, or open PRs
- run build, test, formatter, linter, or package-manager commands
- implement any part of the plan

The only local file you may write is:
`$GH_CLAUDE_SESSION_DIR/drafts/issue_plan_draft.md`

## Issue context

!`gh issue view "$GH_ISSUE_NUMBER" --json number,title,url,body,labels,comments 2>/dev/null | jq -r -f "$CLAUDE_PLUGIN_ROOT/queries/gh_issue_view.jq" || echo "Unable to fetch issue. Check the issue number and gh auth status."`

## Focus

!`echo "$ARGUMENTS"`

If no focus is provided, plan the full implementation.

## Workflow

1. Inspect the working tree with:
   - `git status --short`
   - `git diff --stat HEAD`
2. If local changes are present, include this note at the top of the draft:
   > **Note:** Local changes were detected in your working tree that may relate to this issue.
   > This plan reflects the issue as described — not the current working-tree state. Post it, or tell me what to change.
3. Draft the plan.
4. Show it clearly as a draft.
5. Ask: **Post this plan as a comment, or tell me what to change?**
6. If the user requests changes, revise and repeat step 4.
7. If the user confirms:
   - run `mkdir -p "$GH_CLAUDE_SESSION_DIR/drafts"`
   - write the plan to:
     `"$GH_CLAUDE_SESSION_DIR/drafts/issue_plan_draft.md"`
   - append this marker at the end:
     `<!-- gh-claude:issue-plan issue=$GH_ISSUE_NUMBER -->`
8. Resolve the repo:
   - `REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"`
9. Find an existing plan comment:
   - `gh api "repos/$REPO/issues/$GH_ISSUE_NUMBER/comments" --paginate | jq -s --arg n "$GH_ISSUE_NUMBER" '[.[][] | select(.body | contains("<!-- gh-claude:issue-plan issue=\($n) -->"))] | last | .id // empty'`
10. If a comment ID exists, update it:
    - `jq -Rs '{body: .}' "$GH_CLAUDE_SESSION_DIR/drafts/issue_plan_draft.md" | gh api "repos/$REPO/issues/comments/$COMMENT_ID" -X PATCH --input - --jq .html_url`
11. Otherwise create a new comment:
    - `gh issue comment "$GH_ISSUE_NUMBER" --body-file "$GH_CLAUDE_SESSION_DIR/drafts/issue_plan_draft.md"`
12. Confirm success with the returned URL, and say whether the plan comment was created or updated.

## Rules

- This skill is for planning only, never implementation.
- Use concrete engineering tasks, not vague descriptions.
- Use sequential IDs: `T001`, `T002`, `T003`, ...
- If the issue lacks detail, call out what is missing.
- If a focus area is provided, scope the plan to that area only.
- If issue fetch fails, stop and ask the user to verify the issue number and run `gh auth status`.
- If posting/updating fails, show the full error and suggest `gh auth status`.
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

_Post this plan as a comment, or tell me what to change._
