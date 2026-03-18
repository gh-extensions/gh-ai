---
name: gh:pr:review
description: >
  Drafts a GitHub pull request review with structured code feedback and submits 
  it after user confirmation. Supports approve, request-changes, or comment. 
  Recognizes invocations like "review PR #123", "approve PR #42", "request 
  changes on this PR", "give feedback focusing on security", or "do a code review 
  of #N".
argument-hint: "[approve|request-changes|comment] [focus area]"
disable-model-invocation: true
allowed-tools: Bash(*), Write
---

# Draft and Submit GitHub PR Reviews

## Mode: REVIEW-ONLY

Your role: **read the diff → analyze for issues → draft a structured review → revise → submit the review to GitHub.**

**Submitting the review** means posting it to GitHub. It does NOT mean: merging, editing the PR, or creating separate comments.

## Prerequisites

- `gh` CLI installed and authenticated (`gh auth status` to verify)
- Environment: `$GH_PR_NUMBER` (set or pass explicitly)
- Directories: `$GH_CLAUDE_SESSION_DIR` must be writable
- Write permissions on the repository
- Git repo with access to local commits (for diff context)

## Context

**Current Pull Request (always fresh):**

```
!`gh pr view ${GH_PR_NUMBER} --json number,title,url,body,labels,comments,isDraft,state,reviewDecision,reviews,commits 2>/dev/null | jq -r -f ${CLAUDE_PLUGIN_ROOT}/queries/gh_pr_view.jq || echo "Unable to fetch PR. Check the PR number and gh auth status."`
```

**Review History (always fresh):**

```
!`gh api repos/$(gh repo view --json nameWithOwner --jq .nameWithOwner)/pulls/${GH_PR_NUMBER}/reviews --paginate 2>/dev/null | jq -s '[.[][] | {id: .id, state: .state, submitted_at: .submitted_at, body: (.body // "")}]' || echo "Unable to fetch review history."`
```

**Current Commit SHA:**

```
!`gh pr view ${GH_PR_NUMBER} --json headRefOid --jq .headRefOid 2>/dev/null || echo "unknown"`
```

**Session Notes (optional, non-authoritative):**

```
!`cat "${GH_CLAUDE_SESSION_DIR}/state/session_notes.md" 2>/dev/null || true`
```

**User Request:**

```
!`echo "$ARGUMENTS" | tr ' ' '\n' | head -1 | grep -xE 'approve|request-changes|comment' || true`
```

(If empty, determine outcome based on findings.)

```
!`echo "$ARGUMENTS" | tr ' ' '\n' | grep -vxE 'approve|request-changes|comment' | tr '\n' ' ' | xargs || true`
```

(If empty, review all changes comprehensively.)

## Workflow

### 0. **Check for Prior Reviews**

- Detect if an AI-generated review already exists for this commit (uses tracking marker)
- If found, ask: **"An AI-generated review already exists for this commit. Submit a new one anyway, or cancel?"**
- If user cancels, stop. Otherwise, proceed.

### 1. **Validate & Fetch**

- Verify `$GH_PR_NUMBER` is set; if not, ask the user
- Fetch PR details, review history, and commit SHA; if any fetch fails, stop and show error
- Check user has write permissions to the repo (auth required)
- Note PR state: is it a draft, open, in review, approved, or merged?

### 2. **Fetch & Analyze Diff**

```bash
gh pr diff ${GH_PR_NUMBER} --patch > ${GH_CLAUDE_SESSION_DIR}/state/pr_diff.patch 2>/dev/null
git -C "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" apply --stat < ${GH_CLAUDE_SESSION_DIR}/state/pr_diff.patch 2>/dev/null || echo "(diffstat unavailable)"
```

- If diff is empty, **stop and inform the user** — do not proceed with review
- If diff is extremely large (1000+ lines), focus on critical files and note which were skipped

### 3. **Determine Review Scope**

- **If focus area provided:** Review with that lens (e.g., "security", "performance")
- **If empty:** Review comprehensively (logic, bugs, error handling, architecture)
- Analyze for:
  - **High severity:** Bugs, security/data-loss risks, logic errors, missing error handling
  - **Medium severity:** Edge cases, optimization opportunities, architectural concerns
  - **Low severity:** Minor improvements, clarity enhancements (non-blocking)

### 4. **Determine Outcome**

