---
name: gh:pr:comment
description: >
  Drafts a GitHub pull request comment based on PR context, then posts it after
  user confirmation. Provide optional argument text describing the comment
  intent, e.g., "respond to the review feedback" or "post a status update."
argument-hint: "[comment intent or text]"
version: 1.0.0
disable-model-invocation: true
allowed-tools: Bash(*), Write
---

# Draft and Post GitHub PR Comments

## Prerequisites

- `gh` CLI installed and authenticated (`gh auth status` to verify)
- Environment: `$GH_PR_NUMBER` (set or pass explicitly)
- Directories: `$GH_CLAUDE_SESSION_DIR` must be writable
- Write permissions on the repository

## Context

**Current Pull Request (always fresh):**

```
!`gh pr view ${GH_PR_NUMBER} --json number,title,url,body,labels,comments,isDraft,state,reviewDecision,reviews,commits 2>/dev/null | jq -r -f ${CLAUDE_PLUGIN_ROOT}/queries/gh_pr_view.jq || echo "Unable to fetch PR. Check the PR number and gh auth status."`
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

- Verify `$GH_PR_NUMBER` is set; if not, ask the user
- Fetch PR details (title, body, state, reviews, comments); if fetch fails, stop and show the error
- Check user has write permissions to the repo (auth required)

### 2. **Draft the Comment**

- **If arguments provided:** Use them as the comment seed or full draft
- **If empty:** Infer the most helpful comment from:
  - PR title and description
  - Current review decision and pending reviews
  - Existing comments (to avoid redundancy)
  - PR state (draft, open, merged, etc.)
- When addressing reviews, reference the specific concern or reviewer
- Keep tone professional, constructive, and concise
- Use GitHub Markdown (code blocks, diffs, lists, @mentions where relevant)

### 3. **Present for Review**

```
---
**Draft comment for PR #N:**

{comment body in GitHub-flavored Markdown}

_Post this comment, or tell me what to change?_
---
```

### 4. **Handle User Feedback**

- **If user confirms** (`"post"`, `"yes"`, `"looks good"`, `"👍"`): Proceed to step 5
- **If user requests changes**: Revise and return to step 3
- **If user says cancel** (`"no"`, `"cancel"`, `"discard"`): Stop and don't post
- **If no response to confirmation**: Ask once more: "Should I post this or discard it?"

### 5. **Save & Post**

```bash
mkdir -p "${GH_CLAUDE_SESSION_DIR}/drafts"
cat > "${GH_CLAUDE_SESSION_DIR}/drafts/pr_comment_draft.md" << 'EOF'
{comment body}
EOF

gh pr comment "${GH_PR_NUMBER}" \
  --body-file "${GH_CLAUDE_SESSION_DIR}/drafts/pr_comment_draft.md"
```

### 6. **Confirm Success**

- On success: Show the posted comment URL and a brief confirmation
- On failure: Display the full error and suggest `gh auth status`

---

## Rules & Guidelines

### Content

- **Tone:** Professional, constructive, and respectful; avoid dismissive language
- **Length:** Generally 1–3 paragraphs; use bullet points for lists of changes/concerns
- **Specificity:** Reference commits, file names, line numbers, or reviewer names when relevant
- **Addressing Reviews:** If replying to a review, quote or reference the specific concern
- **Avoid:**
  - Excessive emoji (one or two if naturally appropriate)
  - Auto-merging or auto-closing PRs without explicit user intent
  - Bare "LGTM" or "+1" without substantive feedback (unless the user explicitly requests it)
  - Passive-aggressive tone

### PR Context Awareness

- **PR state matters:** Handle draft PRs differently (don't rush approval)
- **Review decision:** Consider existing review state (changes requested vs. approved)
- **Multiple reviews:** If the PR has multiple pending reviews and the user's intent is ambiguous, list the reviewers and ask which review to address
- **Merged/closed PRs:** Still allow comments, but the PR state should inform tone (e.g., "nice work on shipping" vs. "please fix")

### Safety & Permissions

- If required context is missing, **ask rather than guess**
- If PR fetch fails, **stop immediately** and ask user to:
  - Verify the PR number
  - Run `gh auth status` to check authentication
  - Confirm repo accessibility
- If `gh pr comment` fails, show the full error and suggest next steps

### Edge Cases

- **Merged/closed PRs:** Note the state and confirm before posting
- **Draft PRs:** Warn if posting approval comments (may not be intended)
- **Very long PRs:** Summarize focus area and ask if comment is relevant
- **Comment would be redundant:** Warn and ask user to confirm or revise
- **Sensitive topics:** Flag before posting if comment touches security, licensing, or major architecture changes
- **Review threads:** This skill posts general PR comments only; it cannot reply to specific inline review threads

---

## Error Messages & Recovery

| Scenario                   | Action                                                        |
| -------------------------- | ------------------------------------------------------------- |
| `GH_PR_NUMBER` not set     | Ask user: "Which PR? (use `#123` or set `$GH_PR_NUMBER`)"     |
| `gh pr view` fails         | Show error, suggest `gh auth status`                          |
| `gh pr comment` fails      | Show error, suggest `gh auth status` or repo permission check |
| User interrupts drafting   | Offer: save draft, discard, or resume                         |
| Comment would be redundant | Warn and ask user to confirm or revise                        |
| PR is draft or closed      | Note state and ask for confirmation before posting            |

---

## Example Interactions

**Simple approval:**

```
User: "Comment that the changes look good"
→ AI drafts approval comment with specific praise for the changes
User: "Perfect, post it"
→ Posts successfully
```

**Addressing a review:**

```
User: "Reply to the security review comment about input validation"
→ AI references the specific concern, drafts a response
User: "Make it a bit more detailed about the fix"
→ AI revises and re-shows
User: "Post it"
→ Posts successfully
```

**Status update:**

```
User: "Add a comment that I'm incorporating feedback"
→ AI drafts a progress update
User: "Add that I'll have it done by EOD Friday"
→ AI revises and re-shows
User: "Good, post it"
→ Posts successfully
```

**State awareness:**

```
User: "Comment on PR #42"
→ AI fetches and notes: "This PR is merged. Still want to comment?"
User: "Yes, note the successful deployment"
→ AI drafts comment appropriate for merged state
```

