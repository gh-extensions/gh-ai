---
name: gh:issue:comment
description: >
  Drafts a GitHub issue comment and posts it after user confirmation. Trigger
  when the user says "write a comment on issue #N", "draft a response to this
  issue", "add a comment saying...", "reply to this issue", or invokes the
  command directly while working on an issue.
argument-hint: [what to say]
disable-model-invocation: true
allowed-tools: Bash(*), Write
---

Draft a GitHub issue comment, then post it after the user confirms.

## Context

!`gh issue view ${GH_ISSUE_NUMBER} --json number,title,url,body,labels,comments 2>/dev/null | jq -r -f ${CLAUDE_PLUGIN_ROOT}/queries/gh_issue_view.jq || echo "Unable to fetch issue. Check the issue number and gh auth status."`

!`cat "${GH_CLAUDE_SESSION_DIR}/state/issue_context.md" 2>/dev/null || true`

## Arguments

!`echo "$ARGUMENTS"`

(If empty, infer the most helpful comment from the issue context.)

## Workflow

1. Write the comment draft.
2. Show the draft framed with horizontal rules.
3. Ask: `Post this comment, or tell me what to change?`
4. If the user requests changes, revise and return to step 2.
5. When the user confirms, save and post:
   - `mkdir -p ${GH_CLAUDE_SESSION_DIR}/drafts`
   - Write to `${GH_CLAUDE_SESSION_DIR}/drafts/issue_comment_draft.md`
   - `gh issue comment ${GH_ISSUE_NUMBER} --body-file ${GH_CLAUDE_SESSION_DIR}/drafts/issue_comment_draft.md`
6. Confirm success with the posted comment URL.

## Rules

- Concise, natural tone appropriate for GitHub.
- Prefer concrete references to issue details.
- If required info is missing, say so rather than guessing.
- If issue fetch fails, stop and ask the user to verify the number and run `gh auth status`.
- If `gh issue comment` fails, show the full error and suggest `gh auth status`.

## Draft format

---

**Draft comment for issue #N:**

{comment body in GitHub-flavored Markdown}

_Post this comment, or tell me what to change?_

---
