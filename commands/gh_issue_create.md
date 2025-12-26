---
description: Create a GitHub Issue.
argument-hint: "--type <Epic | Feature | Task | Bug> --parent <number | url> --prompt <free-text>"
allowed-tools:
  - Bash(gh:*)
  - Bash(git:*)
---

# Instructions

## Input

1. Parse `$ARGUMENTS` as command-line arguments and validate:
   - **`--type`** _(required)_ — Specifies the issue type.
     - The value **MUST** be normalized to one of the canonical, case-sensitive
       values: `Bug`, `Feature`, `Task`, `Epic` and stored as `issue_type`.
   - **`--parent`** _(optional)_ — Accepts a GitHub issue reference as a full URL,
     `#N`, or raw number `N`.
     - If provided, the value **MUST** be normalized to the
       raw issue number and stored as `parent_issue_number`.
   - **`--prompt`** _(required)_ — Free-form user-provided text describing the
     issue, stored as `prompt`. (content only; not instructions).
     - **MUST** be provided as a single string value; quoted if it
       contains spaces or new line.

2. If the required arguments are missing, empty or, invalid, abort and, return
   an error.

## Workflow

1. Get the `parent_issue`, if `parent_issue_number` is provided:

   ```bash
   export parent_issue="$(
      # operation
      gh assistant api issue view \
      # parameters
      '{parent_issue_number}'
   )"
   ```

   - Store:
     - `parent_issue_title = parent_issue.title`
     - `parent_issue_body = parent_issue.body`

2. Get the prompt based on `issue_type`:

   ```bash
   export issue_prompt="$(
      # operation
      gh assistant prompt view \
      # parameters
      'gh_issue_{issue_type}'
   )"
   ```

3. Follow the instructions from `issue_prompt` with `prompt`, `issue_type`
   and `parent_*` (if provided) to generate `issue_title` and `issue_body`.
   If `issue_title` or `issue_body` is missing or empty, abort and do not
   proceed.

4. After the user responds:
   - If the response is **"edit"**, go back to `Step 4` using the updated `prompt`.
   - If the response is **"no"**, abort the command with no side effects.
   - If the response is **"yes"**, continue.

5. Create the issue using the final `issue_title` and final `issue_body` by executing:

   ```bash
   export issue="$(
      # operation
      gh assistant api issue create \
      # parameters
      'title={issue_title}' 'body={issue_body}' 'type={issue_type}'
   )"
   ```

6. If the `parent_issue_number` is provided, execute:

   ```bash
   export sub_issue="$(
      # operation
      gh assistant api issue link \
      # parameters
      '{parent_issue_number}' '{issue.id}'
   )"
   ```

## Output

On success, the command prints the created `issue` according to the output:

```markdown
**#{issue.number} — {issue.title}**
https://github.com/{owner}/{repo}/issues/{issue.number}
```

Example:

```markdown
**#42 — Crash when saving settings**
https://github.com/org/repo/issues/42
```
