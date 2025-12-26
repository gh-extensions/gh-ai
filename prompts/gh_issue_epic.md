---
title: Epic
kind: github-issue
version: 2.2.0
status: active
---

- Epics are issues that have sub-issues (leafs).
- Epics keep content brief and high-level.

## Preprocessing

If `current_issue_*` is provided and nonempty, treat `prompt` as a refinement
request and evaluate “thin” using `current_issue_body` + `prompt` together; do not
classify as thin based solely on `prompt`.

### Content Quality Assessment

Treat input as **thin** if **any** of the following apply, after considering
`prompt` does not clearly describe a high-level initiative (e.g. it is too
short, vague, or lacks of identifiable outcome or scope).

## Thin Input Interaction

If thin, output exactly as:

```markdown
**This epic description lacks a sufficient detail for analysis.**

**Can you briefly describe the goal and scope?**

<!-- STOP_AND_WAIT -->
```

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

- **MUST** describe a high-level initiative or theme.
- **MUST** remain implementation-agnostic.
- **MUST NOT** reference specific tasks, components, or timelines.
- **MUST** be concise and readable as a road-map item.

### Preferred Patterns

- `{Domain}: {Outcome}`
- `{Outcome} rollout`
- `{Theme} initiative`

### Examples

- "Payments: subscription management rollout"
- "Observability: unified logging and tracing"
- "Mobile offline mode initiative"

## Body Format

### Overview Section

- **MUST** be a single paragraph of 2–3 sentences.

```markdown
## Overview

{overview}
```

### Scope Section

- **MUST** be a single top-level bulleted list using `-`.
- **MUST NOT** contain nested bullet lists.
- Each scope bullet **SHOULD** be phrased as a user or system outcome, not an
  activity.

```markdown
## Scope

{scope}
```

### Out of Scope Section

- **MUST** be included **ONLY** if explicitly stated; otherwise omit the entire
  section.
- **MUST** be a single top-level bulleted list using `-`.
- **MUST** NOT contain nested bullet lists.

```markdown
## Out of Scope

{out_of_scope}
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
