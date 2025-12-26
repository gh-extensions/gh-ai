---
title: Feature
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

- Under 50 words **and** no acceptance criteria; OR
- Vague scope (e.g., "add X" with no boundaries)

### Thin Input Interaction

If thin, output exactly as:

```markdown
**This feature description lacks sufficient detail for analysis.**

Would you like me to ask clarifying questions to enrich it?

- **"yes"** → Start Q&A (3–5 questions, max 7)
- **"no"** → Skip questions and continue

<!-- STOP_AND_WAIT -->
```

### Q&A Process

**MUST ASK** the questions in the following order, omitting any whose answers are
already explicitly provided in the input:

1. Who is the primary user/actor?
2. What is the core goal they want to achieve?
3. What does success look like? (acceptance criteria)
4. Any edge cases or error scenarios?
5. What is explicitly out of scope?
6. Any constraints (performance/security/compliance)?
7. Any relevant links/background?

### Extract Key Concepts

- Actors: who uses it (users/admins/systems)
- Actions: what they want to do
- Data: entities/information involved
- Constraints: boundaries/requirements mentioned

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

- **MUST** describe a user-facing capability.
- **MUST** use an action-oriented phrasing.
- **MUST NOT** include implementation details.
- **MUST NOT** start with "Implement", "Add support for", or similar low-signal
  phrases.

### Preferred Patterns

- `Allow {Actor} to {Action}`
- `Enable {Action}`
- `{Action} for {Surface}`

### Examples

- "Allow admins to export user activity"
- "Enable passwordless login via email link"
- "Bulk invite users from CSV"

## Body Format

### Context Section

- **MUST** always be issue from `prompt`.
- **MUST** be 1–2 sentences (what and why).
- **MUST NOT** include implementation details.

```markdown
## Context

{context}
```

### Nonfunctional Requirements Section

- **MUST** be included **ONLY** if explicitly stated; otherwise omit the entire
  section.
- If included, items **MUST** be labeled `NFR-001`, `NFR-002`, etc.

```markdown
## Non-Functional Requirements

{non_functional_requirements}
```

### Acceptance Criteria Section

- **MUST** use checkbox format `- [ ]`
- **MUST** be verifiable bullets derived from input and `Q&A`.
- **MUST** label acceptance criterion as `AC-001`, `AC-002`, etc.
- **MUST** be expressed in user-observable terms when possible.
- **At least** one acceptance criterion **MUST** be verifiable via UI, API
  response, or system behavior.
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
