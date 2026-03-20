# gh-claude

Your Claude-powered copilot for the GitHub CLI. Draft pull requests, plan issue
implementations, review code, debug CI failures, and drop into interactive
coding sessions — without leaving the terminal.

Stop context-switching between your editor, browser, and terminal. `gh claude`
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
gh extension install gh-extensions/gh-claude --pin v1.2.3  # recommended: pin to a stable release
gh extension install gh-extensions/gh-claude                # installs from main (unstable)
```

## Usage

```bash
gh claude [CLAUDE_OPTIONS] pr create [-d <DESCRIPTION>] [-B <BASE>] [GH_PR_CREATE_OPTIONS]
gh claude [CLAUDE_OPTIONS] pr edit [PR_NUMBER] -d <DESCRIPTION> [GH_PR_EDIT_OPTIONS]
gh claude [CLAUDE_OPTIONS] pr review [PR_NUMBER] [-d <DESCRIPTION>] [GH_PR_REVIEW_OPTIONS]
gh claude [CLAUDE_OPTIONS] pr explain [PR_NUMBER]
gh claude [CLAUDE_OPTIONS] pr comment [PR_NUMBER] -d <DESCRIPTION> [GH_PR_COMMENT_OPTIONS]
gh claude [CLAUDE_OPTIONS] pr chat [PR_NUMBER] [-d <DESCRIPTION>] [-n]
gh claude [CLAUDE_OPTIONS] issue create -d <DESCRIPTION> [GH_ISSUE_CREATE_OPTIONS]
gh claude [CLAUDE_OPTIONS] issue edit <ISSUE_NUMBER> -d <DESCRIPTION> [GH_ISSUE_EDIT_OPTIONS]
gh claude [CLAUDE_OPTIONS] issue comment <ISSUE_NUMBER> -d <DESCRIPTION> [GH_ISSUE_COMMENT_OPTIONS]
gh claude [CLAUDE_OPTIONS] issue plan <ISSUE_NUMBER> [-d <DESCRIPTION>]
gh claude [CLAUDE_OPTIONS] issue chat <ISSUE_NUMBER> [-d <DESCRIPTION>] [-n]
gh claude [CLAUDE_OPTIONS] run explain <RUN_ID>
gh claude [CLAUDE_OPTIONS] run chat <RUN_ID> [-d <DESCRIPTION>] [-n]
```

`CLAUDE_OPTIONS` are flags forwarded to the `claude` binary (e.g., `--model`,
`--session-id`, `--resume`, `--verbose`, `--allowedTools`, `--permission-mode`).
They are placed **before** the subcommand keyword.

### Pull Request

Creates a pull request with an AI-generated title and description.

```bash
gh claude pr create
gh claude pr create -B develop --draft
gh claude pr create -d "focus on the security changes"
```

Edits an existing pull request with AI-generated updates based on a description
of what to change.

```bash
gh claude pr edit 42 -d "add testing section"
gh claude pr edit 42 -d "fix summary" --add-label bug
gh claude pr edit -d "improve description"   # auto-detect PR from current branch
```

Reviews a pull request with AI-generated feedback. Use `-d`/`--description`
to provide extra context or focus areas that guide the AI review.

```bash
gh claude pr review 42
gh claude pr review 42 --approve
gh claude pr review -d "focus on security"
gh claude pr review 42 -d "check error handling" --comment
gh claude pr review # auto-detects PR for the current branch
```

Explains a pull request in plain language.

```bash
gh claude pr explain 42
gh claude pr explain                              # auto-detect PR from current branch
gh claude pr explain 42 | gh pr comment 42 --body -   # post as PR comment
gh claude pr explain 42 | gh pr edit 42 --body -      # replace PR description
```

Opens an interactive agent session with PR context. Each invocation starts a
new session. Use `--session-id <UUID>` for a reusable named session, or
`--resume <UUID>` to resume a specific session by UUID. Set
`GH_CLAUDE_DEFAULT_SESSION_ID` to always use the same session with
auto-resume.

```bash
gh claude pr chat 42
gh claude pr chat -d "focus on the security changes"
gh claude --session-id <UUID> pr chat 42       # named session (reuses on next call)
gh claude --resume <UUID> pr chat 42           # resume by UUID
GH_CLAUDE_DEFAULT_SESSION_ID=<UUID> gh claude pr chat 42   # auto-resume default session
```

### Issue

Creates a structured GitHub issue from a brief description.

```bash
gh claude issue create -d "Login page crashes with special chars"
gh claude issue create -d "Login crash" --label bug --assignee @me
some_command 2>&1 | gh claude issue create -d "Command X fails" # pipe error context
```

Edits an existing issue with AI-generated updates based on a description of
what to change.

```bash
gh claude issue edit 42 -d "add acceptance criteria"
gh claude issue edit 42 -d "fix typos and improve clarity"
gh claude issue edit 42 -d "rephrase as a bug report" --add-label bug
```

Generates an AI implementation plan from an issue and prints it to stdout.
Use `-d`/`--description` to provide extra context or constraints that guide
the AI when writing the plan.

```bash
gh claude issue plan 42
gh claude issue plan 42 -d "focus on the auth module"
gh claude issue plan 42 | pbcopy
```

Opens an interactive agent session with issue context. Each invocation starts a
new session. Use `--session-id <UUID>` for a reusable named session, or
`--resume <UUID>` to resume a specific session by UUID. Set
`GH_CLAUDE_DEFAULT_SESSION_ID` to always use the same session with
auto-resume.

```bash
gh claude issue chat 42
gh claude issue chat 42 -d "focus on the auth module"
gh claude --session-id <UUID> issue chat 42        # named session (reuses on next call)
gh claude --resume <UUID> issue chat 42            # resume by UUID
GH_CLAUDE_DEFAULT_SESSION_ID=<UUID> gh claude issue chat 42  # auto-resume default session
```

### Run

Analyzes a GitHub Actions workflow run and explains what happened.

```bash
gh claude run explain 123456 # uses --log-failed for failed runs, --log otherwise
```

Opens an interactive agent session with workflow run context. Each invocation
starts a new session. Use `--session-id <UUID>` for a reusable named
session, or `--resume <UUID>` to resume a specific session by UUID. Set
`GH_CLAUDE_DEFAULT_SESSION_ID` to always use the same session with
auto-resume.

```bash
gh claude run chat 123456
gh claude run chat 123456 -d "focus on test failures"
gh claude --session-id <UUID> run chat 123456    # named session (reuses on next call)
gh claude --resume <UUID> run chat 123456        # resume by UUID
GH_CLAUDE_DEFAULT_SESSION_ID=<UUID> gh claude run chat 123456  # auto-resume default session
```

## Recipes

**Pipe an issue plan directly into an AI agent**

```bash
gh claude issue plan 42 | claude  # or: jules new, gh agent-task create -F -
```

**Start work on an issue, generate a plan, and open a draft PR in one command**

Check out a development branch for the issue, record an empty commit to mark the
start of work, then pipe the AI-generated implementation plan directly into a new
pull request.

```bash
gh issue develop 42 --checkout && \
  git commit --allow-empty -m "chore: start work on #42" && git push && \
  gh claude issue plan 42 | gh pr create --title "Implementation plan for #42" -F -
