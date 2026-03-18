---
name: gh:issue:plan
description: >
  Drafts an implementation plan for the current GitHub issue and posts it as a
  comment after explicit user confirmation. Use when a concrete implementation
  approach, task breakdown, or phased plan is needed. Provide optional argument
  to focus on a specific area.
argument-hint: "[focus area or aspect to plan]"
version: 1.0.0
disable-model-invocation: true
allowed-tools: Bash(*), Write
---

# Draft and Post GitHub Issue Implementation Plans

## Mode: PLAN-ONLY

Your role: **read the issue → understand the requirements → draft a concrete implementation plan → present for review → incorporate feedback → post the plan as a comment to GitHub.**

**Posting the plan** means creating or updating a plan comment. It does NOT mean: implementing anything, writing code, running tests, or making changes to the repo.

## Prerequisites

- `gh` CLI installed and authenticated (`gh auth status` to verify)
- Environment: `$GH_ISSUE_NUMBER` (set or pass explicitly)
- Directories: `$GH_CLAUDE_SESSION_DIR` must be writable
- Write permissions on the repository
- Git repo recommended (for working-tree context, optional)

## Context

**Current Issue (always fresh):**

```
!`gh issue view ${GH_ISSUE_NUMBER} --json number,title,url,body,state,labels,comments 2>/dev/null | jq -r -f ${CLAUDE_PLUGIN_ROOT}/queries/gh_issue_view.jq || echo "Unable to fetch issue. Check the issue number and gh auth status."`
```

**Session Notes (optional, non-authoritative):**

```
!`cat "${GH_CLAUDE_SESSION_DIR}/state/session_notes.md" 2>/dev/null || true`
```

**Repository Info:**

```
!`gh repo view --json url,defaultBranchRef --jq '"URL: \(.url)\nDefault branch: \(.defaultBranchRef.name)"' 2>/dev/null || echo "Unable to fetch repo info."`
```

**User Request:**

```
!`echo "$ARGUMENTS"`
```

## Forbidden Actions

**Do NOT:**

- Edit source files or configuration
- Create branches, commit, push, or open PRs
- Run build, test, formatter, linter, or package-manager commands
- Implement any part of the plan
- Write local files other than `${GH_CLAUDE_SESSION_DIR}/drafts/issue_plan_draft.md`

(Creating the `${GH_CLAUDE_SESSION_DIR}/drafts/` directory is allowed.)

## Workflow

### 1. **Validate & Fetch**

- Verify `$GH_ISSUE_NUMBER` is set; if not, ask the user
- Fetch issue details (title, body, labels, comments); if fetch fails, stop and show error
- Check user has write permissions to the repo (auth required)
- **Optional:** Check working tree status for context:
  ```bash
  git status --short
  git diff --stat HEAD
  ```
  (If git is unavailable or not a repo, skip silently and proceed)

### 2. **Note Local Changes (If Any)**

- If local changes detected, include at top of draft:
  ```
  **Note:** Local changes were detected in your working tree that may
  relate to this issue. This plan reflects the issue as described —
  not the current working-tree state.
  ```

### 3. **Determine Plan Scope**

- **If focus area provided:** Scope plan to that area only
- **If empty:** Plan full implementation
- If the issue describes three or more independent workstreams with no shared dependencies, recommend splitting; ask how to proceed

### 4. **Draft the Plan**

- Write as if the implementer has minimal context about the issue
- Use plain English; talk like you're briefing a teammate
- Break work into **small, sequential, concrete tasks**
- Label every task with sequential ID: `T001`, `T002`, `T003`, ...
- Hyperlink file references to GitHub (use repo URL and default branch from context); include line anchors when known
- Do NOT insert blank lines between task bullet items (keeps the list compact on GitHub)
- Include Open Questions section for anything that must be clarified before implementation
- Keep Likely Affected Areas section relevant to the issue context
- Format per specification below

### 5. **Present for Review**

