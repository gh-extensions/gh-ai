---
title: Draft Pull Request
kind: github-pull-request
version: 0.1.0
status: active
---

## Preprocessing

### Content Quality Assessment

Treat the input `current_issue_*` as **insufficient** if any of the following
apply:

- `current_issue_body` is under 50 words, OR
- A clear technical approach **cannot** be inferred from the issue, OR
- Concrete implementation tasks **cannot** be reasonably derived, OR
- The scope is vague (e.g., "implement X" with no technical detail)

If the input is insufficient:

- **MUST** generate a **minimal draft Pull Request**
- **MUST** rely only on information explicitly present in the issue
- **MUST NOT** invent technical details, repository specifics, or tasks
- **MUST** keep all sections present but concise and high-level
- **MUST** include a Checklist section even if no concrete tasks can be derived
- **MUST** limit checklist items to high-level, non-speculative tasks
  explicitly implied by the issue
- The draft is expected to be refined by a human

## Rules

- **MUST** generate the `pr_title` strictly according to the `Title Format`
  defined in this template.
- **MUST** generate the `pr_body` by rendering the complete `Body Format`
  exactly as specified.
- **MUST** generate the final `pr_title` and the complete `pr_body`
  **BEFORE** producing any Preview, Confirmation prompt, or `STOP_AND_WAIT`
  output.
- **MUST NOT** output content outside of the sections defined in
  `Title Format` and `Body Format`.

## Title Format

- **MUST** use `current_issue_title` verbatim as the title.
- **MUST NOT** attempt to improve or rewrite the title.

## Body Format

### Summary Section

- **MUST** be a single paragraph summarizing the pull request intent.
- **MUST** be concise and derived from the issue context.
- **MUST NOT** include implementation details or technical specifics.

```markdown
## Summary

{one_paragraph_summary}
```

### Context Section

- **MUST** treat the GitHub issue (`current_issue_title`, `current_issue_body`)
  as the **sole source of truth**.
- **MUST** include the issue title.
- **MUST** provide concise context derived from the issue body.
- **MUST NOT** add information not present in the issue.

```markdown
## Context

{current_issue_title}

{concise_context_derived_from_issue_body}
```

### Technical Approach Section

- **MUST** include a section describing the inferred implementation strategy.
- **MUST** be based on technical details inferred from the issue.
- **MUST NOT** invent repository-specific details (file paths, components, APIs).
- **MUST** focus on the overall technical strategy and patterns.

```markdown
## Technical Approach

{inferred_technical_approach}
```

### Implementation Plan Section

- **MUST** describe phases and intent only.
- **MUST NOT** contain specific tasks or checkboxes.
- **MUST** outline the high-level implementation strategy.
- **MUST** focus on approach rather than specific work items.

```markdown
## Implementation Plan

{strategy_and_phases_only_no_tasks}
```

### Checklist Section

- **MUST** render all implementation tasks exclusively in this section.
- **MUST** label tasks as `T001`, `T002`, etc. The non-hyphenated format is
  intentional and distinguishes tasks from spec identifiers.
- **MUST** preserve inferred phase groupings as checklist subheadings when
  applicable.
- **MUST** ensure every inferred task appears exactly once in the checklist.
- **MUST NOT** mark any checklist items as completed.
- **MUST** include the completion subsection for testing and review items.
- If no actionable tasks are implied, the Checklist may contain only the
  Completion subsection.

```markdown
## Checklist

{phase_headings_if_applicable}

- [ ] T001 — {task_description}
- [ ] T002 — {task_description}
- [ ] …

### Completion

- [ ] Tests added/updated
- [ ] Documentation updated or not required
- [ ] Ready for review
```

### Closing Footer

- **MUST** include a `Closes #{issue.number}` footer at the end of the Pull
  Request body.
- **MUST** include `Closes` even for draft pull requests to preserve lifecycle
  linkage.
- **MUST NOT** use other closing keywords (`Fixes`, `Resolves`).

```markdown
---

Closes #{current_issue_number}
```

## Output

After rendering and storing the final `pr_title` and `pr_body`,
the template **MUST** output the following prompt as the **final output**:

```markdown
### Preview

**Title**

> {pr_title}

**Body**

{pr_body}

Do you want to proceed with this draft?

- **"yes"** → Proceed with this draft
- **"edit"** → Revise the title/body
- **"no"** → Abort

<!-- STOP_AND_WAIT -->
```
