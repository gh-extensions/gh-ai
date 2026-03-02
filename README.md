# gh-ai

Your AI-powered copilot for the GitHub CLI. Draft pull requests, plan issue
implementations, review code, debug CI failures, and drop into interactive
coding sessions — without leaving the terminal.

Stop context-switching between your editor, browser, and terminal. `gh ai`
meets you where you already work and handles the tedious parts so you can
focus on shipping.

## Prerequisites

- [Gum](https://github.com/charmbracelet/gum) — macOS: `brew install gum`
- [Bash](https://www.gnu.org/software/bash/) 4.4+ (`bash`) — macOS: `brew install bash`
- [GitHub CLI](https://cli.github.com/) (`gh`) — macOS: `brew install gh`
- [Claude Code](https://docs.anthropic.com/en/docs/build-with-claude/claude-code) (`claude`)

## Installation

```bash
gh extension install gh-extensions/gh-ai
```

## Usage

```bash
gh ai pr create [-d <DESCRIPTION>] [-B <BASE>] [-- GH_PR_CREATE_OPTIONS]
gh ai pr edit [PR_NUMBER] -d <DESCRIPTION> [-- GH_PR_EDIT_OPTIONS]
gh ai pr review [PR_NUMBER] [-d <DESCRIPTION>] [-- GH_PR_REVIEW_OPTIONS]
gh ai pr explain [PR_NUMBER] [--comment | --edit]
gh ai pr chat [PR_NUMBER] [-d <DESCRIPTION>] [-n] [-- AGENT_OPTIONS]
gh ai issue create -d <DESCRIPTION> [-- GH_ISSUE_CREATE_OPTIONS]
gh ai issue edit <ISSUE_NUMBER> -d <DESCRIPTION> [-- GH_ISSUE_EDIT_OPTIONS]
gh ai issue plan <ISSUE_NUMBER> [-d <DESCRIPTION>]
gh ai issue chat <ISSUE_NUMBER> [-d <DESCRIPTION>] [-n] [-- AGENT_OPTIONS]
gh ai run explain <RUN_ID>
gh ai run chat <RUN_ID> [-d <DESCRIPTION>] [-n] [-- AGENT_OPTIONS]
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
gh ai pr explain 42              # print explanation to stdout
gh ai pr explain                 # auto-detect PR from current branch
gh ai pr explain 42 --comment    # post as PR comment
gh ai pr explain 42 --edit       # replace PR description
```

Opens an interactive agent session with PR context. Sessions are persistent —
running the same command again resumes the previous session. Use `--new-session`
(or `-n`) to start fresh.

```bash
gh ai pr chat 42
gh ai pr chat -d "focus on the security changes"
gh ai pr chat 42 -n # start a new session
gh ai pr chat 42 -- --model sonnet
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

Pipe to an AI agent to implement:

```bash
gh ai issue plan 42 | claude
gh ai issue plan 42 | jules new
gh ai issue plan 42 | gh agent-task create --body -
```

Full branch + PR workflow:

```bash
gh issue develop 42 --checkout && \
  git commit --allow-empty -m "chore: start work on #42" && \
  gh ai issue plan 42 | gh pr create --body -
```

Opens an interactive agent session with issue context. Sessions are persistent —
running the same command again resumes the previous session. Use `--new-session`
(or `-n`) to start fresh.

```bash
gh ai issue chat 42
gh ai issue chat 42 -d "focus on the auth module"
gh ai issue chat 42 -n                # start a new session
gh ai issue chat 42 -- --model sonnet
```

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
gh ai run chat 123456 -- --model sonnet
```

## Session Management

Chat commands automatically persist sessions per resource. The first
invocation creates a new session with a dedicated worktree and a local branch
named after the resource (e.g. `issue-42`, `pr-42`); subsequent runs resume
it. Session state is stored in the repository at:

```text
<repo-root>/.claude/sessions/<session-uuid>/state.json
```

Use `--new-session` (or `-n`) to discard the existing session and start fresh.
Session management is skipped when you pass your own `--resume`, `--session-id`,
`--continue`, or `-c` after `--`.

When a session ends, the worktree is automatically removed. If the worktree
has uncommitted changes, they are auto-stashed before removal so nothing is
lost. Recover them with `git stash list` and look for entries prefixed with
`gh-ai: auto-stash worktree`. Unpushed commits remain in the branch reflog.

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
`extras/gh_fzf.sh` in your shell config to register `gh-ai` keybinds via
`GH_FZF_*_OPTS`.

```bash
source "$HOME/.local/share/gh/extensions/gh-ai/extras/gh_fzf.sh"
```

| Context        | Key     | Action                                           |
| -------------- | ------- | ------------------------------------------------ |
| `gh-fzf issue` | `alt-P` | Generate AI plan for the selected issue          |
| `gh-fzf issue` | `alt-C` | Chat about the selected issue with AI            |
| `gh-fzf pr`    | `alt-E` | Explain the selected PR                          |
| `gh-fzf pr`    | `alt-A` | Approve the selected PR via AI review            |
| `gh-fzf pr`    | `alt-N` | Request changes on the selected PR via AI review |
| `gh-fzf pr`    | `alt-C` | Chat about the selected PR with AI               |
| `gh-fzf run`   | `alt-E` | Explain the selected workflow run failure        |
| `gh-fzf run`   | `alt-C` | Chat about the selected workflow run with AI     |

## See Also

- [git-ai](https://github.com/git-extensions/git-ai) — AI-powered commit messages for git (`git ai commit`)
- [gh-fzf](https://github.com/gh-extensions/gh-fzf) — Fuzzy finder for GitHub CLI

## License

[MIT](LICENSE) — Copyright (c) 2025 gh-extensions

<!-- markdownlint-disable-file MD013 -->