```
---
**Draft implementation plan for issue #N:**

## Summary
{1-2 sentence description of the proposed approach}

## Likely Affected Areas
- [`{path/to/file.ext}`]({repo_url}/blob/{branch}/{path/to/file.ext}) — {why it likely matters}
- [`{path/to/file.ext#L10-L20}`]({repo_url}/blob/{branch}/{path/to/file.ext}#L10-L20) — {specific lines, if known}

## Tasks
- T001 — {small, concrete task}
- T002 — {small, concrete task}

## Open Questions
- {question}

_Post this plan as a comment, or tell me what to change?_
---
```

### 6. **Handle User Feedback**

- **If user confirms** (`"post"`, `"yes"`, `"looks good"`, `"👍"`): Proceed to step 7
- **If user requests changes**: Revise and return to step 5
- **If user says cancel** (`"no"`, `"cancel"`, `"discard"`): Stop and don't post
- **If scope changes**: Restart from step 3 or re-draft from step 4
- **If no response to confirmation**: Ask once more: "Should I post this plan or discard it?"

### 7. **Save Draft**

```bash
mkdir -p "${GH_CLAUDE_SESSION_DIR}/drafts"
cat > "${GH_CLAUDE_SESSION_DIR}/drafts/issue_plan_draft.md" << 'EOF'
{plan body}
<!-- gh-claude:issue-plan issue=${GH_ISSUE_NUMBER} -->
EOF
```

### 8. **Post or Update Comment**

- Fetch repo name:
  ```bash
  REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
  ```
- Find existing plan comment (using tracking marker):
  ```bash
  # --paginate returns one array per page; -s wraps them in an outer array
  # so .[][] flattens [[page1...],[page2...]] into a single stream
  COMMENT_ID=$(gh api "repos/${REPO}/issues/${GH_ISSUE_NUMBER}/comments" --paginate | jq -s --arg n "${GH_ISSUE_NUMBER}" '[.[][] | select(.body | test("gh-claude:issue-plan issue=" + $n))] | last | .id // empty')
  ```
- If existing comment found, **update** it:
  ```bash
  jq -Rs '{body: .}' "${GH_CLAUDE_SESSION_DIR}/drafts/issue_plan_draft.md" > "${GH_CLAUDE_SESSION_DIR}/drafts/issue_plan_draft_body.json"
  gh api "repos/${REPO}/issues/comments/${COMMENT_ID}" --method PATCH --input "${GH_CLAUDE_SESSION_DIR}/drafts/issue_plan_draft_body.json" --jq .html_url
  ```
- Otherwise, **create** new comment:
  ```bash
  gh issue comment "${GH_ISSUE_NUMBER}" --body-file "${GH_CLAUDE_SESSION_DIR}/drafts/issue_plan_draft.md"
  ```

### 9. **Confirm Success**

- On success: Show the posted/updated comment URL and confirm whether it was created or updated
- On failure: Display the full error and suggest `gh auth status`

---

## Rules & Guidelines

### Planning Style

- **Audience:** Write as if the implementer has minimal context
- **Tone:** Plain English, like briefing a teammate; avoid jargon where possible
- **Task granularity:** Small, concrete, sequential tasks; avoid vague descriptions
- **Naming:** Every task gets `T001`, `T002`, `T003`, ... labels
- **Components:** Hyperlink file references to GitHub; name modules, components, or systems
- **Honesty:** If you don't have enough info, say so and ask in Open Questions
- **Scope awareness:** If issue spans multiple independent areas, recommend splitting

### Content & Structure

- **Summary:** 1–2 sentences describing the proposed approach
- **Likely Affected Areas:** Hyperlink to files on GitHub using `[path](repo_url/blob/branch/path)` format; include `#L10` or `#L10-L20` line anchors when specific lines are known; omit section if no useful clues from issue context
- **Tasks:** Sequential, small, concrete, with clear IDs (`- T001 — ...`); hyperlink file and line references to GitHub; no blank lines between items (compact list)
- **Open Questions:** List anything requiring clarification before implementation starts; omit section if none
- **Tracking marker:** Always append at the end of the draft

### Safety & Scope Boundaries

- **No implementation:** Never write code, edit files, or run commands (except git/gh queries)
- **No branches/commits:** Never create branches, commit, push, or open PRs
- **No build/test:** Never run build, test, formatter, linter, or package-manager commands
- **No side effects:** Only safe to write `${GH_CLAUDE_SESSION_DIR}/drafts/` and create that directory
- **Focus matters:** If focus area provided, respect it; don't plan the full issue if user asks for one aspect

### Context Awareness

- **Working tree:** If local changes detected, note at top of plan that it reflects the issue, not the working tree
- **Labels & urgency:** Consider labels (bug, feature, urgent) when prioritizing tasks
- **Existing discussions:** Reference prior comments if they inform the plan
- **Scope splits:** If issue is too broad, explicitly recommend splitting before proceeding

### Error Handling

- If issue fetch fails, **stop immediately** and ask user to:
  - Verify the issue number
  - Run `gh auth status` to check authentication
  - Confirm repo accessibility
- If git unavailable, **skip working-tree check** and proceed without that context
- If comment API fails, **stop and show error** before continuing
- If posting/updating fails, show error and suggest `gh auth status`

### Edge Cases

- **Very broad issues:** Recommend splitting; ask user how to proceed
- **Too little context:** Use Open Questions section; don't invent details
- **Existing plan comment:** Find and update it (don't create duplicate)
- **Multiple focus areas:** Ask if user wants all or a specific area
- **Ambiguous requirements:** Flag in Open Questions; don't guess
- **No clear tasks:** If issue is too vague, ask for clarification before drafting

---

## Error Messages & Recovery

| Scenario                  | Action                                                              |
| ------------------------- | ------------------------------------------------------------------- |
| `GH_ISSUE_NUMBER` not set | Ask user: "Which issue? (use `#123` or set `$GH_ISSUE_NUMBER`)"     |
| `gh issue view` fails     | Show error, suggest `gh auth status`                                |
| Git unavailable           | Skip working-tree check, proceed without that context               |
| Issue context unclear     | Use Open Questions section; ask user to clarify before implementing |
| User wants to split scope | Ask which part to plan; restart from step 3                         |
| Comment API call fails    | Show full error, ask user to retry or cancel                        |
| Posting/updating fails    | Show error, suggest `gh auth status`                                |
| Plan too vague            | Ask for clarification on specific requirements                      |
| Existing plan found       | Update it instead of creating duplicate                             |

---

## Example Interactions

**Simple feature plan:**

```
User: "Plan issue #42 to add dark mode support"
→ AI fetches issue, drafts plan with affected areas (CSS, config, storage)
→ Shows 5 sequential tasks, 2 open questions about design tokens
User: "Looks good, post it"
→ Posts plan comment successfully
```

**Scoped plan (focus area):**

```
User: "Plan the backend part of issue #88"
→ AI fetches issue (which mentions frontend AND backend)
→ Drafts plan scoped to backend only
User: "Add a note about database migrations"
→ AI revises and re-shows
User: "Post it"
→ Posts plan comment
```

**Broad issue needing split:**

```
User: "Plan issue #100"
→ AI fetches issue; sees it covers 3 independent features
→ Asks: "This issue spans 3 areas. Should I plan all three, or focus on one?"
User: "Plan all three"
→ AI drafts comprehensive plan with tasks grouped by area
User: "Perfect, post it"
→ Posts plan successfully
```

**Updating existing plan:**

```
User: "Plan issue #15 to add a deployment section"
→ AI finds existing plan comment (with tracking marker)
→ Revises it to add deployment tasks
User: "Good, post it"
→ Updates the existing comment instead of creating duplicate
```
