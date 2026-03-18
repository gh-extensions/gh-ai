---
name: gh:issue:plan
description: >
  Drafts an implementation plan for the current GitHub issue and posts it as a
  comment after user confirmation. Trigger when the user says "plan this issue",
  "create an implementation plan", "break down this issue into tasks", "draft
  a plan for #N", or "what steps do I need to implement this?". The plan is
  for discussion only and never triggers implementation.
argument-hint: [focus area]
disable-model-invocation: true
allowed-tools: Bash(*), Write
---

Draft an implementation plan for a GitHub issue, then post or update it as a comment after confirmation.

## Mode: PLAN-ONLY

Your job: understand the issue → draft a plan → revise → post. Nothing else.

**Confirming means: post or update the plan comment. It never means: implement anything.**

## Context

!`gh issue view ${GH_ISSUE_NUMBER} --json number,title,url,body,labels,comments 2>/dev/null | jq -r -f ${CLAUDE_PLUGIN_ROOT}/queries/gh_issue_view.jq || echo "Unable to fetch issue. Check the issue number and gh auth status."`

## Arguments

!`echo "$ARGUMENTS"`

(If empty, plan the full implementation.)

## Workflow

1. Inspect the working tree:
   - `git status --short`
   - `git diff --stat HEAD`
   (If git unavailable, skip to step 3.)
2. If local changes present, include at the top of the draft:
   > **Note:** Local changes detected. This plan reflects the issue as described, not the working-tree state.
3. Draft the plan using the format below.
4. Show the draft framed with horizontal rules.
5. Ask: `Post this plan as a comment, or tell me what to change?`
6. If the user requests changes, revise and return to step 4.
7. When the user confirms, save the draft:
   - `mkdir -p ${GH_CLAUDE_SESSION_DIR}/drafts`
   - Write to `${GH_CLAUDE_SESSION_DIR}/drafts/issue_plan_draft.md`
   - Append marker: `<!-- gh-claude:issue-plan issue=${GH_ISSUE_NUMBER} -->`
8. Resolve repo: `REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"`
9. Find existing plan comment:
   - `COMMENT_ID="$(gh api "repos/${REPO}/issues/${GH_ISSUE_NUMBER}/comments" --paginate | jq -s --arg n "${GH_ISSUE_NUMBER}" '[.[][] | select(.body | contains("<!-- gh-claude:issue-plan issue=\($n) -->"))] | last | .id // empty')"`
10. Post or update:
    - If `COMMENT_ID` non-empty: `jq -Rs '{body: .}' ${GH_CLAUDE_SESSION_DIR}/drafts/issue_plan_draft.md | gh api "repos/${REPO}/issues/comments/${COMMENT_ID}" -X PATCH --input - --jq .html_url`
    - Otherwise: `gh issue comment ${GH_ISSUE_NUMBER} --body-file ${GH_CLAUDE_SESSION_DIR}/drafts/issue_plan_draft.md`
11. Confirm success with URL; say whether created or updated.

## Rules

- Write as if the implementer has little context. Plain English, concrete tasks.
- Label tasks sequentially: `T001`, `T002`, `T003`, ...
- Call out likely affected files, modules, or systems.
- If the issue is too broad, recommend splitting. Wait for the user to decide.
- Use Open Questions for anything that needs clarification.
- Do not: edit source files, create branches, commit, push, run builds/tests, or implement the plan.
- Only writable file: `${GH_CLAUDE_SESSION_DIR}/drafts/issue_plan_draft.md`
- Always keep the tracking marker at the end of the posted comment.
- If issue fetch fails, stop and ask the user to verify the number and run `gh auth status`.
- If comment-list API fails in step 9, stop and show the full error.
- If posting/updating fails, show the error and suggest `gh auth status`.

## Draft format

---

**Draft implementation plan for issue #N:**

## Summary
{1-2 sentence approach}

## Likely Affected Areas
- `{path or subsystem}` — {why}

## Tasks
- T001 — {task}
- T002 — {task}

## Open Questions
- {question}

_Post this plan as a comment, or tell me what to change?_

---

_Omit Open Questions if none. Omit Likely Affected Areas if insufficient context._
