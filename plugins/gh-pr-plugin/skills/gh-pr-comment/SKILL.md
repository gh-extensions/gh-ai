---
name: gh:pr:comment
description: >
  Drafts a GitHub pull request comment and posts it after user confirmation.
  Trigger when the user says "write a comment on PR #N", "draft a response to
  this PR", "add a comment saying...", "reply to this pull request", "respond
  to a review on PR #N", or invokes the command directly while working on a PR.
argument-hint: [what to say]
disable-model-invocation: true
allowed-tools: Bash(*), Write
---

Draft a GitHub pull request comment, then post it after the user confirms.

## Context

!`gh pr view ${GH_PR_NUMBER} --json number,title,url,body,labels,comments,isDraft,state,reviewDecision,reviews,commits 2>/dev/null | jq -r -f ${CLAUDE_PLUGIN_ROOT}/queries/gh_pr_view.jq || echo "Unable to fetch PR. Check the PR number and gh auth status."`

!`cat "${GH_CLAUDE_SESSION_DIR}/state/pr_context.md" 2>/dev/null || true`

## Arguments

!`echo "$ARGUMENTS"`

(If empty, infer the most helpful comment from the PR context.)

## Workflow

1. Write the comment draft.
2. Show the draft framed with horizontal rules.
3. Ask: `Post this comment, or tell me what to change?`
4. If the user requests changes, revise and return to step 2.
5. When the user confirms, save and post:
   - `mkdir -p ${GH_CLAUDE_SESSION_DIR}/drafts`
   - Write to `${GH_CLAUDE_SESSION_DIR}/drafts/pr_comment_draft.md`
   - `gh pr comment ${GH_PR_NUMBER} --body-file ${GH_CLAUDE_SESSION_DIR}/drafts/pr_comment_draft.md`
6. Confirm success with the posted comment URL.

## Rules

- Concise, natural tone appropriate for GitHub.
- Prefer concrete references to PR details.
- If required info is missing, say so rather than guessing.
- If PR fetch fails, stop and ask the user to verify the number and run `gh auth status`.
- If `gh pr comment` fails, show the full error and suggest `gh auth status`.

## Draft format

---

**Draft comment for PR #N:**

{comment body in GitHub-flavored Markdown}

_Post this comment, or tell me what to change?_

---