- **If outcome specified in arguments:** Use it (approve/request-changes/comment)
- **If empty:** Determine based on findings:
  - **Approve:** No blocking issues found
  - **Request Changes:** High-severity issues require fixes
  - **Comment:** Observations worth noting but not blocking
- Never auto-approve without thorough review

### 5. **Draft the Review**

- Structure review with sections: Summary, Findings (by severity), Action Items
- Include file and line references for context (`file.ext:line`)
- Provide specific suggestions for each finding
- Keep tone professional, constructive, and respectful
- Append tracking marker: `<!-- gh-claude:pr-review pr=<PR_NUMBER> commit=<HEAD_SHA> -->`

### 6. **Present for Review**

```
---
**Draft review for PR #N:**

**Outcome: {Approve | Request Changes | Comment}**

## Summary
{overview of the PR and assessment}

## Findings
[{High|Medium|Low}] {issue}
Location: `file.ext:line`
Details: {explanation}
Suggestion: {fix}

## Action Items
Required Changes:
- [ ] {blocking issue}

Advisory:
- {optional improvement}

_Submit this review, or tell me what to change?_
---
```

### 7. **Handle User Feedback**

- **If user confirms** (`"submit"`, `"yes"`, `"👍"`): Proceed to step 8
- **If user requests changes**: Revise and return to step 6
- **If user says cancel** (`"no"`, `"cancel"`, `"discard"`): Stop and don't submit
- **If outcome changes** (e.g., "change to comment"): Update and re-show
- **If no response after 2 clarifications**: Ask "Should I submit this review or discard it?"

### 8. **Save & Submit**

```bash
mkdir -p ${GH_CLAUDE_SESSION_DIR}/drafts
cat > ${GH_CLAUDE_SESSION_DIR}/drafts/pr_review_draft.md << 'EOF'
{review body with tracking marker}
EOF

# Based on outcome:
gh pr review ${GH_PR_NUMBER} --approve --body-file ${GH_CLAUDE_SESSION_DIR}/drafts/pr_review_draft.md
# OR
gh pr review ${GH_PR_NUMBER} --request-changes --body-file ${GH_CLAUDE_SESSION_DIR}/drafts/pr_review_draft.md
# OR
gh pr review ${GH_PR_NUMBER} --comment --body-file ${GH_CLAUDE_SESSION_DIR}/drafts/pr_review_draft.md
```

### 9. **Confirm Success**

- On success: Show the submitted review URL and brief confirmation
- On failure: Display the full error and suggest next steps

---

## Rules & Guidelines

### Review Scope & Severity

- **Prioritize:** Bugs, security/data-loss issues, logic errors, missing error handling
- **Medium:** Edge cases, optimization opportunities, architectural concerns
- **Low:** Code clarity, style improvements, minor refactors
- **Skip:** Purely stylistic comments, linter-detectable issues, unrelated legacy code issues
- **Balance:** Provide constructive feedback without being nitpicky

### Content & Structure

- **Findings format:** `[Severity] issue → Location → Details → Suggestion`
- **Action items:** Separate required changes (blocking) from advisory (optional)
- **Tone:** Professional, respectful, collaborative—avoid dismissive or condescending language
- **Specificity:** Reference exact files, line numbers, and code context
- **Suggestions:** Offer concrete fixes or improvements, not just criticism

### Review State Awareness

- **Draft PRs:** Note that review may be premature; adjust tone accordingly
- **Existing reviews:** Consider prior feedback to avoid redundancy
- **Review decision state:** Be aware if PR already has approvals or change requests
- **Merged PRs:** Still allow reviews (for documentation/future reference), but note state
- **Tracking marker:** Always include; prevents duplicate AI reviews on same commit

### Safety & Permissions

- If required context is missing, **ask rather than guess**
- If diff is empty, **stop immediately** — do not proceed
- If diff is very large (1000+ lines), **focus on critical files** and state which were skipped
- If PR fetch fails, **stop immediately** and ask user to:
  - Verify the PR number
  - Run `gh auth status` to check authentication
  - Confirm repo accessibility
- If `gh pr review` fails on user's own PR, suggest posting as a comment instead
- If `gh pr review` fails for auth/network reasons, show full error and suggest `gh auth status`

### Edge Cases

