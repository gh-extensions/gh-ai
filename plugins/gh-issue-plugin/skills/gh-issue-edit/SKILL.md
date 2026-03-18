---
name: gh:issue:edit
description: >
  Edits a GitHub issue title and/or body according to requested changes, then 
  applies the edit after user confirmation. Recognizes natural invocations like 
  "edit issue #123 to add acceptance criteria", "update the issue body", 
  "rewrite the description", "fix the title", or "improve this issue".
argument-hint: "[what to change or edit request]"
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
!`gh issue view ${GH_ISSUE_NUMBER} --json number,title,url,body,labels,comments 2>/dev/null | jq -r -f ${CLAUDE_PLUGIN_ROOT}/queries/gh_issue_view.jq || echo "Unable to fetch issue. Check the issue number and gh auth status."`
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
- **If no response after 2 clarifications**: Ask "Should I apply this edit or discard it?"

### 6. **Extract & Save**

```bash
mkdir -p ${GH_CLAUDE_SESSION_DIR}/drafts

# Extract title (first line, without "# " prefix)
TITLE_LINE=$(echo '{draft}' | head -1 | sed 's/^# //')
echo "$TITLE_LINE" > ${GH_CLAUDE_SESSION_DIR}/drafts/issue_title_draft.txt

# Extract body (everything after the title line)
echo '{draft}' | tail -n +2 > ${GH_CLAUDE_SESSION_DIR}/drafts/issue_body_draft.md
```

### 7. **Apply the Edit**

```bash
gh issue edit ${GH_ISSUE_NUMBER} \
  --title "$(cat ${GH_CLAUDE_SESSION_DIR}/drafts/issue_title_draft.txt | tr -d '\n')" \
  --body-file ${GH_CLAUDE_SESSION_DIR}/drafts/issue_body_draft.md
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

---

## Dependencies & Assumptions

- **External tools:** `gh` CLI (v2.0+), `jq`
- **Query file:** `${CLAUDE_PLUGIN_ROOT}/queries/gh_issue_view.jq` (must exist)
- **Environment:** `$GH_CLAUDE_SESSION_DIR` for drafts
- **Repo state:** User is in a git repo with a remote, or `GH_ISSUE_NUMBER` is explicitly set
- **Title handling:** Must respect 72-char limit (GitHub convention)

---

## Implementation Notes

### Title/Body Split

- Title is extracted from the first `# Heading` line in the draft
- Body is everything after the title line
- Ensure no double newlines between title and body in the draft

### Extraction Commands

```bash
# Title (without "# " prefix)
sed 's/^# //' | head -1

# Body (everything after first line)
tail -n +2
```

---

## Future Enhancements

- [ ] Diff preview mode (show side-by-side before/after)
- [ ] Linting for common issues (check title length before posting)
- [ ] Template mode (apply standard sections like "Acceptance Criteria", "DoD", etc.)
- [ ] Batch editing (update multiple issues with similar pattern)
- [ ] Rollback (keep version history, offer to revert recent edits)
- [ ] Smart merging (detect if title/body changed on GitHub while editing)
