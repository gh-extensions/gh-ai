---
description: Execute Pull Request checklist tasks interactively.
argument-hint: "--number <number | url> [--yes]"
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
referenced Pull Request and repository state.

1. Parse `$ARGUMENTS` as command-line arguments and validate:
   - **`--number`** _(required)_ — Accepts a GitHub Pull Request reference as a
     full URL, `#N`, or raw number `N`.
     - The value **MUST** be normalized to the raw PR number and stored as
       `current_pr_number`.
   - **`--yes`** _(optional)_ — Skip all interactive prompts. Automatically work
     on all pending tasks and mark them as completed.

2. If required arguments are missing, empty, or invalid, abort and, return an
   error.

## Workflow

1. Fetch Pull Request metadata:

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

2. Extract tasks from the Pull Request:

   ```bash
   export all_tasks="$(
      # operation
      gh assistant pr task list \
      # parameters
      '{current_pr_number}' --filter 'T\d\d\d' --json
   )"
   ```

   - Build `pending_tasks[]` from `all_tasks` where `status == "pending"`.
   - If no tasks exist, print a notice and exit successfully.
   - Display pending tasks:

   ```markdown
   - [ ] T001 — {task_description}
   - [ ] T002 — {task_description}
   - [ ] …
   ```

3. Iterate through `pending_tasks` sequentially.

   For each task:

   If `--yes` is set, proceed directly to implementation (step 4).

   Otherwise, prompt:

   ```markdown
   **{task_id}:** {task_text}

   Do you want to work on this task?

   - **yes** → Work on this task
   - **skip** → Mark as skipped and move to next task
   - **no** → Abort and go to Summary

   <!-- STOP_AND_WAIT -->
   ```

   If skipped, append `{task_id}` to `skipped_tasks[]`.

4. Implement task (max 2 retries):
   - **ANALYZE**
     - Use only Pull Request context and repository state.
     - **MUST NOT** invent files or components.
   - **EXECUTE**
     - Make minimal code changes needed for the task.
   - **VERIFY**
     - Run relevant checks if reasonable.

   If blocked:

   If `--yes` is set, mark as blocked and continue to next task.

   Otherwise, prompt:

   ```markdown
   **Blocked:** {blocker}

   How would you like to proceed?

   - **retry** → Retry and work on this task
   - **skip** → Mark as blocked and move to next task
   - **no** → Abort and go to Summary

   <!-- STOP_AND_WAIT -->
   ```

   If blocked, append `{task_id}` to `blocked_tasks[]`.

5. On successful implementation:

   If `--yes` is set, show changes and proceed directly to marking (step 6):

   ```markdown
   **{task_id}:** {task_text}

   **Changes made:**

   - {summary}
   ```

   Otherwise, prompt:

   ```markdown
   **{task_id}:** {task_text}

   **Changes made:**

   - {summary}

   Mark this task as done in the PR checklist?

   - **yes** → Mark the task as completed
   - **no** → Do not mark the task

   <!-- STOP_AND_WAIT -->
   ```

6. Mark task as completed:

   ```bash
   gh assistant pr task check \
   # parameters
   '{current_pr_number}' '{task_id}'
   ```

7. Summary output:

   ```markdown
   **Progress:** {completed}/{total} tasks complete

   **Completed:**
   {completed_tasks}

   **Remaining:**
   {remaining_tasks}

   **Skipped:**
   {skipped_tasks}

   **Blocked:**
   {blocked_tasks}

   ---

   #{current_pr_number} - {current_pr_title}
   https://github.com/{owner}/{repo}/pull/{current_pr_number}
   ```

   WHERE:
   - `total` — total number of checklist tasks parsed from the Pull Request body
   - `completed_tasks` — all tasks marked [x] in the Pull Request body after updates
   - `completed` — count of completed_tasks
   - `remaining_tasks` — all tasks marked [ ] in the Pull Request body after updates
   - `blocked_tasks` — tasks explicitly blocked during this run
   - `skipped_tasks` — tasks explicitly skipped during this run
