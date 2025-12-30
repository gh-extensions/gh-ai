---
title: Pull Request Review
kind: github-pull-request-review
version: 0.1.0
status: active
---

## Preprocessing

Analyze the `pr_diff` to understand what changed:

- Identify files added, modified, or deleted.
- Determine the nature of changes (feature, fix, refactor, etc.).
- Assess correctness, safety, and design quality.
- Identify potential bugs, security issues, and performance concerns.

### Review Priorities

**Prioritize:**

- Objective bugs and logic errors
- Security, data-loss, and concurrency issues
- Clear violations of project guidelines
- Performance bottlenecks
- Missing error handling

**Do not flag:**

- Pure style preferences not required by project rules
- Issues linters will catch
- Pre-existing issues not introduced in this diff
- Speculative issues that cannot be validated from the diff alone

## Rules

- **MUST** generate the review by rendering the complete `Body Format`
  exactly as specified.
- **MUST NOT** include preamble, explanation, or meta-commentary.
- **MUST NOT** include sentences such as "Let me review…" or "Here is the
  analysis…".
- **MUST** use valid GitHub-flavored Markdown (GFM).
- **MUST** conform to `markdownlint` rules.
- **MUST** reference code locations as `file.ext:line` or `file.ext:line1-line2`.
- **MUST** omit sections with no findings entirely.
- **MUST** omit the `---` separator that would precede an omitted section.
- **MUST** always include the `Summary & Outcome` section.
- **MUST** quote the exact rule when citing a guideline violation.

## Body Format

### Summary & Outcome Section

- **MUST** always be included.
- **MUST** provide 2-5 bullet points summarizing the change and overall
  impression.
- **MUST** specify exactly one outcome: `Approve`, `Request Changes`, or
  `Comment`.

```markdown
## Summary & Outcome

**Summary:**

- {bullet_point_1}
- {bullet_point_2}
- {bullet_point_3}

**Outcome:** {Approve | Request Changes | Comment}
```

### Outcome Criteria

| Outcome             | When to Use                                                          |
| ------------------- | -------------------------------------------------------------------- |
| **Approve**         | No blocking issues; code is ready to merge                           |
| **Request Changes** | Has High or Medium severity issues that must be fixed before merging |
| **Comment**         | Has suggestions but nothing blocking; informational review           |

### Code Quality Section

- **MUST** only include if findings exist.
- **MUST** review for structure, readability, maintainability, error handling.
- **MUST** provide specific and actionable comments with file references.
- **MUST** focus on changes introduced in this diff.

```markdown
## Code Quality & Best Practices

{specific_actionable_comments_with_file_references}
```

### Potential Issues Section

- **MUST** only include if findings exist.
- **MUST** format each issue with severity, location, details, and suggestion.
- **MUST** only include issues with high confidence.

```markdown
## Potential Issues

**[{severity}] {issue_description}**

- Location: `{file.ext:line}`
- Details: {explanation_of_issue}
- Suggestion: {how_to_fix}
```

### Severity Levels

| Severity   | Description                                           | Blocks Approval? |
| ---------- | ----------------------------------------------------- | ---------------- |
| **High**   | Bugs, security issues, data loss risk                 | Yes              |
| **Medium** | Logic issues, missing edge cases, poor error handling | Yes              |
| **Low**    | Minor improvements, style suggestions                 | No               |

### Tests & Coverage Section

- **MUST** only include if findings exist.
- **MUST** comment on test sufficiency, missing tests for critical paths.
- **MUST** identify edge cases that need coverage.

```markdown
## Tests & Coverage

{test_sufficiency_comments}
```

### Improvements Section

- **MUST** only include if findings exist.
- **MUST** offer incremental, practical suggestions.
- **MUST NOT** overwhelm the author with minor nits.

```markdown
## Improvements & Suggestions

{incremental_practical_suggestions}
```

### Action Items Section

- **MUST** only include if required changes exist.
- **MUST** include checkboxes for High and Medium severity issues.
- **MUST** include advisory notes for optional improvements (no checkbox).

```markdown
## Action Items

**Required Changes:**

- [ ] [{severity}] {issue_description} ({file.ext:line})

**Advisory Notes:**

- Note: {optional_improvement_or_consideration}
```

### Positive Aspects Section

- **SHOULD** include when applicable.
- **MUST** highlight what was done well.

```markdown
## Positive Aspects

{clean_abstractions_solid_tests_good_naming_careful_handling}
```

## Output

The template **MUST** output the following as the **final output**:

```markdown
---REVIEW_START---
{review_body}
---REVIEW_END---
```
