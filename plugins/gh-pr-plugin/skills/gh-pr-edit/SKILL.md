---
name: gh:pr:edit
description: >
  Edits a GitHub pull request title and body according to requested changes,
  then applies the edit after user confirmation. Use when the user wants to
  update, modify, improve, or rewrite a PR — for example "edit PR #N to add
  a testing section", "update the PR body", "rewrite the description",
  "fix the PR title", "add a summary", "update the PR checklist",
  "add merge instructions", or "improve this pull request".
argument-hint: [what to change]
disable-model-invocation: true
allowed-tools: Bash(*), Write
---

Edit a GitHub pull request according to the requested changes, then apply it after confirmation.

## PR context

!`gh pr view ${GH_PR_NUMBER} --json number,title,url,body,labels,comments,isDraft,state,reviewDecision,reviews,commits 2>/dev/null | jq -r -f ${CLAUDE_PLUGIN_ROOT}/queries/gh_pr_view.jq || echo "Unable to fetch PR. Check the PR number and gh auth status."`

## Additional context

!`cat "${GH_CLAUDE_SESSION_DIR}/state/pr_context.md" 2>/dev/null || true`

## Requested changes

!`echo "$ARGUMENTS"`

(If no changes are specified, ask the user what they want to change.)

## Workflow

1. Apply the requested changes to produce an updated title and body.
2. Show the full updated PR to the user clearly marked as a draft.
3. Ask the user: "Apply this edit, or tell me what to change?"
4. If the user requests changes, revise and repeat from step 2.
5. When the user confirms:
   - Ensure the drafts directory exists: `mkdir -p ${GH_CLAUDE_SESSION_DIR}/drafts`
   - Extract the title from the draft (the first `# ...` line, without the `# ` prefix)
   - Write the extracted title (without the `# ` prefix) to `${GH_CLAUDE_SESSION_DIR}/drafts/pr_title_draft.txt`
   - Write ONLY the body (everything after the title line) to `${GH_CLAUDE_SESSION_DIR}/drafts/pr_body_draft.md` — do NOT include the `# Title` line in the file
   - Run: `gh pr edit ${GH_PR_NUMBER} --title "$(cat ${GH_CLAUDE_SESSION_DIR}/drafts/pr_title_draft.txt | tr -d '\n')" --body-file ${GH_CLAUDE_SESSION_DIR}/drafts/pr_body_draft.md`
6. Confirm success with the PR URL.

## Rules

- Apply only the requested changes.
- Preserve existing wording and structure unless the request explicitly requires modification.
- If the requested change is ambiguous, identify what clarification is needed.
- Keep the title under 72 characters.
- If the PR context shows "Unable to fetch...", stop and ask the user to verify the PR number and run `gh auth status`.
- If the `gh pr edit` command fails, show the full error and suggest running `gh auth status`.

## Draft format

ALWAYS present the draft clearly so the user can read it before confirming:

---

**Draft edit for PR #N:**

# {title under 72 chars}

{updated PR body in GitHub-flavored Markdown}

---

_Apply this edit, or tell me what to change._
