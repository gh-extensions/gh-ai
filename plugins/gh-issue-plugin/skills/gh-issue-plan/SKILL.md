---
name: gh:issue:plan
description: >
  Drafts an implementation plan for a GitHub issue and posts it as a comment
  after user confirmation. The plan is a proposal for discussion, not an
  execution trigger. Use when the user wants to plan how to implement or solve
  an issue — "plan issue #N", "create an implementation plan", "what steps do I
  need to implement #N?", "break down this issue into tasks", or asks for a
  TODO list or task checklist for an issue.
argument-hint: [focus area]
disable-model-invocation: true
allowed-tools: Bash(*), Write
---

Draft an implementation plan for a GitHub issue, then post it as a comment after confirmation.
The plan is a proposal for discussion — this command does not execute the plan.

## Issue context

!`gh issue view ${GH_ISSUE_NUMBER} --json number,title,url,body,labels,comments 2>/dev/null | jq -r -f ${CLAUDE_PLUGIN_ROOT}/queries/gh_issue_view.jq || echo "Unable to fetch issue. Check the issue number and gh auth status."`

## Additional context

!`cat "${GH_CLAUDE_SESSION_DIR}/state/issue_context.md" 2>/dev/null || true`

## Focus

!`echo "$ARGUMENTS"`

(If the focus is empty, plan the full implementation.)

## Workflow

1. Check for existing work: run `git status --short` and `git diff --stat HEAD`. If uncommitted or
   staged changes are present, note this at the top of the plan draft using the warning format below.
   Do not block — continue normally and let the user decide.
2. Think step by step: understand requirements, identify affected components, break into tasks.
3. Write the implementation plan draft.
4. Show the draft to the user clearly marked as a draft.
5. Ask the user: "Post this plan as a comment, or tell me what to change?"
6. If the user requests changes, revise and repeat from step 4.
7. When the user confirms, run `mkdir -p ${GH_CLAUDE_SESSION_DIR}/drafts`, write the plan body to
   `${GH_CLAUDE_SESSION_DIR}/drafts/issue_plan_draft.md`, then append the tracking marker with the actual issue number:
   `printf '\n<!-- gh-claude:issue-plan issue=%s -->' "${GH_ISSUE_NUMBER}" >> ${GH_CLAUDE_SESSION_DIR}/drafts/issue_plan_draft.md`
8. Resolve the repository name: `gh repo view --json nameWithOwner --jq .nameWithOwner`
9. Check if a plan comment already exists on the issue (use `--paginate` to search all comments).
   The marker to search for is `<!-- gh-claude:issue-plan issue=N -->` with the actual issue number.
   `gh api repos/{owner}/{repo}/issues/${GH_ISSUE_NUMBER}/comments --paginate | jq -s --arg n "${GH_ISSUE_NUMBER}" '[.[][] | select(.body | contains("<!-- gh-claude:issue-plan issue=\($n) -->"))] | last | .id // empty'`
   - If a comment ID is returned: update it and confirm success with the returned URL:
     `jq -Rs '{body: .}' ${GH_CLAUDE_SESSION_DIR}/drafts/issue_plan_draft.md | gh api repos/{owner}/{repo}/issues/comments/{ID} -X PATCH --input - --jq .html_url`
   - If no comment is found: create a new one:
     `gh issue comment ${GH_ISSUE_NUMBER} --body-file ${GH_CLAUDE_SESSION_DIR}/drafts/issue_plan_draft.md`
10. Confirm success with the URL of the posted or updated comment.

## Rules

- This is a draft plan for discussion, not an execution trigger. Do not attempt to implement the plan.
- If uncommitted or staged local changes are detected in step 1, prepend this notice to the draft (do not block or skip the plan):
  > **Note:** Local changes were detected in your working tree that may relate to this issue.
  > This plan reflects the issue as described — not the current working-tree state. Post it, or tell me what to change.
- Focus on concrete engineering tasks rather than vague descriptions.
- Use sequential step IDs (T001, T002...) for implementation steps.
- If the issue lacks sufficient detail, highlight the missing information.
- If a focus area is provided, scope the plan to that area only.
- If the issue context shows "Unable to fetch...", stop and ask the user to verify the issue number and run `gh auth status`.
- If the final `gh` command fails, show the full error and suggest running `gh auth status`.

## Draft format

ALWAYS present the draft clearly so the user can read it before confirming:

---

**Draft implementation plan for issue #N:**

## Summary
{1-2 sentence description of the proposed approach}

## Plan
- T001 — {step}
- T002 — {step}

## Open Questions
- {anything that needs clarification before implementation; omit this section if there are none}

---

_Post this plan as a comment, or tell me what to change._
