---
name: gh:pr:review
description: >
  Drafts a GitHub pull request review with structured code feedback and submits
  it after user confirmation. Supports approving, requesting changes, or leaving
  a comment-only review. Use when the user wants to review a PR, give feedback
  on code changes, approve or reject a pull request, or request changes —
  "review PR #N", "approve PR #42", "request changes on this PR",
  "give feedback on PR #N", "reject this PR", "do a code review of #N",
  "LGTM on PR #42", or "review this pull request focusing on security".
argument-hint: <pr-number> [approve|request-changes|comment] [focus area]
disable-model-invocation: true
allowed-tools: Bash(gh *), Write
---

Draft a GitHub pull request review with structured code feedback, then submit it
after the user confirms. The review outcome (approve, request-changes, or comment)
is determined during the review and confirmed before submission.

## PR context

!`gh pr view $ARGUMENTS[0] --json number,title,url,body,labels,comments,isDraft,state,reviewDecision,reviews,commits 2>/dev/null | jq -r -f queries/gh_pr_view.jq || echo "Unable to fetch PR. Check the PR number and gh auth status."`

## Additional context

!`cat ".github/sessions/pull-$ARGUMENTS[0]/pr_context.md" 2>/dev/null || true`

## Review type

!`echo "$ARGUMENTS" | awk '{print $2}' | grep -xE 'approve|request-changes|comment' || true`

(If empty, determine the appropriate outcome based on the review findings.)

## Focus area

!`echo "$ARGUMENTS" | awk '{for(i=2;i<=NF;i++) if($i !~ /^(approve|request-changes|comment)$/) printf "%s ", $i}'`

(If empty, review all changes comprehensively.)

## Workflow

1. Fetch the PR diff and save it locally for analysis:
   `mkdir -p .github/sessions/pull-$ARGUMENTS[0] && gh pr diff $ARGUMENTS[0] --patch > .github/sessions/pull-$ARGUMENTS[0]/pr_diff.patch 2>/dev/null`
   Then generate a diffstat:
   `git apply --stat < .github/sessions/pull-$ARGUMENTS[0]/pr_diff.patch 2>/dev/null || echo "(diffstat unavailable)"`
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
7. When the user confirms, write the review body to
   `.github/sessions/pull-$ARGUMENTS[0]/pr_review_draft.md` and run the
   matching command:
   - Approve: `gh pr review $ARGUMENTS[0] --approve --body-file .github/sessions/pull-$ARGUMENTS[0]/pr_review_draft.md`
   - Request changes: `gh pr review $ARGUMENTS[0] --request-changes --body-file .github/sessions/pull-$ARGUMENTS[0]/pr_review_draft.md`
   - Comment: `gh pr review $ARGUMENTS[0] --comment --body-file .github/sessions/pull-$ARGUMENTS[0]/pr_review_draft.md`
8. Confirm success with the PR URL.

## Rules

- Prioritize bugs, security/data-loss issues, logic errors, and missing error handling.
- Skip purely stylistic comments, issues detectable by linters, and unrelated legacy issues.
- Use severity levels: High (blocks approval), Medium (logic/edge cases), Low (minor improvements).
- If the PR is a draft, note that it may not be ready for formal review.
- If the diff is too large to analyze fully, focus on the most critical files and state which files were skipped.
- If the `gh pr review` command fails (e.g. reviewing your own PR), show the error and suggest posting as a comment instead.
- GitHub has no "reject" action — map user requests to "reject" to request-changes.

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

_Submit this review, or tell me what to change?_
