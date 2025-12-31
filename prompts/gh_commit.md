---
title: Message
kind: git-commit
version: 0.1.0
status: active
---

## Preprocessing

Analyze the `staged_diff` to understand what changed:

- Identify files added, modified, or deleted.
- Determine the nature of changes (feature, fix, refactor, etc.).
- Extract the affected module, component, or area for scope.

### Extract Key Concepts

- Type: what kind of change (feat, fix, docs, etc.)
- Scope: which module or component is affected
- Description: what the change accomplishes
- Rationale: why the change was made

## Rules

- **MUST** output ONLY the formatted commit message between markers.
- **MUST NOT** include preamble, explanation, thinking, or meta-commentary.
- **MUST NOT** ask questions or request user input.
- **MUST** generate the `commit_subject` strictly according to the
  `Subject Format` defined in this template.
- **MUST** generate the `commit_body` by rendering the complete `Body Format`
  exactly as specified.
- **MAY** generate the `commit_footer` **ONLY** when applicable (breaking
  changes or issue references). Omit entirely otherwise.
- **MUST** follow the Conventional Commits specification.
- **MUST** use `!` after type or scope for breaking changes.

## Subject Format

- **MUST** be maximum 72 characters.
- **MUST** use imperative mood (e.g., "add", not "added" or "adds").
- **MUST** start with lowercase (except proper nouns).
- **MUST NOT** end with a period.
- **MUST NOT** invent component or file names not present in the diff.

```text
<type>[optional scope]: <description>
```

### Commit Types

| Type     | Description                                             |
| -------- | ------------------------------------------------------- |
| feat     | A new feature                                           |
| fix      | A bug fix                                               |
| docs     | Documentation only changes                              |
| style    | Code style changes                                      |
| refactor | Code change that neither fixes a bug nor adds a feature |
| perf     | Performance improvement                                 |
| test     | Adding or updating tests                                |
| build    | Changes to build system or dependencies                 |
| ci       | Changes to CI configuration files and scripts           |
| chore    | Other changes that don't modify src or test files       |

### Scope Guidelines

- **MUST** use lowercase.
- **MUST** keep short (1–2 words).
- **MUST** derive from module, component, or affected area.
- Examples: `auth`, `api`, `cli`, `parser`, `docs`.

### Examples

- `feat(auth): add OAuth2 login support`
- `fix(api): handle null response from upstream`
- `docs: update installation instructions`
- `refactor(cli): simplify argument parsing`

## Body Format

- **MUST** explain what changed and why.
- **MUST NOT** explain how (the diff shows how).
- **MUST** wrap lines at 72 characters.
- **MUST** leave one blank line between subject and body.
- **MUST** use bullet points when listing multiple changes.
- **MUST** reference issues if applicable (e.g., `Fixes #123`).

## Footer Format

- **MUST** omit footer entirely if none of the conditions below apply.
- Include `BREAKING CHANGE: <description>` only if the change breaks
  backward compatibility.
- Include `Fixes #<issue_number>` only if the change closes an issue.
- Include `Refs #<issue_number>` only if the change relates to an issue
  without closing it.

```text
BREAKING CHANGE: <description>
Fixes #<issue_number>
Refs #<issue_number>
```

## Output

The template **MUST** output the following as the **final output** immediately,
without preamble, questions, or confirmation requests:

```text
<!-- COMMIT_START -->
{commit_subject}

{commit_body}

{commit_footer (ONLY if applicable, otherwise omit)}
<!-- COMMIT_END -->
```
