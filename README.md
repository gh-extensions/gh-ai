# gh-ai

Your AI-powered copilot for the GitHub CLI. Draft pull requests, plan issue
implementations, review code, debug CI failures, and drop into interactive
coding sessions — without leaving the terminal.

Stop context-switching between your editor, browser, and terminal. `gh ai`
meets you where you already work and handles the tedious parts so you can
focus on shipping.

## Requirements

- [GitHub CLI](https://cli.github.com/) (`gh`)
- [Bash](https://www.gnu.org/software/bash/) 4.4+ (`bash`)
- [jq](https://jqlang.github.io/jq/) (`jq`)
- [Claude Code](https://docs.anthropic.com/en/docs/build-with-claude/claude-code) (`claude`)
- [Gum](https://github.com/charmbracelet/gum) (`gum`)

**macOS (Homebrew):**

```bash
brew install gh bash jq gum
```

**Nix:**

```bash
nix profile install nixpkgs#gh nixpkgs#bash nixpkgs#jq nixpkgs#gum
```

Install `claude` separately: [Claude Code installation guide](https://docs.anthropic.com/en/docs/claude-code/setup)

## Installation

```bash
gh extension install gh-extensions/gh-ai --pin v1.2.3  # recommended: pin to a stable release
gh extension install gh-extensions/gh-ai                # installs from main (unstable)
```

## Usage

```bash
gh ai pr create [-d <DESCRIPTION>] [-B <BASE>] [-- GH_PR_CREATE_OPTIONS]
gh ai pr edit [PR_NUMBER] -d <DESCRIPTION> [-- GH_PR_EDIT_OPTIONS]
gh ai pr review [PR_NUMBER] [-d <DESCRIPTION>] [-- GH_PR_REVIEW_OPTIONS]
gh ai pr explain [PR_NUMBER]
gh ai pr comment [PR_NUMBER] -d <DESCRIPTION> [-- GH_PR_COMMENT_OPTIONS]
gh ai pr chat [PR_NUMBER] [-d <DESCRIPTION>] [-n]
gh ai issue create -d <DESCRIPTION> [-- GH_ISSUE_CREATE_OPTIONS]
gh ai issue edit <ISSUE_NUMBER> -d <DESCRIPTION> [-- GH_ISSUE_EDIT_OPTIONS]
gh ai issue comment <ISSUE_NUMBER> -d <DESCRIPTION> [-- GH_ISSUE_COMMENT_OPTIONS]
gh ai issue plan <ISSUE_NUMBER> [-d <DESCRIPTION>]
gh ai issue chat <ISSUE_NUMBER> [-d <DESCRIPTION>] [-n]
gh ai run explain <RUN_ID>
gh ai run chat <RUN_ID> [-d <DESCRIPTION>] [-n]
```

### Pull Request

Creates a pull request with an AI-generated title and description.

```bash
gh ai pr create
gh ai pr create -B develop -- --draft
gh ai pr create -d "focus on the security changes"
```

Edits an existing pull request with AI-generated updates based on a description
of what to change.

```bash
gh ai pr edit 42 -d "add testing section"
gh ai pr edit 42 -d "fix summary" -- --add-label bug
gh ai pr edit -d "improve description"   # auto-detect PR from current branch
```

Reviews a pull request with AI-generated feedback. Use `-d`/`--description`
to provide extra context or focus areas that guide the AI review.

```bash
gh ai pr review 42
gh ai pr review 42 -- --approve
gh ai pr review -d "focus on security"
gh ai pr review 42 -d "check error handling" -- --comment
gh ai pr review # auto-detects PR for the current branch
```

Explains a pull request in plain language.

```bash
gh ai pr explain 42
gh ai pr explain                              # auto-detect PR from current branch
gh ai pr explain 42 | gh pr comment 42 --body -   # post as PR comment
gh ai pr explain 42 | gh pr edit 42 --body -      # replace PR description
```

Opens an interactive agent session with PR context. Sessions are persistent —
running the same command again resumes the previous session. Use `--new-session`
(or `-n`) to start fresh.

```bash
gh ai pr chat 42
gh ai pr chat -d "focus on the security changes"
gh ai pr chat 42 -n # start a new session
```

### Issue

Creates a structured GitHub issue from a brief description.

```bash
gh ai issue create -d "Login page crashes with special chars"
gh ai issue create -d "Login crash" -- --label bug --assignee @me
some_command 2>&1 | gh ai issue create -d "Command X fails" # pipe error context
```

Edits an existing issue with AI-generated updates based on a description of
what to change.

```bash
gh ai issue edit 42 -d "add acceptance criteria"
gh ai issue edit 42 -d "fix typos and improve clarity"
gh ai issue edit 42 -d "rephrase as a bug report" -- --add-label bug
```

Generates an AI implementation plan from an issue and prints it to stdout.
Use `-d`/`--description` to provide extra context or constraints that guide
the AI when writing the plan.

```bash
gh ai issue plan 42
gh ai issue plan 42 -d "focus on the auth module"
gh ai issue plan 42 | pbcopy
```

Opens an interactive agent session with issue context. Sessions are persistent —
running the same command again resumes the previous session. Use `--new-session`
(or `-n`) to start fresh.

```bash
gh ai issue chat 42
gh ai issue chat 42 -d "focus on the auth module"
gh ai issue chat 42 -n                # start a new session
```

### Slash Commands

Slash command equivalents for issue workflows, usable directly inside a Claude
Code session. Each command fetches live issue data, generates a draft, and waits
for confirmation before executing.

```
/gh:issue:comment <issue-number> [what to say]
/gh:issue:edit    <issue-number> [what to change]
/gh:issue:plan    <issue-number> [focus area]
```

All three commands follow a **draft → iterate → confirm → execute** workflow:
generate a draft, show it to the user, accept revision requests, and only run
the `gh` CLI command once the user confirms.

**Post a comment on an issue:**

```
/gh:issue:comment 42 ask for clarification on the acceptance criteria
/gh:issue:comment 42 summarize the discussion so far
```

**Edit an issue title and body:**

```
/gh:issue:edit 42 add a definition of done section
/gh:issue:edit 42 rewrite the description as a bug report
```

**Generate an implementation plan and post it as a comment:**

```
/gh:issue:plan 42
/gh:issue:plan 42 focus on the auth module
```

> These are Claude Code skill equivalents to `gh ai issue comment`,
> `gh ai issue edit`, and `gh ai issue plan`.

Slash command equivalents for pull request workflows:

```
/gh:pr:comment <pr-number> [what to say]
/gh:pr:edit    <pr-number> [what to change]
/gh:pr:review  <pr-number> [approve|request-changes|comment] [focus area]
```

**Post a comment on a pull request:**

```
/gh:pr:comment 67 ask about the failing CI check
/gh:pr:comment 67 summarize the changes in this PR
```

**Edit a pull request title and body:**

```
/gh:pr:edit 67 add a testing section
/gh:pr:edit 67 rewrite the description to include risk level
```

**Review a pull request:**

```
/gh:pr:review 67
/gh:pr:review 67 approve
/gh:pr:review 67 request-changes focus on error handling
/gh:pr:review 67 comment check the auth module
```

> These are Claude Code skill equivalents to `gh ai pr comment`,
> `gh ai pr edit`, and `gh ai pr review`.

### Run

Analyzes a GitHub Actions workflow run and explains what happened.

```bash
gh ai run explain 123456 # uses --log-failed for failed runs, --log otherwise
```

Opens an interactive agent session with workflow run context. Sessions are
persistent — running the same command again resumes the previous session.
Use `--new-session` (or `-n`) to start fresh.

```bash
gh ai run chat 123456
gh ai run chat 123456 -d "focus on test failures"
gh ai run chat 123456 -n                # start a new session
```

## Recipes

**Pipe an issue plan directly into an AI agent**

```bash
gh ai issue plan 42 | claude  # or: jules new, gh agent-task create -F -
```

**Start work on an issue, generate a plan, and open a draft PR in one command**

Check out a development branch for the issue, record an empty commit to mark the
start of work, then pipe the AI-generated implementation plan directly into a new
pull request.

```bash
gh issue develop 42 --checkout && \
  git commit --allow-empty -m "chore: start work on #42" && git push && \
  gh ai issue plan 42 | gh pr create --title "Implementation plan for #42" -F -
```

**Open a chat session inside an isolated worktree with [gh-worktree](https://github.com/gh-extensions/gh-worktree)**

[gh-worktree](https://github.com/gh-extensions/gh-worktree) creates a dedicated git worktree for the
resource, then runs a command inside it. Combine it with `gh ai` to get a
chat session that starts in the correct branch with no impact on your working tree.

```bash
gh worktree pr 42 -- gh ai pr chat 42
gh worktree issue 42 -- gh ai issue chat 42
gh worktree run 12345678 -- gh ai run chat 12345678
```

Inside tmux, open the session in a new window so your current work is not interrupted:

```bash
tmux new-window -n "pull-42" "gh worktree pr 42 -- gh ai pr chat 42"
tmux new-window -n "issue-42" "gh worktree issue 42 -- gh ai issue chat 42"
```

**Start a dedicated tmux session for a PR or issue**

Create a named tmux session in the background, then attach to it. Useful when you want a fully isolated terminal session you can detach from and return to later.

```bash
gh worktree pr 42 --keep -- tmux new-session -d -s "pull-42" "gh ai pr chat 42" && tmux attach -t "pull-42"
gh worktree issue 42 --keep -- tmux new-session -d -s "issue-42" "gh ai issue chat 42" && tmux attach -t "issue-42"
gh worktree run 123 --keep -- tmux new-session -d -s "run-123" "gh ai run chat 123" && tmux attach -t "run-123"
```

**Consolidate Dependabot PRs into one tracked issue and implement with an AI agent**

Pipe the list of open Dependabot PRs into `gh ai issue create` so the AI names
each PR in the issue body, then hand off the implementation plan to an AI agent.

```bash
# Pipe the plan to any agent: jules new, gh agent-task create -F -, claude, etc.
gh pr list --search "author:app/dependabot is:pr" --json number,title \
  | gh ai issue create -d "Your task is to consolidate Dependabot pull requests." \
  | xargs -I{} sh -c 'gh ai issue plan "{}" | jules new'
```

## Session Management

Chat commands automatically persist sessions per resource. The first
invocation creates a new session; subsequent runs resume it. Session state
is stored in the current worktree at:

```text
<worktree-root>/.github/sessions/<name>/   (e.g. pull-42/, issue-42/, run-123/)
  session.id   — Claude session UUID used to resume the conversation
```

When working inside a linked worktree (e.g. created by `gh worktree`),
sessions are scoped to that worktree — not the main repository root.

Use `--new-session` (or `-n`) to discard the existing session and start fresh.

## Configuration

Override the AI agent and model via `gh config`.

| Key              | Default  | Description                            |
| ---------------- | -------- | -------------------------------------- |
| `ai.agent`       | `claude` | Agent binary (used by all commands)    |
| `ai.model`       | `haiku`  | Model for all commands (fallback)      |
| `ai.pr.model`    |          | Model override for `pr` subcommands    |
| `ai.issue.model` |          | Model override for `issue` subcommands |
| `ai.run.model`   |          | Model override for `run` subcommands   |

Per-command keys take priority over `ai.model`.

```bash
# Set the default model
gh config set ai.model haiku

# Use a stronger model for PRs
gh config set ai.pr.model sonnet

# Use a different agent binary
gh config set ai.agent claude
```

> **Note:** `gh config set` will print a warning for keys it doesn't
> recognize (e.g. `'ai.pr.model' is not a known configuration key`).
> This is expected — the values are still saved and used by the extension.

## Integrations

### gh-fzf

[gh-fzf](https://github.com/gh-extensions/gh-fzf) is a GitHub CLI extension
that wraps `gh` commands in an interactive fuzzy finder. Source
`extras/gh_fzf.sh` in your shell config to register `gh ai` keybinds via
`GH_FZF_*_OPTS`.

```bash
source "$HOME/.local/share/gh/extensions/gh-ai/extras/gh_fzf.sh"
```

| Context        | Key     | Action                                           |
| -------------- | ------- | ------------------------------------------------ |
| `gh-fzf issue` | `alt-P` | Generate AI plan for the selected issue          |
| `gh-fzf issue` | `alt-C` | Chat about the selected issue with AI            |
| `gh-fzf pr`    | `alt-E` | Explain the selected PR                          |
| `gh-fzf pr`    | `alt-R` | Request changes on the selected PR via AI review |
| `gh-fzf pr`    | `alt-C` | Chat about the selected PR with AI               |
| `gh-fzf run`   | `alt-E` | Explain the selected workflow run failure        |
| `gh-fzf run`   | `alt-C` | Chat about the selected workflow run with AI     |

When inside tmux, chat bindings (`alt-C`) automatically open in a new tmux
window so fzf stays interactive. Set `GH_AI_FZF_TMUX=0` to disable this
and always run inline.

## See Also

- [gh-worktree](https://github.com/gh-extensions/gh-worktree) — Isolated git worktrees for PRs, issues, and workflow runs
- [git-ai](https://github.com/git-extensions/git-ai) — AI-powered commit messages for git (`git ai commit`)
- [gh-fzf](https://github.com/gh-extensions/gh-fzf) — Fuzzy finder for GitHub CLI

## License

[MIT](LICENSE) — Copyright (c) 2025 gh-extensions

<!-- markdownlint-disable-file MD013 MD036 -->
