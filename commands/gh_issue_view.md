---
description: View a GitHub Issue.
argument-hint: "--number <number | url>"
allowed-tools:
  - Bash(gh:*)
  - Bash(git:*)
---

# Instructions

## Input

No additional free-form input is accepted. All behavior is derived from the
referenced issue and repository state.

1. Parse `$ARGUMENTS` as command-line arguments and validate:
   - **`--number`** _(required)_ — Accepts a GitHub issue reference as a full URL,
     `#N`, or raw number `N`.
     - The value **MUST** be normalized to the
       raw issue number and stored as `current_issue_number`.

2. If the required arguments are missing, empty or, invalid, abort and, return
   an error.

## Workflow

1. Get the `current_issue` issue by executing:

   ```bash
   export current_issue="$(
      # operation
      gh assistant api issue view
      # parameters
      '{current_issue_number}'
   )"
   ```

   - Store:
     - `current_issue_title = current_issue.title`
     - `current_issue_body = current_issue.body`

## Output

On success, the command prints the created `current_issue` according to the output:

```markdown
**Title**

> {current_issue_type}: {current_issue_title}

**Body**

{current_issue_body}

https://github.com/{owner}/{repo}/issues/{current_issue_number}
```
