---
name: gh:issue:edit
description: >
  Edits a GitHub issue title and body according to requested changes, then
  applies the edit after user confirmation. Use when the user wants to update,
  modify, improve, or rewrite an issue — for example "edit issue #N to add
  acceptance criteria", "update the issue body", "rewrite the description",
  "fix the issue title", "add a definition of done", or "improve this issue".
argument-hint: <issue-number> [what to change]
disable-model-invocation: true
allowed-tools: Bash(gh *), Write
---

Edit a GitHub issue according to the requested changes, then apply it after confirmation.

## Issue context

!`gh issue view $ARGUMENTS[0] --json number,title,url,body,labels,comments 2>/dev/null | jq -r -f templates/gh_issue_view.jq || echo "Unable to fetch issue. Check the issue number and gh auth status."`

## Additional context

!`cat ".github/sessions/issue-$ARGUMENTS[0]/issue_context.md" 2>/dev/null || true`

## Requested changes

!`echo "$ARGUMENTS" | cut -d' ' -f2-`

(If no changes are specified, ask the user what they want to change.)

## Workflow

1. Apply the requested changes to produce an updated title and body.
2. Show the full updated issue to the user clearly marked as a draft.
3. Ask the user: "Apply this edit, or tell me what to change?"
4. If the user requests changes, revise and repeat from step 2.
5. When the user confirms:
   - Extract the title from the draft (the first `# ...` line, without the `# ` prefix)
   - Write ONLY the body (everything after the title line) to `.github/sessions/issue-$ARGUMENTS[0]/issue_body_draft.md` — do NOT include the `# Title` line in the file
   - Run: `gh issue edit $ARGUMENTS[0] --title "<extracted title>" --body-file .github/sessions/issue-$ARGUMENTS[0]/issue_body_draft.md`
6. Confirm success with the issue URL.

## Rules

- Apply only the requested changes.
- Preserve existing wording and structure unless the request explicitly requires modification.
- If the requested change is ambiguous, identify what clarification is needed.

## Draft format

ALWAYS present the draft clearly so the user can read it before confirming:

---

**Draft edit for issue #N:**

# {title under 72 chars}

{updated issue body in GitHub-flavored Markdown}

---

_Apply this edit, or tell me what to change._
