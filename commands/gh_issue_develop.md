---
description: Develop an existing GitHub Issue.
argument-hint: "--number <number | url>"
allowed-tools:
  - Bash(gh:\*)
  - Bash(git:\*)
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
      gh assistant api issue view \
      # parameters
      '{current_issue_number}'
   )"
   ```

   - Store:
     - `current_issue_title = current_issue.title`
     - `current_issue_body = current_issue.body`

2. Generate the `technical_approach` and the `implementation_plan` by following:
   - **MUST** analyze the `current_issue_body`
   - **MUST** scan the repository only for high-level signals
     (programming language, build system, frameworks, testing tools)
   - **MUST NOT** infer or reference specific files, components, modules,
     directories, or APIs unless they are explicitly mentioned in the issue
   - **MUST** describe the technical approach at an architectural or procedural
     level only, without naming implementation locations

3. Get the prompt:

   ```bash
   export pr_prompt="$(
      # operation
      gh assistant prompt view \
      # parameters
      'gh_pr_draft'
   )"
   ```

4. Follow the instructions from `pr_prompt` with `current_*`,
   `technical_approach`, `implementation_plan` to generate `pr_title`
   and `pr_body`. If `pr_title` or `pr_body` is missing or empty,
   abort and do not proceed.

5. After the user responds:
   - If the response is **"no"**, abort the command with no side effects.
   - If the response is **"yes"**, continue.

6. Assign the user to the issue by executing:

   ```bash
   export current_issue="$(
      # operation
      gh assistant api issue update \
      # parameters
      '{current_issue_number}' 'assignee=@me'
   )"
   ```

7. Bootstrap the Pull Request branch:

   ```bash
   export pr_branch="$(
      # operation
      gh assistant api issue develop \
      # parameters
      '{current_issue_number}'
   )"
   ```

8. Create the Pull Request using the final `pr_title` and final `pr_body` by executing:

   ```bash
   export pr="$(
      # operation
      gh assistant api pr create \
      # parameters
      'title={pr_title}' 'body={pr_body}' 'head={pr_branch}' \
      'base=main' 'draft=true'
   )"

   ```

## Output

On success, the command prints the created `pr` according to the output:

```markdown
**#{pr.number} — {pr.title}**
https://github.com/{owner}/{repo}/pull/{pr.number}
```

Example:

```markdown
**#42 — Crash when saving settings**
https://github.com/org/repo/pull/42
```
