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

!`gh issue view $GH_AI_ISSUE_NUMBER --json number,title,url,body,labels,comments 2>/dev/null | jq -r -f $CLAUDE_PLUGIN_ROOT/queries/gh_issue_view.jq || echo "Unable to fetch issue. Check the issue number and gh auth status."`

## Additional context

!`cat "$GH_AI_SESSION_DIR/state/issue_context.md" 2>/dev/null || true`

## Focus

!`echo "$ARGUMENTS"`

(If the focus is empty, plan the full implementation.)

## Workflow

1. Think step by step: understand requirements, identify affected components, break into tasks.
2. Write the implementation plan draft.
3. Show the draft to the user clearly marked as a draft.
4. Ask the user: "Post this plan as a comment, or tell me what to change?"
5. If the user requests changes, revise and repeat from step 3.
6. When the user confirms, run `mkdir -p $GH_AI_SESSION_DIR/drafts`, write the plan body to
   `$GH_AI_SESSION_DIR/drafts/issue_plan_draft.md`, then append the tracking marker with the actual issue number:
   `printf '\n<!-- gh-ai:issue-plan issue=%s -->' "$GH_AI_ISSUE_NUMBER" >> $GH_AI_SESSION_DIR/drafts/issue_plan_draft.md`
7. Resolve the repository name: `gh repo view --json nameWithOwner --jq .nameWithOwner`
8. Check if a plan comment already exists on the issue (use `--paginate` to search all comments).
   The marker to search for is `<!-- gh-ai:issue-plan issue=N -->` with the actual issue number.
   `gh api repos/{owner}/{repo}/issues/$GH_AI_ISSUE_NUMBER/comments --paginate | jq -s --arg n "$GH_AI_ISSUE_NUMBER" '[.[][] | select(.body | contains("<!-- gh-ai:issue-plan issue=\($n) -->"))] | last | .id // empty'`
   - If a comment ID is returned: update it and confirm success with the returned URL:
     `jq -Rs '{body: .}' $GH_AI_SESSION_DIR/drafts/issue_plan_draft.md | gh api repos/{owner}/{repo}/issues/comments/{ID} -X PATCH --input - --jq .html_url`
   - If no comment is found: create a new one:
     `gh issue comment $GH_AI_ISSUE_NUMBER --body-file $GH_AI_SESSION_DIR/drafts/issue_plan_draft.md`
9. Confirm success with the URL of the posted or updated comment.

## Rules

- This is a draft plan for discussion, not an execution trigger. Do not attempt to implement the plan.
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
