---
description: Edit a GitHub Issue.
argument-hint: "--number <number | url> --parent <number | url> --prompt <free-text>"
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

1. Parse `$ARGUMENTS` as command-line arguments and validate:
   - **`--number`** _(required)_ — Accepts a GitHub issue reference as a full URL,
     `#N`, or raw number `N`.
     - The value **MUST** be normalized to the
       raw issue number and stored as `current_issue_number`.
   - **`--prompt`** _(required)_ — Free-form user-provided text describing the
     issue, stored as `prompt`. (content only; not instructions).
     - **MUST** be provided as a single string value; quoted if it
       contains spaces or new line.

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

2. Get the `parent_issue`, if `parent_issue_number` is provided:

   ```bash
   export parent_issue="$(
      # operation
      gh assitant api issue view \
      # parameters
      '{parent_issue_number}'
   )"
   ```

   - Store:
     - `parent_issue_title = parent_issue.title`
     - `parent_issue_body = parent_issue.body`

3. Get the prompt based on `current_issue_type`:

   ```bash
   export issue_prompt="$(
      # operation
      gh assistant prompt view \
      # parameters
      'gh_issue_{current_issue_type}'
   )"
   ```

4. Follow the instructions from `issue_prompt` with `prompt`, `current_*`
   and `parent_*` (if provided) to generate `issue_title` and `issue_body`.
   If `issue_body` is missing or empty, abort and do not proceed.

5. After the user responds:
   - If the response is **"edit"**, go back to `Step 5` using the updated `prompt`.
   - If the response is **"no"**, abort the command with no side effects.
   - If the response is **"yes"**, continue.

6. Store the `current_issue_type` as `issue_type`.

7. A title change is considered explicit only if the template returns a
   nonempty `issue_title` value that differs from `current_issue_title`.
   Otherwise, set `issue_title = current_issue_title`.

8. Merge the proposed `issue_body` with `current_issue_body`:
   - Parse `issue_body` into sections using `## {Section Name}` headings.
   - Parse `current_issue_body` into sections using `## {Section Name}` headings.
   - For each section defined by the selected template:
     - If `prompt` indicates an explicit change to that section, use the
       section from `issue_body`.
     - Otherwise, if the section exists and is not empty in
       `current_issue_body`, use the section from `current_issue_body`.
     - Otherwise, use the section from `issue_body`.
   - Preserve any optional sections from `current_issue_body` that contain meaningful
     content, unless the user explicitly requests removal.
   - Store the result as `issue_body`.

9. Update the issue using the final `issue_title` and final `issue_body` by executing:

   ```bash
   export issue="$(
      # operation
      gh assistant api issue update \
      # parameters
      '{current_issue_number}' 'title={issue_title}' 'body={issue_body}' 'type={issue_type}'
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