```

**Open a chat session inside an isolated worktree with [gh-worktree](https://github.com/gh-extensions/gh-worktree)**

[gh-worktree](https://github.com/gh-extensions/gh-worktree) creates a dedicated git worktree for the
resource, then runs a command inside it. Combine it with `gh claude` to get a
chat session that starts in the correct branch with no impact on your working tree.

```bash
gh worktree pr 42 -- gh claude pr chat 42
gh worktree issue 42 -- gh claude issue chat 42
gh worktree run 12345678 -- gh claude run chat 12345678
```

Inside tmux, open the session in a new window so your current work is not interrupted:

```bash
tmux new-window -n "pull-42" "gh worktree pr 42 -- gh claude pr chat 42"
tmux new-window -n "issue-42" "gh worktree issue 42 -- gh claude issue chat 42"
```

**Start a dedicated tmux session for a PR or issue**

Create a named tmux session in the background, then attach to it. Useful when you want a fully isolated terminal session you can detach from and return to later.

```bash
gh worktree pr 42 --keep -- tmux new-session -d -s "pull-42" "gh claude pr chat 42" && tmux attach -t "pull-42"
gh worktree issue 42 --keep -- tmux new-session -d -s "issue-42" "gh claude issue chat 42" && tmux attach -t "issue-42"
gh worktree run 123 --keep -- tmux new-session -d -s "run-123" "gh claude run chat 123" && tmux attach -t "run-123"
```

**Consolidate Dependabot PRs into one tracked issue and implement with an AI agent**

Pipe the list of open Dependabot PRs into `gh claude issue create` so the AI names
each PR in the issue body, then hand off the implementation plan to an AI agent.

```bash
# Pipe the plan to any agent: jules new, gh agent-task create -F -, claude, etc.
gh pr list --search "author:app/dependabot is:pr" --json number,title \
  | gh claude issue create -d "Your task is to consolidate Dependabot pull requests." \
  | xargs -I{} sh -c 'gh claude issue plan "{}" | jules new'
