---
name: gh:issue:comment
description: >
  Drafts a GitHub issue comment and posts it after user confirmation. Use when
  the user wants to write, draft, or post a comment on a GitHub issue, or needs
  help wording a reply. Trigger when the user says "write a comment on issue #N",
  "draft a response to this issue", "add a comment saying...", "reply to this
  issue", or invokes the command directly while working on an issue.
argument-hint: [what to say]
disable-model-invocation: true
allowed-tools: Bash(*), Write
---

Draft a GitHub issue comment, then post it after the user confirms.

## Issue context

!`gh issue view ${GH_ISSUE_NUMBER} --json number,title,url,body,labels,comments 2>/dev/null | jq -r -f ${CLAUDE_PLUGIN_ROOT}/queries/gh_issue_view.jq || echo "Unable to fetch issue. Check the issue number and gh auth status."`

## Additional context

!`cat "${GH_CLAUDE_SESSION_DIR}/state/issue_context.md" 2>/dev/null || true`

## Request

!`echo "$ARGUMENTS"`

(If the request is empty, infer the most helpful comment from the issue context.)

## Workflow

1. Write the comment draft based on the issue context and the request above.
2. Show the draft to the user clearly marked as a draft.
3. Ask the user: "Post this comment, or tell me what to change?"
4. If the user requests changes, revise and repeat from step 2.
5. When the user confirms:
   - Ensure the drafts directory exists: `mkdir -p ${GH_CLAUDE_SESSION_DIR}/drafts`
   - Write the final comment to `${GH_CLAUDE_SESSION_DIR}/drafts/issue_comment_draft.md`
   - Run: `gh issue comment ${GH_ISSUE_NUMBER} --body-file ${GH_CLAUDE_SESSION_DIR}/drafts/issue_comment_draft.md`
6. Confirm the action was successful with the URL of the posted comment.

## Rules

- Keep the tone concise, natural, and appropriate for a GitHub discussion.
- Prefer concrete references to issue details when possible.
- If information required to fulfill the request is missing, say so rather than guessing.
- If the issue context shows "Unable to fetch...", stop and ask the user to verify the issue number and run `gh auth status`.
- If the `gh issue comment` command fails, show the full error and suggest running `gh auth status`.

## Draft format

ALWAYS present the draft clearly so the user can read it before confirming:

---

**Draft comment for issue #N:**

{comment body in GitHub-flavored Markdown}

---

_Post this comment, or tell me what to change._
