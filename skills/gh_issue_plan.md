---
name: gh:issue:plan
description: >
  Drafts an implementation plan for a GitHub issue and posts it as a comment
  after user confirmation. The plan is a proposal for discussion, not an
  execution trigger. Use when the user wants to plan how to implement or solve
  an issue — "plan issue #N", "create an implementation plan", "what steps do I
  need to implement #N?", "break down this issue into tasks", or asks for a
  TODO list or task checklist for an issue.
argument-hint: <issue-number> [focus area]
disable-model-invocation: true
allowed-tools: Bash(gh *), Write
---

Draft an implementation plan for a GitHub issue, then post it as a comment after confirmation.
The plan is a proposal for discussion — this command does not execute the plan.

## Issue context

!`gh issue view $ARGUMENTS[0] --json number,title,url,body,labels,comments 2>/dev/null | jq -r -f queries/gh_issue_view.jq || echo "Unable to fetch issue. Check the issue number and gh auth status."`

## Additional context

!`cat ".github/sessions/issue-$ARGUMENTS[0]/issue_context.md" 2>/dev/null || true`

## Focus

!`echo "$ARGUMENTS" | cut -d' ' -f2-`

(If the focus is empty, plan the full implementation.)

## Workflow

1. Think step by step: understand requirements, identify affected components, break into tasks.
2. Write the implementation plan draft.
3. Show the draft to the user clearly marked as a draft.
4. Ask the user: "Post this plan as a comment, or tell me what to change?"
5. If the user requests changes, revise and repeat from step 3.
6. When the user confirms, append `<!-- gh-ai:issue-plan issue=N -->` (with the actual issue number)
   as the last line of the plan body and write it to `.github/sessions/issue-$ARGUMENTS[0]/issue_plan_draft.md`.
7. Resolve the repository name: `gh repo view --json nameWithOwner --jq .nameWithOwner`
8. Check if a plan comment already exists on the issue (use `--paginate` to search all comments).
   The marker to search for is `<!-- gh-ai:issue-plan issue=N -->` with the actual issue number.
   `gh api repos/<owner>/<repo>/issues/<N>/comments --paginate | jq -s '[.[][] | select(.body | contains("<!-- gh-ai:issue-plan issue=<N> -->"))] | last | .id'`
   - If a comment ID is returned: update it:
     `gh api repos/<owner>/<repo>/issues/comments/<ID> -X PATCH -F body=@.github/sessions/issue-$ARGUMENTS[0]/issue_plan_draft.md`
   - If no comment is found: create a new one:
     `gh issue comment $ARGUMENTS[0] --body-file .github/sessions/issue-$ARGUMENTS[0]/issue_plan_draft.md`
9. Confirm success with the URL of the posted or updated comment.

## Rules

- This is a draft plan for discussion, not an execution trigger. Do not attempt to implement the plan.
- Focus on concrete engineering tasks rather than vague descriptions.
- Use sequential step IDs (T001, T002...) for implementation steps.
- If the issue lacks sufficient detail, highlight the missing information.
- If a focus area is provided, scope the plan to that area only.

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

<!-- gh-ai:issue-plan issue={N} -->

---

_Post this plan as a comment, or tell me what to change._