```

## Session Management

Session state is stored under the XDG state directory:

```text
${XDG_STATE_HOME:-~/.local/state}/gh/claude/sessions/<session-id>/
  chat.id   — resource identifier (e.g. pull-42, issue-7, run-123456)
```

**Four modes:**

| Invocation | Behaviour |
|---|---|
| `gh claude pr chat 42` | Auto-generate UUID, new session, context rendered |
| `gh claude --session-id <UUID> pr chat 42` | Named session — creates on first call, resumes (no context re-render) on subsequent calls |
| `gh claude --resume <UUID> pr chat 42` | Resume a specific session by UUID; errors if not found or resource mismatch |
| `GH_CLAUDE_DEFAULT_SESSION_ID=<UUID> gh claude pr chat 42` | Default session — auto-resumes if exists, creates if not |

```bash
# Named session: context rendered first time, skipped on reuse
gh claude --session-id <UUID> pr chat 42
gh claude --session-id <UUID> pr chat 42   # resumes, no re-fetch

# Resume by UUID
gh claude --resume abc123-... pr chat 42

# Default session via env var: always uses the same session, auto-resumes
export GH_CLAUDE_DEFAULT_SESSION_ID=my-session
gh claude pr chat 42    # first run: new session, context rendered
gh claude pr chat 42    # subsequent runs: auto-resume, no re-fetch
```

`GH_CLAUDE_DEFAULT_SESSION_ID` is only consulted when neither `--session-id`
nor `--resume` are provided, so explicit flags always take precedence.

Override the sessions root by setting `XDG_STATE_HOME`.

## Configuration

Override the model via `--model` or `gh config`.

| Key                 | Default | Description                            |
| ------------------- | ------- | -------------------------------------- |
| `claude.model`       | `haiku` | Model for all commands (fallback)      |
| `claude.pr.model`    |         | Model override for `pr` subcommands    |
| `claude.issue.model` |         | Model override for `issue` subcommands |
| `claude.run.model`   |         | Model override for `run` subcommands   |

Priority: `--model` flag > per-command config > `claude.model`.

```bash
# Override the model for a single invocation
gh claude --model sonnet pr chat 42

# Set the default model
gh config set claude.model haiku

# Use a stronger model for PRs
gh config set claude.pr.model sonnet
```

> **Note:** `gh config set` will print a warning for keys it doesn't
> recognize (e.g. `'claude.pr.model' is not a known configuration key`).
> This is expected — the values are still saved and used by the extension.

## Integrations

### gh-fzf

[gh-fzf](https://github.com/gh-extensions/gh-fzf) is a GitHub CLI extension
that wraps `gh` commands in an interactive fuzzy finder. Source
`extras/gh_fzf.sh` in your shell config to register `gh claude` keybinds via
`GH_FZF_*_OPTS`.

```bash
source "$HOME/.local/share/gh/extensions/gh-claude/extras/gh_fzf.sh"
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
window so fzf stays interactive. Set `GH_CLAUDE_FZF_TMUX=0` to disable this
and always run inline.

## The gh-extensions Ecosystem

| Repo | What it provides |
|------|-----------------|
| **gh-claude** ← you are here | AI-powered copilot for the GitHub CLI |
| [gh-fzf](https://github.com/gh-extensions/gh-fzf) | Fuzzy finder for GitHub CLI |
| [gh-worktree](https://github.com/gh-extensions/gh-worktree) | Isolated git worktrees for PRs, issues, and workflow runs |

## License

[MIT](LICENSE) — Copyright (c) 2025 gh-extensions

<!-- markdownlint-disable-file MD013 MD036 -->
