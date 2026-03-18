---
name: gh:issue:edit
description: >
  Edits a GitHub issue title and body according to requested changes, then
  applies the edit after user confirmation. Trigger when the user says "edit
  issue #N to add acceptance criteria", "update the issue body", "rewrite the
  description", "fix the issue title", "add a definition of done", or
  "improve this issue".
argument-hint: [what to change]
disable-model-invocation: true
allowed-tools: Bash(*), Write
---

Edit a GitHub issue according to the requested changes, then apply it after confirmation.

## Context

!`gh issue view ${GH_ISSUE_NUMBER} --json number,title,url,body,labels,comments 2>/dev/null | jq -r -f ${CLAUDE_PLUGIN_ROOT}/queries/gh_issue_view.jq || echo "Unable to fetch issue. Check the issue number and gh auth status."`

!`cat "${GH_CLAUDE_SESSION_DIR}/state/issue_context.md" 2>/dev/null || true`

## Arguments

!`echo "$ARGUMENTS"`

(If empty, ask the user what they want to change.)

## Workflow

1. Apply the requested changes to produce an updated title and body.
2. Show the full updated issue framed with horizontal rules.
3. Ask: `Apply this edit, or tell me what to change?`
4. If the user requests changes, revise and return to step 2.
5. When the user confirms, save and apply:
   - `mkdir -p ${GH_CLAUDE_SESSION_DIR}/drafts`
   - Extract the title (first `# ...` line, without the `# ` prefix) → `${GH_CLAUDE_SESSION_DIR}/drafts/issue_title_draft.txt`
   - Write ONLY the body (everything after the title line) → `${GH_CLAUDE_SESSION_DIR}/drafts/issue_body_draft.md` — do NOT include the `# Title` line
   - `gh issue edit ${GH_ISSUE_NUMBER} --title "$(cat ${GH_CLAUDE_SESSION_DIR}/drafts/issue_title_draft.txt | tr -d '\n')" --body-file ${GH_CLAUDE_SESSION_DIR}/drafts/issue_body_draft.md`
6. Confirm success with the issue URL.

## Rules

- Apply only the requested changes.
- Preserve existing wording and structure unless the request explicitly requires modification.
- If the requested change is ambiguous, identify what clarification is needed.
- Keep the title under 72 characters.
- If issue fetch fails, stop and ask the user to verify the number and run `gh auth status`.
- If `gh issue edit` fails, show the full error and suggest `gh auth status`.

## Draft format

---

**Draft edit for issue #N:**

# {title under 72 chars}

{updated issue body in GitHub-flavored Markdown}

_Apply this edit, or tell me what to change?_

---
