---
description: View a GitHub Pull Request.
argument-hint: "--number <number | url>"
allowed-tools:
  - Bash(gh:*)
  - Bash(git:*)
---

# Instructions

All `gh assistant` commands refer to a **custom GitHub CLI extension** that must
be installed and available in the current environment.

- The assistant **MUST** execute `gh assistant …` commands exactly as written.
- The assistant **MUST NOT** substitute or approximate these commands using
  built-in GitHub CLI commands (e.g. `gh api`, `gh pr view`, etc.).
- If the `gh assistant` extension is not available, the assistant **MUST abort**
  and instruct the user to install it via:

  ```bash
  gh extension install gh-extensions/gh-assistant
  ```

## Input

No additional free-form input is accepted. All behavior is derived from the
referenced issue and repository state.

1. Parse `$ARGUMENTS` as command-line arguments and validate:
   - **`--number`** _(required)_ — Accepts a GitHub Pull Request reference as a
     full URL, `#N`, or raw number `N`.
     - The value **MUST** be normalized to the
       raw issue number and stored as `current_pr_number`.

2. If the required arguments are missing, empty or, invalid, abort and, return
   an error.

## Workflow

1. Get the `current_pr` issue by executing:

   ```bash
   export current_pr="$(
      # operation
      gh assistant api pr view
      # parameters
      '{current_pr_number}'
   )"
   ```

   - Store:
     - `current_pr_title = current_pr.title`
     - `current_pr_body = current_pr.body`

## Output

On success, the command prints the created `current_pr` according to the output:

```markdown
**Title**

> {current_pr_title}

**Body**

{current_pr_body}

https://github.com/{owner}/{repo}/pull/{current_pr_number}
```
