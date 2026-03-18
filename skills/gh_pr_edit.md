---
name: gh:pr:edit
description: >
  Edits a GitHub pull request title and body according to requested changes,
  then applies the edit after user confirmation. Use when the user wants to
  update, modify, improve, or rewrite a PR — for example "edit PR #N to add
  a testing section", "update the PR body", "rewrite the description",
  "fix the PR title", "add a summary", "update the PR checklist",
  "add merge instructions", or "improve this pull request".
argument-hint: <pr-number> [what to change]
disable-model-invocation: true
allowed-tools: Bash(gh *), Write
---

Edit a GitHub pull request according to the requested changes, then apply it after confirmation.

## PR context

!`gh pr view $ARGUMENTS[0] --json number,title,url,body,labels,comments,isDraft,state,reviewDecision,reviews,commits 2>/dev/null | jq -r -f queries/gh_pr_view.jq || echo "Unable to fetch PR. Check the PR number and gh auth status."`

## Additional context

!`cat ".github/sessions/pull-$ARGUMENTS[0]/pr_context.md" 2>/dev/null || true`

## Requested changes

!`echo "$ARGUMENTS" | cut -d' ' -f2-`

(If no changes are specified, ask the user what they want to change.)

## Workflow

1. Apply the requested changes to produce an updated title and body.
2. Show the full updated PR to the user clearly marked as a draft.
3. Ask the user: "Apply this edit, or tell me what to change?"
4. If the user requests changes, revise and repeat from step 2.
5. When the user confirms:
   - Ensure the session directory exists: `mkdir -p .github/sessions/pull-$ARGUMENTS[0]`
   - Extract the title from the draft (the first `# ...` line, without the `# ` prefix)
   - Write ONLY the body (everything after the title line) to `.github/sessions/pull-$ARGUMENTS[0]/pr_body_draft.md` — do NOT include the `# Title` line in the file
   - Run: `gh pr edit $ARGUMENTS[0] --title "<extracted title>" --body-file .github/sessions/pull-$ARGUMENTS[0]/pr_body_draft.md`
6. Confirm success with the PR URL.

## Rules

- Apply only the requested changes.
- Preserve existing wording and structure unless the request explicitly requires modification.
- If the requested change is ambiguous, identify what clarification is needed.

## Draft format

ALWAYS present the draft clearly so the user can read it before confirming:

---

**Draft edit for PR #N:**

# {title under 72 chars}

{updated PR body in GitHub-flavored Markdown}

---

_Apply this edit, or tell me what to change._
