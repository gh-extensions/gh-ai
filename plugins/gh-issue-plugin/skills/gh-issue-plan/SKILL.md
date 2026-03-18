---
name: gh:issue:plan
description: >
  Drafts an implementation plan for the current GitHub issue and posts it as a
  comment after explicit user confirmation. Use when the user wants a concrete
  implementation approach, task breakdown, TODO list, phased plan, or scoped
  plan for part of an issue. Trigger when the user says "plan this issue",
  "create an implementation plan", "break down this issue into tasks", "draft
  a plan for #N", "what steps do I need to implement this?", or invokes the
  command with a focus area. The plan is for discussion only and never
  triggers implementation.
argument-hint: [focus area]
disable-model-invocation: true
allowed-tools: Bash(*), Write
---

You are helping the user think through how to implement a GitHub issue. Read the issue,
draft a concrete implementation plan, revise it based on feedback, and post or update it
as a comment only after explicit confirmation.

## Mode: PLAN-ONLY

Your job is limited to:

1. understanding the issue
2. drafting an implementation plan
3. revising it based on user feedback
4. posting or updating the plan comment after explicit confirmation

**Confirming means: post or update the plan comment. It never means: implement anything.**

## Planning style

Write the plan as if the future implementer has little context about this issue.

- Write in plain English, like you are talking to a teammate.
- Prefer concrete engineering tasks over vague descriptions.
- Break work into small, sequential tasks.
- Label every task with a sequential ID: `T001`, `T002`, `T003`, ...
- Call out likely files, modules, components, or systems that may need changes.
- If the issue seems too broad or spans multiple independent areas, say so explicitly and recommend splitting it into smaller plans, then wait for the user to decide how to proceed.
- If a focus area is provided, scope the plan to that area only.
- Use Open Questions for anything that must be clarified before implementation starts.

## Forbidden actions

Do not:

- edit source files or configuration
- create branches, commit, push, or open PRs
- run build, test, formatter, linter, or package-manager commands
- implement any part of the plan
- write any local file other than `${GH_CLAUDE_SESSION_DIR}/drafts/issue_plan_draft.md`

Creating `${GH_CLAUDE_SESSION_DIR}/drafts/` is allowed only as needed to save that draft file.

## Issue context

!`gh issue view ${GH_ISSUE_NUMBER} --json number,title,url,body,labels,comments 2>/dev/null | jq -r -f ${CLAUDE_PLUGIN_ROOT}/queries/gh_issue_view.jq || echo "Unable to fetch issue. Check the issue number and gh auth status."`

## Focus

!`echo "$ARGUMENTS"`

If no focus is provided, plan the full implementation.

## Workflow

1. Inspect the working tree by running:
   - `git status --short`
   - `git diff --stat HEAD`
   (If git is unavailable or the directory is not a repo, skip steps 1–2 and proceed without the working-tree note.)
2. If local changes are present, include this note at the top of the draft:
   > **Note:** Local changes were detected in your working tree that may relate to this issue.
   > This plan reflects the issue as described — not the current working-tree state.
3. Draft the plan using the format below.
4. Show the draft clearly, framed with horizontal rules.
5. Ask: `Post this plan as a comment, or tell me what to change?`
6. If the user requests changes, revise and return to step 4.
7. If the user confirms, save the draft by running:
   - `mkdir -p ${GH_CLAUDE_SESSION_DIR}/drafts`
   - write the plan to `${GH_CLAUDE_SESSION_DIR}/drafts/issue_plan_draft.md`
   - append this marker at the end: `<!-- gh-claude:issue-plan issue=${GH_ISSUE_NUMBER} -->`
8. Resolve the repo by running:
   - `REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"`
9. Find an existing plan comment by running:
   - `COMMENT_ID="$(gh api "repos/${REPO}/issues/${GH_ISSUE_NUMBER}/comments" --paginate | jq -s --arg n "${GH_ISSUE_NUMBER}" '[.[][] | select(.body | contains("<!-- gh-claude:issue-plan issue=\($n) -->"))] | last | .id // empty')"`
   If this command fails, stop and show the full error before continuing.
10. Post or update the comment:
    - If `COMMENT_ID` is non-empty, update the existing comment:
      `jq -Rs '{body: .}' ${GH_CLAUDE_SESSION_DIR}/drafts/issue_plan_draft.md | gh api "repos/${REPO}/issues/comments/${COMMENT_ID}" -X PATCH --input - --jq .html_url`
    - Otherwise, create a new comment:
      `gh issue comment ${GH_ISSUE_NUMBER} --body-file ${GH_CLAUDE_SESSION_DIR}/drafts/issue_plan_draft.md`
11. Confirm success with the returned URL, and say whether the plan comment was created or updated.

## Error handling

- If the issue fetch fails, stop and ask the user to verify the issue number and run `gh auth status`.
- If `git status` fails (not a git repo or git unavailable), skip steps 1–2 and proceed without the working-tree note.
- If the comment-list API call in step 9 fails, stop, show the full error output, and ask the user whether to retry or cancel.
- If posting or updating fails, stop, show the full error output, and suggest running `gh auth status`.

## Rules

- Always keep the tracking marker at the end of the posted comment.
- Do not invent exact file paths or implementation details unless they are clear from the issue context.
- When the exact implementation area is uncertain, name the most likely affected components or systems instead.

## Draft format

---

**Draft implementation plan for issue #N:**

## Summary

{1-2 sentence description of the proposed approach}

## Likely Affected Areas

- `{path, module, component, or subsystem}` — {why it likely matters}
- `{path, module, component, or subsystem}` — {why it likely matters}

## Tasks

- T001 — {small, concrete task}
- T002 — {small, concrete task}
- T003 — {small, concrete task}

## Open Questions

- {question}

---

_Omit the Open Questions section if there are none._
_Omit Likely Affected Areas if the issue does not provide enough information to make a useful guess._

_Post this plan as a comment, or tell me what to change?_
