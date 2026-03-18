---
name: gh:pr:review
description: >
  Drafts a GitHub pull request review with structured code feedback and submits
  it after user confirmation. Supports approving, requesting changes, or leaving
  a comment-only review. Use when the user wants to review a PR, give feedback
  on code changes, approve or reject a pull request, or request changes —
  "review PR #N", "approve PR #42", "request changes on this PR",
  "give feedback on PR #N", "do a code review of #N",
  "LGTM on PR #42", or "review this pull request focusing on security".
argument-hint: "[approve|request-changes|comment] [focus area]"
disable-model-invocation: true
allowed-tools: Bash(*), Write
---

Draft a GitHub pull request review with structured code feedback, then submit it
after the user confirms. The review outcome (approve, request-changes, or comment)
is determined during the review and confirmed before submission.

## PR context

!`gh pr view $GH_AI_PR_NUMBER --json number,title,url,body,labels,comments,isDraft,state,reviewDecision,reviews,commits 2>/dev/null | jq -r -f $CLAUDE_PLUGIN_ROOT/queries/gh_pr_view.jq || echo "Unable to fetch PR. Check the PR number and gh auth status."`

## Review history

!`gh api repos/$(gh repo view --json nameWithOwner --jq .nameWithOwner)/pulls/$GH_AI_PR_NUMBER/reviews --paginate 2>/dev/null | jq -s '[.[][] | {id: .id, state: .state, submitted_at: .submitted_at, body: (.body // "")}]' || echo "Unable to fetch review history."`

## Current head commit

!`gh pr view $GH_AI_PR_NUMBER --json headRefOid --jq .headRefOid 2>/dev/null || echo "unknown"`

## Prior AI review for current commit

!`REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) && HEAD=$(gh pr view $GH_AI_PR_NUMBER --json headRefOid --jq .headRefOid 2>/dev/null) && MARKER="<!-- gh-ai:pr-review pr=${GH_AI_PR_NUMBER} commit=${HEAD} -->" && gh api "repos/${REPO}/pulls/${GH_AI_PR_NUMBER}/reviews" --paginate 2>/dev/null | jq -rs '.[].[] | .body' | grep -qF "$MARKER" && echo "exists" || true`

## Additional context

!`cat "$GH_AI_SESSION_DIR/state/pr_context.md" 2>/dev/null || true`

## Review type

!`echo "$ARGUMENTS" | tr ' ' '\n' | head -1 | grep -xE 'approve|request-changes|comment' || true`

(If empty, determine the appropriate outcome based on the review findings.)

## Focus area

!`echo "$ARGUMENTS" | tr ' ' '\n' | grep -vxE 'approve|request-changes|comment' | tr '\n' ' ' | xargs || true`

(If empty, review all changes comprehensively.)

## Workflow

0. If "Prior AI review for current commit" above shows "exists", tell the user:
   > "An AI-generated review already exists on this PR for the current commit. Submit a new review anyway, or cancel?"
   Wait for their response. If they cancel, stop here.
1. Fetch the PR diff and save it locally for analysis:
   `gh pr diff $GH_AI_PR_NUMBER --patch > $GH_AI_SESSION_DIR/state/pr_diff.patch 2>/dev/null`
   Then generate a diffstat:
   `git -C "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" apply --stat < $GH_AI_SESSION_DIR/state/pr_diff.patch 2>/dev/null || echo "(diffstat unavailable)"`
2. Read the full diff and analyze the relevant changed files for bugs, security
   issues, logic errors, missing error handling, and performance concerns.
3. Write the review draft with a recommended outcome. If a review type was
   specified above, use that outcome. Otherwise, choose based on findings:
   - approve — no blocking issues found
   - request-changes — high-severity issues that must be fixed
   - comment — observations worth noting but not blocking
4. Show the draft to the user clearly marked as a draft.
5. Ask the user: "Submit this review, or tell me what to change?"
6. If the user requests changes to the draft, revise and repeat from step 4.
7. When the user confirms, run `mkdir -p $GH_AI_SESSION_DIR/drafts`, write the review body to
   `$GH_AI_SESSION_DIR/drafts/pr_review_draft.md`, appending
   `<!-- gh-ai:pr-review pr=<PR_NUMBER> commit=<HEAD_SHA> -->` (with the actual
   PR number and head commit SHA) as the last line. Then run the
   matching command:
   - Approve: `gh pr review $GH_AI_PR_NUMBER --approve --body-file $GH_AI_SESSION_DIR/drafts/pr_review_draft.md`
   - Request changes: `gh pr review $GH_AI_PR_NUMBER --request-changes --body-file $GH_AI_SESSION_DIR/drafts/pr_review_draft.md`
   - Comment: `gh pr review $GH_AI_PR_NUMBER --comment --body-file $GH_AI_SESSION_DIR/drafts/pr_review_draft.md`
8. Confirm success with the PR URL.

## Rules

- Prioritize bugs, security/data-loss issues, logic errors, and missing error handling.
- Skip purely stylistic comments, issues detectable by linters, and unrelated legacy issues.
- Use severity levels: High (blocks approval), Medium (logic/edge cases), Low (minor improvements).
- If the PR is a draft, note that it may not be ready for formal review.
- If the diff is too large to analyze fully, focus on the most critical files and state which files were skipped.
- If the `gh pr review` command fails (e.g. reviewing your own PR), show the full error; for own-PR failures suggest posting as a comment instead, for auth/network failures suggest running `gh auth status`.
- GitHub has no "reject" action — map user requests to "reject" to request-changes.
- Findings are reported in the top-level review body only. Inline diff comments are not supported — `Location: file:line` references are informational pointers, not attached annotations.
- If the diff is empty (no changes to review), tell the user and stop — do not generate a review for an empty patch.
- If the PR context shows "Unable to fetch...", stop and ask the user to verify the PR number and run `gh auth status`.

## Draft format

ALWAYS present the draft clearly so the user can read it before confirming:

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

---

_Submit this review, or tell me what to change._
