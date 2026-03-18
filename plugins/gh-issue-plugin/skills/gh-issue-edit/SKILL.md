---
name: gh:issue:edit
description: >
  Edits a GitHub issue title and/or body according to requested changes, then
  applies the edit after user confirmation. Provide optional argument text
  describing what to change, e.g., "add acceptance criteria" or "fix the title."
argument-hint: "[what to change or edit request]"
version: 1.0.0
disable-model-invocation: true
allowed-tools: Bash(*), Write
---

# Edit GitHub Issues (Title & Body)

## Prerequisites

- `gh` CLI installed and authenticated (`gh auth status` to verify)
- Environment: `$GH_ISSUE_NUMBER` (set or pass explicitly)
- Directories: `$GH_CLAUDE_SESSION_DIR` must be writable
- Write permissions on the repository

## Context

**Current Issue (always fresh):**

```
!`gh issue view ${GH_ISSUE_NUMBER} --json number,title,url,body,state,labels,comments 2>/dev/null | jq -r -f ${CLAUDE_PLUGIN_ROOT}/queries/gh_issue_view.jq || echo "Unable to fetch issue. Check the issue number and gh auth status."`
```

**Session Notes (optional, non-authoritative):**

```
!`cat "${GH_CLAUDE_SESSION_DIR}/state/session_notes.md" 2>/dev/null || true`
```

**User Request:**

```
!`echo "$ARGUMENTS"`
```

## Workflow

### 1. **Validate & Fetch**

- Verify `$GH_ISSUE_NUMBER` is set; if not, ask the user
- Fetch issue details (title, body, metadata); if fetch fails, stop and show the error
- Check user has write permissions to the repo (auth required)

### 2. **Clarify Changes (If Needed)**

- **If arguments provided:** Confirm scope (e.g., "I'll update the title and add acceptance criteria")
- **If empty:** Ask "What would you like to change about this issue?"
- If request is ambiguous, ask for clarification before proceeding

### 3. **Draft the Changes**

- **Apply ONLY the requested modifications**
- Preserve existing wording, structure, and formatting unless explicitly requested
- Keep title under 72 characters (GitHub best practice)
- Use GitHub Markdown for body formatting (code blocks, lists, tables, etc.)
- Format output as:

  ```
  # {new title}

  {updated body}
  ```

### 4. **Present for Review**

```
---
**Draft edit for issue #N:**

# {title under 72 chars}

{updated issue body in GitHub-flavored Markdown}

_Apply this edit, or tell me what to change?_
---
```

### 5. **Handle User Feedback**

- **If user confirms** (`"apply"`, `"yes"`, `"👍"`, `"looks good"`): Proceed to step 6
- **If user requests changes**: Revise and return to step 4
- **If user says cancel** (`"no"`, `"cancel"`, `"discard"`): Stop and don't apply
- **If no response to confirmation**: Ask once more: "Should I apply this edit or discard it?"

### 6. **Extract & Save**

- Create the drafts directory: `mkdir -p ${GH_CLAUDE_SESSION_DIR}/drafts`
- The draft's **first line** is always the title (starting with `# `). Everything after is the body.
- Write the title (without `# ` prefix) to `${GH_CLAUDE_SESSION_DIR}/drafts/issue_title_draft.txt`
- Write the body to `${GH_CLAUDE_SESSION_DIR}/drafts/issue_body_draft.md`

### 7. **Apply the Edit**

```bash
gh issue edit "${GH_ISSUE_NUMBER}" \
  --title "$(tr -d '\n' < "${GH_CLAUDE_SESSION_DIR}/drafts/issue_title_draft.txt")" \
  --body-file "${GH_CLAUDE_SESSION_DIR}/drafts/issue_body_draft.md"
```

### 8. **Confirm Success**

- On success: Show the updated issue URL and a brief confirmation
- On failure: Display the full error and suggest `gh auth status` or repo permission check

---

## Rules & Guidelines

### Content Changes

- **Scope:** Apply only the requested changes; don't "improve" beyond the request
- **Preservation:** Keep existing wording, links, formatting, and structure unless explicitly asked to change
- **Title:** Must be under 72 characters; clear and descriptive
- **Body:** Use GitHub-flavored Markdown; maintain readability with sections, code blocks, lists
- **Clarity:** If a request is ambiguous (e.g., "make it better"), ask "What specifically should change?"

### Safety & Permissions

- If required context is missing, **ask rather than guess**
- If issue fetch fails, **stop immediately** and ask user to:
  - Verify the issue number
  - Run `gh auth status` to check authentication
  - Confirm repo accessibility
- If `gh issue edit` fails, show the full error and suggest next steps
- **Never silently drop information** unless explicitly requested

### Edge Cases

- **Large changes:** Ask if user wants a fresh rewrite vs. incremental edits
- **Title too long:** Flag (≥72 chars) and ask for shortening before posting
- **Removing content:** Confirm explicitly ("You requested I remove the 'Acceptance Criteria' section—confirm?")
- **Markdown corruption:** If body becomes malformed, warn and ask for revision
- **Multiple edits in one session:** Treat each as a new workflow (fetch fresh each time)
- **Closed issues:** Note state and confirm before applying edits

---

## Error Messages & Recovery

| Scenario                   | Action                                                          |
| -------------------------- | --------------------------------------------------------------- |
| `GH_ISSUE_NUMBER` not set  | Ask user: "Which issue? (use `#123` or set `$GH_ISSUE_NUMBER`)" |
| `gh issue view` fails      | Show error, suggest `gh auth status`                            |
| `gh issue edit` fails      | Show error, suggest `gh auth status` or repo permission check   |
| Title ≥72 characters       | Warn and ask user to shorten                                    |
| Markdown body is malformed | Show preview and ask for revision before posting                |
| User interrupts editing    | Offer: save draft, discard, or resume                           |
| Request is ambiguous       | Ask: "Which of these did you mean? [options]"                   |

---

## Example Interactions

**Simple edit:**

```
User: "Add acceptance criteria to issue #15"
→ AI shows draft with new "Acceptance Criteria" section added
User: "Perfect, apply it"
→ Successfully edited, shows updated issue URL
```

**Iterative refinement:**

```
User: "Rewrite the issue description to be clearer"
→ AI rewrites, shows draft
User: "Good, but add a note about the deadline"
→ AI revises and re-shows
User: "Apply"
→ Successfully edited
```

**Scope clarification:**

```
User: "Improve this issue"
→ AI asks: "What specifically? (e.g., clarify title, add acceptance criteria, reorganize sections)"
User: "Clarify the title and add a 'Definition of Done' section"
→ AI applies both changes and shows draft
```

**Preservation in action:**

```
User: "Update the title but keep everything else"
→ AI changes ONLY title, preserves entire body exactly as-is
```

