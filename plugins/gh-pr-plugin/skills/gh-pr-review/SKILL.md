---
name: gh:pr:review
description: >
  Drafts a GitHub pull request review with structured code feedback and submits
  it after user confirmation. Supports approve, request-changes, or comment.
  Trigger when the user says "review PR #N", "approve PR #42", "request changes
  on this PR", "give feedback on PR #N", "do a code review of #N", "LGTM on
  PR #42", or "review this pull request focusing on security".
argument-hint: "[approve|request-changes|comment] [focus area]"
disable-model-invocation: true
allowed-tools: Bash(*), Write
---

Draft a GitHub pull request review with structured code feedback, then submit it after confirmation.

## Mode: REVIEW-ONLY

Your job: read the diff → analyze for issues → draft a review → revise → submit. Nothing else.

**Confirming means: submit the review to GitHub. It never means: merge, edit, or comment separately.**

## Context

!`gh pr view ${GH_PR_NUMBER} --json number,title,url,body,labels,comments,isDraft,state,reviewDecision,reviews,commits 2>/dev/null | jq -r -f ${CLAUDE_PLUGIN_ROOT}/queries/gh_pr_view.jq || echo "Unable to fetch PR. Check the PR number and gh auth status."`

!`gh api repos/$(gh repo view --json nameWithOwner --jq .nameWithOwner)/pulls/${GH_PR_NUMBER}/reviews --paginate 2>/dev/null | jq -s '[.[][] | {id: .id, state: .state, submitted_at: .submitted_at, body: (.body // "")}]' || echo "Unable to fetch review history."`

!`gh pr view ${GH_PR_NUMBER} --json headRefOid --jq .headRefOid 2>/dev/null || echo "unknown"`

!`REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) && HEAD=$(gh pr view ${GH_PR_NUMBER} --json headRefOid --jq .headRefOid 2>/dev/null) && [ -n "$REPO" ] && [ -n "$HEAD" ] && MARKER="<!-- gh-claude:pr-review pr=${GH_PR_NUMBER} commit=${HEAD} -->" && gh api "repos/${REPO}/pulls/${GH_PR_NUMBER}/reviews" --paginate 2>/dev/null | jq -rs '.[].[] | .body' | grep -qF "$MARKER" && echo "exists" || true`

!`cat "${GH_CLAUDE_SESSION_DIR}/state/pr_context.md" 2>/dev/null || true`

## Arguments

!`echo "$ARGUMENTS" | tr ' ' '\n' | head -1 | grep -xE 'approve|request-changes|comment' || true`

(If empty, determine the outcome based on review findings.)

!`echo "$ARGUMENTS" | tr ' ' '\n' | grep -vxE 'approve|request-changes|comment' | tr '\n' ' ' | xargs || true`

(If empty, review all changes comprehensively.)

## Workflow

0. If a prior AI review exists for the current commit, ask:
   > "An AI-generated review already exists for this commit. Submit a new one anyway, or cancel?"
   If they cancel, stop.
1. Fetch the diff:
   - `gh pr diff ${GH_PR_NUMBER} --patch > ${GH_CLAUDE_SESSION_DIR}/state/pr_diff.patch 2>/dev/null`
   - `git -C "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" apply --stat < ${GH_CLAUDE_SESSION_DIR}/state/pr_diff.patch 2>/dev/null || echo "(diffstat unavailable)"`
2. Analyze the diff for bugs, security issues, logic errors, missing error handling, and performance concerns.
3. Draft the review with a recommended outcome:
   - approve — no blocking issues
   - request-changes — high-severity issues that must be fixed
   - comment — observations worth noting but not blocking
4. Show the draft framed with horizontal rules.
5. Ask: `Submit this review, or tell me what to change?`
6. If the user requests changes, revise and return to step 4.
7. When the user confirms, save and submit:
   - `mkdir -p ${GH_CLAUDE_SESSION_DIR}/drafts`
   - Write to `${GH_CLAUDE_SESSION_DIR}/drafts/pr_review_draft.md`
   - Append marker: `<!-- gh-claude:pr-review pr=<PR_NUMBER> commit=<HEAD_SHA> -->`
   - Approve: `gh pr review ${GH_PR_NUMBER} --approve --body-file ${GH_CLAUDE_SESSION_DIR}/drafts/pr_review_draft.md`
   - Request changes: `gh pr review ${GH_PR_NUMBER} --request-changes --body-file ${GH_CLAUDE_SESSION_DIR}/drafts/pr_review_draft.md`
   - Comment: `gh pr review ${GH_PR_NUMBER} --comment --body-file ${GH_CLAUDE_SESSION_DIR}/drafts/pr_review_draft.md`
8. Confirm success with the PR URL.

## Rules

- Prioritize bugs, security/data-loss issues, logic errors, and missing error handling.
- Skip purely stylistic comments, linter-detectable issues, and unrelated legacy issues.
- Severity levels: High (blocks approval), Medium (logic/edge cases), Low (minor improvements).
- If the PR is a draft, note it may not be ready for formal review.
- If the diff is too large, focus on the most critical files and state which were skipped.
- GitHub has no "reject" — map "reject" requests to request-changes.
- Findings go in the review body only. `Location: file:line` references are informational, not inline annotations.
- Always keep the tracking marker at the end of the review body.
- If the diff is empty, tell the user and stop — do not review an empty patch.
- If PR fetch fails, stop and ask the user to verify the number and run `gh auth status`.
- If `gh pr review` fails on own PR, suggest posting as a comment instead.
- If `gh pr review` fails for auth/network, show the error and suggest `gh auth status`.

## Draft format

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
