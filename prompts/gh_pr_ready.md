---
title: Pull Request Ready
kind: github-pull-request
version: 0.1.0
status: active
---

## Preprocessing

Analyze the `pr_diff` to understand what changed:

- Identify files added, modified, or deleted.
- Determine the nature of changes (feature, fix, refactor, etc.).
- Extract the affected module, component, or area for scope.
- Assess risk level based on scope and criticality.

### Extract Key Concepts

- Type: what kind of change (feat, fix, docs, etc.)
- Scope: which module or component is affected
- Summary: what the change accomplishes
- Impact: breaking changes, performance, security implications

## Rules

- **MUST** generate the `pr_title` strictly according to the `Title Format`
  defined in this template.
- **MUST** generate the `pr_body` by rendering the complete `Body Format`
  exactly as specified.
- **MUST** generate the final `pr_title` and the complete `pr_body`
  **BEFORE** producing any output.
- **MUST NOT** output content outside of the sections defined in
  `Title Format` and `Body Format`.
- **MUST NOT** include preamble, explanation, or meta-commentary.
- **MUST** use valid GitHub-flavored Markdown (GFM).
- **MUST** conform to `markdownlint` rules.
- **MUST** reference code locations as `file.ext:line` or `file.ext:line1-line2`.

## Title Format

- **MUST** be maximum 72 characters.
- **MUST** use imperative mood (e.g., "Add", not "Added" or "Adds").
- **MUST** be a concise summary of the change.
- **MUST NOT** end with a period.

## Body Format

### Context Section

- **MUST** explain what problem the PR solves.
- **MUST** explain why the change is needed.
- **MUST** be 1-2 sentences.

```markdown
## Context / Problem Statement

{problem_description_and_rationale}
```

### Summary Section

- **MUST** provide a brief overview of what changed.
- **MUST** describe the high-level approach taken.
- **MUST NOT** include implementation details.

```markdown
## High-Level Summary

{brief_overview_of_changes}
```

### Risk Level Section

- **MUST** check exactly one option.
- **MUST** consider scope of change, criticality of affected code, data integrity.

```markdown
## Risk Level

- [ ] Low (docs, tests, internal refactor)
- [ ] Medium (behavior change, non-critical path)
- [ ] High (core logic, data integrity, security, perf-critical)
```

### Technical Breakdown Section

- **MUST** describe how the code behaves after this change.
- **MUST** explain key tradeoffs and patterns used.
- **MUST** list alternatives considered and why they were rejected.
- **MUST** note implicit assumptions and edge conditions.
- **MUST** write "N/A" for subsections that do not apply.

```markdown
## Detailed Technical Breakdown

### Behavior & Execution Flow

{how_code_behaves_after_change}

### Design & Architectural Decisions

{key_tradeoffs_and_patterns}

### Alternatives Considered

{other_approaches_and_why_rejected}

### Assumptions & Edge Cases

{implicit_assumptions_and_edge_conditions}
```

### Testing Section

- **MUST** check applicable items.
- **MUST** be specific about test locations and verification steps.
- **MUST** replace placeholders with actual values from the diff.

```markdown
## Testing & Validation

- [ ] **Unit Tests:** Added coverage in `{test_file_path}`
- [ ] **Integration Tests:** Verifies {flow_description}
- [ ] **Manual Verification:**
  1. {verification_step_1}
  2. {verification_step_2}
  3. {verification_step_3}
```

### Impact Section

- **MUST** answer each item concisely.
- **MUST** be explicit about breaking changes.
- **MUST** write "N/A" or "None" for items that do not apply.

```markdown
## Impact Assessment

- **Breaking Changes:** {yes_or_no_with_details}
- **Performance:** {improved_regressed_or_no_change}
- **Security:** {auth_data_handling_trust_boundaries}
- **Observability:** {metrics_logs_alerts}
```

### Rollout Section

- **MUST** check applicable items.
- **MUST** note any special deployment requirements.

```markdown
## Rollout & Deployment

- [ ] **Migrations:** {database_migrations_required}
- [ ] **Feature Flags:** {is_behind_flag}
- [ ] **Dependencies:** {new_env_vars_secrets_libraries}
```

### Post-Merge Section

- **MUST** include follow-up tasks or known limitations.
- **MUST** include monitoring expectations.
- **MUST** write "None" if no post-merge notes apply.

```markdown
## Post-Merge Notes

{follow_up_tasks_limitations_monitoring}
```

### Checklist Section

- **MUST** include all checklist items.
- **MUST NOT** mark any items as completed.

```markdown
## Checklist

- [ ] Code follows project style (fmt/lint passed)
- [ ] Self-review performed
- [ ] Documentation updated
- [ ] Comments added for complex logic
```

## Output

The template **MUST** output the following as the **final output**:

```markdown
---PR_START---
# {pr_title}

{pr_body}
---PR_END---
```
