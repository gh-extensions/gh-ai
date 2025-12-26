---
title: Task
kind: github-issue
version: 2.2.0
status: active
---

## Preprocessing

If `current_issue_*` is provided and nonempty, treat `prompt` as a refinement
request and evaluate “thin” using `current_issue_body` + `prompt` together; do not
classify as thin based solely on prompt.

If `parent_issue_*` parameters are provided, they **MAY** be used as
supporting context only, without inventing requirements or copying large
portions verbatim.

### Content Quality Assessment

Treat input as **thin** if **any** of the following apply, after considering
`prompt` and any provided `parent_issue_*` context:

- Under 30 words, OR
- Vague target (e.g., "fix something" without specifying what), OR
- No defined outcome

### Thin Input Interaction

If thin, output exactly as verbatim verbatim artifact:

```markdown
**This task description lacks sufficient detail for analysis.**

Would you like me to ask clarifying questions to enrich it?

- **"yes"** → Start Q&A (1–2 questions, max 3)
- **"no"** → Skip questions and continue

<!-- STOP_AND_WAIT -->
```

### Q&A Process

**MUST ASK** the questions in the following order, omitting any whose answers are
already explicitly provided in the input:

1. What is the specific outcome you want to achieve?
2. What component/system is affected?
3. Any constraints or dependencies?

### Extract Key Concepts

- Target: component/system affected
- Objective: end goal state
- Scope: what is included

## Rules

- **MUST** generate the `issue_title` strictly according to the `Title Format`
  defined in this template.
- **MUST** generate the `issue_body` by rendering the complete `Body Format`
  exactly as specified.
- **MUST** generate the final `issue_title` and the complete `issue_body`
  **BEFORE** producing any Preview, Confirmation prompt, or `STOP_AND_WAIT`
  output (except during Thin Input Interaction).
- **MUST NOT** output content outside of the sections defined in
  `Title Format` and `Body Format`.

## Title Format

- **MUST** be written in imperative form.
- **MUST** describe a concrete unit of work.
- **MUST NOT** be vague or generic (e.g., "Do clean-up", "Misc fixes").
- **MUST NOT** include issue-type prefixes.

### Preferred Verbs

`Add`, `Update`, `Remove`, `Refactor`, `Migrate`, `Optimize`, `Document`, `Rename`

### Preferred Patterns

- `{Verb} {Object}`
- `{Outcome} for {Surface}`

### Examples

- "Refactor request validation"
- "Update onboarding docs for new flow"
- "Remove deprecated auth middleware"

## Body Format

### Context Section

- **MUST** always be generated from `prompt`.
- **MUST** be 1–2 sentences (what and why).
- **MUST NOT** include implementation details.

```markdown
## Context

{context}
```

### Objective Section

- **MUST** be a single clear goal statement.

```markdown
## Objective

{objective}
```

### Acceptance Criteria Section

- **MUST** use checkbox format `- [ ]`
- **MUST** be verifiable bullets derived from input and `Q&A`.
- **MUST** label acceptance criterion as `AC-001`, `AC-002`, etc.
- If criteria are still unclear, the section **MUST** contain `NOT SPECIFIED`.

```markdown
## Acceptance Criteria

- [ ] AC-001 — {verifiable criterion}
- [ ] AC-002 — {verifiable criterion}
- [ ] AC-003 — {verifiable criterion}
```

### Out of Scope Section

- **MUST** be included **ONLY** if explicitly stated; otherwise omit the entire
  section.

```markdown
## Out of Scope

{out_of_scope}
```

### Clarifications Section

- **MUST** be included if and only if a `Q&A` session occurred.

```markdown
## Clarifications

{clarifications}
```

### Closing Footer Section

- **MUST** be included if `parent_issue_number` is provided.

```markdown
---

Relates to #{parent_issue_number}
```

## Output

After rendering and storing the final `issue_title` and `issue_body`,
the template **MUST** output the following prompt as the **final output**:

```markdown
### Preview

**Title**

> {issue_title}

**Body**

{issue_body}

Do you want to proceed with this draft?

- **"yes"** → Proceed with this draft
- **"edit"** → Revise the title/body
- **"no"** → Abort

<!-- STOP_AND_WAIT -->
```
