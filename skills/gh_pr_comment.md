---
name: gh:pr:comment
description: >
  Drafts a GitHub pull request comment and posts it after user confirmation. Use
  when the user wants to write, draft, or post a comment on a GitHub pull
  request, or needs help wording a reply. Trigger when the user says "write a
  comment on PR #N", "draft a response to this PR", "add a comment saying...",
  "reply to this pull request", "respond to a review on PR #N", or invokes the
  command directly while working on a PR.
argument-hint: <pr-number> [what to say]
disable-model-invocation: true
allowed-tools: Bash(gh *), Write
---

Draft a GitHub pull request comment, then post it after the user confirms.

## PR context

!`gh pr view $ARGUMENTS[0] --json number,title,url,body,labels,comments,isDraft,state,reviewDecision,reviews,commits 2>/dev/null | jq -r -f queries/gh_pr_view.jq || echo "Unable to fetch PR. Check the PR number and gh auth status."`

## Additional context

!`cat ".github/sessions/pull-$ARGUMENTS[0]/pr_context.md" 2>/dev/null || true`

## Request

!`echo "$ARGUMENTS" | cut -d' ' -f2-`

(If the request is empty, infer the most helpful comment from the PR context.)

## Workflow

1. Write the comment draft based on the PR context and the request above.
2. Show the draft to the user clearly marked as a draft.
3. Ask the user: "Post this comment, or tell me what to change?"
4. If the user requests changes, revise and repeat from step 2.
5. When the user confirms, ensure the session directory exists (`mkdir -p .github/sessions/pull-$ARGUMENTS[0]`),
   write the final comment to `.github/sessions/pull-$ARGUMENTS[0]/pr_comment_draft.md`, and run:
   `gh pr comment $ARGUMENTS[0] --body-file .github/sessions/pull-$ARGUMENTS[0]/pr_comment_draft.md`
6. Confirm the action was successful with the URL of the posted comment.

## Rules

- Keep the tone concise, natural, and appropriate for a GitHub discussion.
- Prefer concrete references to PR details when possible.
- If information required to fulfill the request is missing, say so rather than guessing.

## Draft format

ALWAYS present the draft clearly so the user can read it before confirming:

---

**Draft comment for PR #N:**

{comment body in GitHub-flavored Markdown}

---

_Post this comment, or tell me what to change._