- **Empty diff:** Stop; inform user and don't review
- **Massive diff:** Focus on critical areas; note scope limits
- **Outcome change:** If user changes outcome mid-review, update and re-show
- **Existing AI review:** Ask before posting duplicate review
- **Sensitive code:** Flag (security, compliance, architecture changes) before submitting
- **Prior conflicting reviews:** Acknowledge if request contradicts previous feedback

---

## Error Messages & Recovery

| Scenario                            | Action                                                              |
| ----------------------------------- | ------------------------------------------------------------------- |
| `GH_PR_NUMBER` not set              | Ask user: "Which PR? (use `#123` or set `$GH_PR_NUMBER`)"           |
| `gh pr view` fails                  | Show error, suggest `gh auth status`                                |
| Diff is empty                       | Stop immediately; inform user and do not proceed                    |
| Diff is massive (1000+ lines)       | Ask: "Focus on critical files only?" and list scope                 |
| `gh pr review` fails (own PR)       | Suggest: "You can't review your own PR. Post as a comment instead?" |
| `gh pr review` fails (auth/network) | Show error, suggest `gh auth status`                                |
| Prior AI review exists              | Ask: "Resubmit or cancel?"                                          |
| User interrupts reviewing           | Offer: save draft, discard, or resume                               |
| Outcome is ambiguous                | Ask: "Should this be approve, request-changes, or comment?"         |

---

## Example Interactions

**Straightforward approval:**

```
User: "Approve PR #25"
→ AI fetches diff, analyzes, finds no blocking issues
→ Drafts approval review with minor observations (comment-level)
User: "Looks good, submit it"
→ Submits approval review successfully
```

**Catching a bug:**

```
User: "Review PR #30 focusing on security"
→ AI analyzes, finds potential SQL injection in query builder
→ Drafts request-changes review with severity levels and suggestions
User: "Make the suggestion more concrete with example code"
→ AI revises and re-shows
User: "Good, submit it"
→ Submits request-changes review
```

**Large PR scope limitation:**

```
User: "Review PR #100"
→ AI fetches 2000+ line diff; notes scope
→ Drafts review focusing on critical logic files, notes which were skipped
User: "Looks comprehensive for the scope, submit it"
→ Submits comment review
```

**Iterative refinement:**

```
User: "Review PR #45"
→ AI drafts comment-level review with observations
User: "Actually, the middleware change looks risky—request changes?"
→ AI revises outcome to request-changes, re-shows with higher severity
User: "Perfect, submit it"
→ Submits request-changes review
```

---

## Dependencies & Assumptions

- **External tools:** `gh` CLI (v2.0+), `jq`, `git`
- **Query files:** `${CLAUDE_PLUGIN_ROOT}/queries/gh_pr_view.jq` (must exist)
- **Environment:** `$GH_CLAUDE_SESSION_DIR` for drafts and diff storage
- **Repo state:** User is in a git repo with access to commits; `gh pr diff` works
- **Review metadata:** Query includes reviews, comments, state for context
- **Tracking marker:** Embedded in review body to prevent duplicate AI reviews

---

## Implementation Notes

### Diff Fetching

- Use `gh pr diff ${GH_PR_NUMBER} --patch` to fetch raw patch
- Use `git apply --stat` to show file-by-file stats (helps with scope)
- Store in `${GH_CLAUDE_SESSION_DIR}/state/pr_diff.patch` for reference

### Tracking Marker Format

```markdown
<!-- gh-claude:pr-review pr=<GH_PR_NUMBER> commit=<HEAD_SHA> -->
```

- Always append to review body (end of review)
- Used to detect duplicate AI reviews on same commit
- Inert for GitHub display (HTML comment)

### Outcome Mapping

- `approve` → PR is good to merge (no blocking issues)
- `request-changes` → Issues exist that must be fixed before merge
- `comment` → Observations noted but not blocking

---

## Future Enhancements

- [ ] Inline code suggestions (GitHub's suggestion feature integration)
- [ ] Commit-by-commit review mode (review each commit separately)
- [ ] Comparison with prior reviews (highlight if contradicting feedback)
- [ ] Auto-detection of high-risk files (security, migrations, config)
- [ ] Performance analysis (detect N+1 queries, inefficient loops)
- [ ] Test coverage check (flag untested new code)
- [ ] Custom linting rules (organization-specific patterns)
- [ ] Reviewee mentions (optional: tag reviewee in summary)
- [ ] Multi-file context (understand cross-file dependencies)
- [ ] Rollback capability (ability to retract and resubmit review)
