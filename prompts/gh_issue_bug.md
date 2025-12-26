---
title: Bug
kind: github-issue
version: 2.2.0
status: active
---

## Preprocessing

If `current_issue_*` is provided and nonempty, treat `prompt` as a refinement
request and evaluate “thin” using `current_issue_body` + `prompt` together; do not
classify as thin based solely on `prompt`.

If `parent_issue_*` parameters are provided, they **MAY** be used as
supporting context only, without inventing requirements or copying large
portions verbatim.

### Content Quality Assessment

Treat input as **thin** if **any** of the following apply, after considering
`prompt` and any provided `parent_issue_*` context:

- Fewer than **30 words**, OR
- No **Steps to Reproduce**, OR
- No **Expected Behavior**, AND the input only states a symptom
  (e.g. “X is broken”, “doesn’t work”, “fails sometimes”)

### Thin Input Interaction

If thin, output exactly as verbatim artifact:

```markdown
**This bug description lacks sufficient detail for analysis.**

Would you like me to ask clarifying questions to enrich it?

- **"yes"** → Start Q&A (2-3 questions, max 5)
- **"no"** → Skip questions and continue

<!-- STOP_AND_WAIT -->
```

### Q&A Process

**MUST ASK** the questions in the following order, omitting any whose answers are
already explicitly provided in the input:

1. What are the exact steps to reproduce the issue?
2. What environment are you seeing this in (`OS`, `App Version`, `Browser`, `Runtime`)?
3. What should happen (expected behavior) versus what actually happens?
4. Does this occur consistently or intermittently?
5. Are there any relevant logs, screenshots, or error messages?

### Extract Key Concepts

- Symptom: what is broken / what fails
- Trigger: what action causes it
- Expected: what should happen instead
- Environment: `OS`/`Version`/`Browser`/`Runtime` if stated

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

- **MUST** describe the observable problem, not the fix.
- **MUST** be written in present tense.
- **MUST** reference either:
  - The trigger (`when …`), OR
  - The affected surface (`in …`).
- **MUST NOT** invent component or file names not present in the input.
- **MUST NOT** start with "Fix", "Bug", or similar prefixes.

### Preferred Patterns

- `{Symptom} when {Trigger}`
- `{Symptom} in {Surface}`

### Examples

- "Crash when saving settings"
- "Login button unclickable in dark mode"
- "Incorrect total shown on invoice preview"

## Body Format

### Context Section

- **MUST** be generated from `prompt` when producing the final bug body.
  This requirement is suspended during Thin Input Interaction (STOP state).
- **MUST NOT** add a separate `Summary` section; the summary is implicit via
  the `Context` section.

```markdown
## Context

{context}
```

### Severity Section

- **MUST** be one of: `Critical`, `High`, `Medium`, `Low`.
- **MUST** default to `Medium` if unclear.

```markdown
## Severity

{severity}
```

### Steps to Reproduce Section

- **MUST** be included.
- If reproduction steps are unknown or not provided, the section **MUST**
  contain `[NEEDS CLARIFICATION]`.

```markdown
## Steps to Reproduce

{steps_to_reproduce}
```

### Expected Behavior Section

- **MUST** be included.
- If expected behavior is unclear or not provided, the section **MUST** contain
  `[NEEDS CLARIFICATION]`.

```markdown
## Expected Behavior

{expected_behavior}
```

### Actual Behavior Section

- **MUST** be included.
- If actual behavior is unclear, it **MUST** contain `[NEEDS CLARIFICATION]`.

```markdown
## Actual Behavior

{actual_behavior}
```

### Environment Section

- **MUST** be included **ONLY** if environment details are explicitly provided;
  otherwise omit the entire section.

```markdown
## Environment

{environment}
```

### Acceptance Criteria Section

- **MUST** be included.
- **MUST** use checkbox format `- [ ]`
- **MUST** label acceptance criterion as `AC-001`, `AC-002`, etc.

```markdown
## Acceptance Criteria

- [ ] AC-001 — Bug is no longer reproducible using the provided steps
- [ ] AC-002 — Regression test added (if non-trivial)
```

### Additional Context Section

- **MUST** be included **ONLY** if additional context is explicitly provided;
  otherwise omit the entire section.

```markdown
## Additional Context

{additional_context}
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

- **"yes"** → Proceed with the draft
- **"edit"** → Revise the title/body
- **"no"** → Abort

<!-- STOP_AND_WAIT -->
```
