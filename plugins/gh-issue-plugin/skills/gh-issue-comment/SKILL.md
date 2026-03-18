---
name: gh:issue:comment
description: >
  Drafts a GitHub issue comment intelligently based on issue context, then 
  posts it after user confirmation. Recognizes natural invocations like 
  "write a comment on issue #123", "draft a response to this", or direct 
  command use while working on an issue.
argument-hint: "[comment intent or text]"
disable-model-invocation: true
allowed-tools: Bash(*), Write
---

# Draft and Post GitHub Issue Comments

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
- Fetch issue details (title, body, state, labels, comments); if fetch fails, stop and show the error
- Check user has write permissions to the repo (auth required)

### 2. **Draft the Comment**

- **If arguments provided:** Use them as the comment seed or full draft
- **If empty:** Infer the most helpful comment from:
  - Issue body and description
  - Existing comments (to avoid redundancy)
  - Labels and issue state (open/closed, bug/feature, etc.)
- Keep tone concise, professional, and constructive
- Use GitHub Markdown (code blocks, lists, mentions where relevant)

### 3. **Present for Review**

```
---
**Draft comment for issue #N:**

{comment body in GitHub-flavored Markdown}

_Post this comment, or tell me what to change?_
---
```

### 4. **Handle User Feedback**

- **If user confirms** (`"post"`, `"yes"`, `"👍"`): Proceed to step 5
- **If user requests changes**: Revise and return to step 3
- **If user says cancel** (`"no"`, `"cancel"`, `"discard"`): Stop and don't post
- **If no response after 2 clarifications**: Ask "Should I post this or discard it?"

### 5. **Save & Post**

```bash
mkdir -p ${GH_CLAUDE_SESSION_DIR}/drafts
cat > ${GH_CLAUDE_SESSION_DIR}/drafts/issue_comment_draft.md << 'EOF'
{comment body}
EOF

gh issue comment ${GH_ISSUE_NUMBER} \
  --body-file ${GH_CLAUDE_SESSION_DIR}/drafts/issue_comment_draft.md
```

### 6. **Confirm Success**

- On success: Show the posted comment URL and a brief confirmation
- On failure: Display the full error and suggest `gh auth status`

---

## Rules & Guidelines

### Content

- **Tone:** Constructive, professional, and respectful (avoid sarcasm or dismissive language)
- **Length:** Generally 1–3 paragraphs; break up long explanations with bullet points
- **Specificity:** Reference issue details by number, label, or user name when relevant
- **Avoid:**
  - Excessive emoji (one or two if naturally appropriate)
  - Closing or locking issues without explicit user intent
  - Multiple separate comments (consolidate into one where possible)
  - Speculation ("I think the bug might be...")—ask for clarification instead

### Issue Context Awareness

- **Issue state matters:** Closed issues may need different tone (e.g., "for future reference" vs. "please fix")
- **Labels inform context:** Bug vs. feature request vs. documentation; priority/severity; sensitivity labels (security, code of conduct)
- **Stale issues:** If issue is old, briefly acknowledge age and ask if context still applies
- **Thread patterns:** Avoid repeating points already made in comments; add new information or perspective

### Safety & Permissions

- If required context is missing, **ask rather than guess**
- If issue fetch fails, **stop immediately** and ask user to:
  - Verify the issue number
  - Run `gh auth status` to check authentication
  - Confirm repo accessibility
- If `gh issue comment` fails, show the full error and suggest next steps

### Edge Cases

- **Closed/locked issues:** Note state and confirm before posting
- **Duplicate comment detection:** Warn if your comment echoes recent discussion
- **Very old issues:** Acknowledge age; ask if context still relevant before posting
- **Sensitive topics:** Flag before posting if comment touches code of conduct, security, or major architecture decisions
- **First responder:** If you're the first to reply, set helpful tone for the discussion

---

## Error Messages & Recovery

| Scenario                   | Action                                                          |
| -------------------------- | --------------------------------------------------------------- |
| `GH_ISSUE_NUMBER` not set  | Ask user: "Which issue? (use `#123` or set `$GH_ISSUE_NUMBER`)" |
| `gh issue view` fails      | Show error, suggest `gh auth status`                            |
| `gh issue comment` fails   | Show error, suggest `gh auth status` or repo permission check   |
| User interrupts drafting   | Offer: save draft, discard, or resume                           |
| Comment would be redundant | Warn and ask user to confirm or revise                          |
| Issue is closed or locked  | Note state and ask for confirmation before posting              |

---

## Example Interactions

**Simple clarification:**

```
User: "Ask for clarification on the issue"
→ AI drafts a focused question referencing the issue
User: "Perfect, post it"
→ Posts successfully
```

**Bug confirmation:**

```
User: "Comment that I can reproduce the bug"
→ AI drafts reproduction confirmation
User: "Add details about my environment"
→ AI revises and re-shows
User: "Good, post it"
→ Posts successfully
```

**Providing context:**

```
User: "Reply with a possible solution"
→ AI drafts a constructive suggestion with code reference
User: "Make it less speculative"
→ AI revises to focus on facts, adds "have you tried..." question
User: "Post it"
→ Posts successfully
```

**Closed issue response:**

```
User: "Comment on issue #99"
→ AI fetches and notes: "This issue is closed. Still want to comment?"
User: "Yes, for future reference"
→ AI drafts comment appropriate for closed state (acknowledges closure, provides info)
```

---

## Dependencies & Assumptions

- **External tools:** `gh` CLI (v2.0+), `jq`
- **Query file:** `${CLAUDE_PLUGIN_ROOT}/queries/gh_issue_view.jq` (must exist)
- **Environment:** `$GH_CLAUDE_SESSION_DIR` for drafts
- **Repo state:** User is in a git repo with a remote, or `GH_ISSUE_NUMBER` is explicitly set
- **Labels:** Query should include labels for context awareness

---

## Future Enhancements

- [ ] Label detection (auto-flag security, code-of-conduct labels)
- [ ] Lint draft for common issues (speculation, vague language, duplicate points)
- [ ] Auto-suggest @mentions based on issue history and participants
- [ ] Template mode for common comment types (needs-info, works-for-me, proposed-solution, etc.)
- [ ] Markdown preview with syntax highlighting before posting
- [ ] Stale issue detection (warn if issue unchanged for 6+ months)
