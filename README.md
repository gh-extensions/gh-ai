# gh-ai

> Your AI-powered copilot for the GitHub CLI. Draft pull requests, plan issue implementations, review code, debug CI failures, and drop into interactive coding sessions — without leaving the terminal.

[![CI](https://github.com/gh-extensions/gh-ai/actions/workflows/ci.yml/badge.svg)](https://github.com/gh-extensions/gh-ai/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/gh-extensions/gh-ai)](https://github.com/gh-extensions/gh-ai/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Stop context-switching between your editor, browser, and terminal. `gh ai`
meets you where you already work and handles the tedious parts so you can
focus on shipping.

## Requirements

- [GitHub CLI](https://cli.github.com/) (`gh`)
- [Bash](https://www.gnu.org/software/bash/) 4.4+ (`bash`)
- [jq](https://jqlang.github.io/jq/) (`jq`)
- One supported AI agent:
  - [Claude Code](https://docs.anthropic.com/en/docs/build-with-claude/claude-code) (`claude`)
  - [Codex](https://developers.openai.com/codex/) (`codex`)
  - [Gemini CLI](https://github.com/google-gemini/gemini-cli) (`gemini`)
- [Gum](https://github.com/charmbracelet/gum) (`gum`)

**macOS (Homebrew):**

```bash
brew install gh bash jq gum
```

**Nix:**

```bash
nix profile install nixpkgs#gh nixpkgs#bash nixpkgs#jq nixpkgs#gum
```

Install your AI agent separately:

- Claude Code: [Claude Code installation guide](https://docs.anthropic.com/en/docs/claude-code/setup)
- Codex: [OpenAI Codex](https://developers.openai.com/codex/)
- Gemini CLI: [google-gemini/gemini-cli](https://github.com/google-gemini/gemini-cli)

## Installation

```bash
gh extension install gh-extensions/gh-ai --pin v1.2.3  # recommended: pin to a stable release
gh extension install gh-extensions/gh-ai                # installs from main (unstable)
```

## Usage

```bash
gh ai [AI_OPTIONS] pr create [-d <DESCRIPTION>] [-B <BASE>] [GH_PR_CREATE_OPTIONS]
gh ai [AI_OPTIONS] pr edit [PR_NUMBER] -d <DESCRIPTION> [GH_PR_EDIT_OPTIONS]
gh ai [AI_OPTIONS] pr review [PR_NUMBER] [-d <DESCRIPTION>] [GH_PR_REVIEW_OPTIONS]
gh ai [AI_OPTIONS] pr comment [PR_NUMBER] -d <DESCRIPTION> [GH_PR_COMMENT_OPTIONS]
gh ai [AI_OPTIONS] pr analyze [PR_NUMBER] [-d <DESCRIPTION>] [-i]
gh ai [AI_OPTIONS] issue create -d <DESCRIPTION> [GH_ISSUE_CREATE_OPTIONS]
gh ai [AI_OPTIONS] issue edit <ISSUE_NUMBER> -d <DESCRIPTION> [GH_ISSUE_EDIT_OPTIONS]
gh ai [AI_OPTIONS] issue comment <ISSUE_NUMBER> -d <DESCRIPTION> [GH_ISSUE_COMMENT_OPTIONS]
gh ai [AI_OPTIONS] issue analyze <ISSUE_NUMBER> [-d <DESCRIPTION>] [-i]
gh ai [AI_OPTIONS] run analyze <RUN_ID> [-d <DESCRIPTION>] [-i]
```

`AI_OPTIONS` are flags forwarded to the AI agent binary (e.g., `--model`,
`--session-id`, `--resume`, `--verbose`, `--allowedTools`, `--permission-mode`).
They are placed **before** the subcommand keyword.

### Pull Request

Creates a pull request with an AI-generated title and description.

```bash
gh ai pr create
gh ai pr create -B develop --draft
gh ai pr create -d "focus on the security changes"
```

Edits an existing pull request with AI-generated updates based on a description
of what to change.

```bash
gh ai pr edit 42 -d "add testing section"
gh ai pr edit 42 -d "fix summary" --add-label bug
gh ai pr edit -d "improve description"   # auto-detect PR from current branch
```

Reviews a pull request with AI-generated feedback. Use `-d`/`--description`
to provide extra context or focus areas that guide the AI review.

```bash
gh ai pr review 42
gh ai pr review 42 --approve
gh ai pr review -d "focus on security"
gh ai pr review 42 -d "check error handling" --comment
gh ai pr review # auto-detects PR for the current branch
```

Analyzes a pull request. Without `-i`, prints the analysis to stdout.
With `-i`, opens an interactive agent session that begins with the analysis
and asks how you'd like to proceed (review specific areas, propose fixes,
draft a comment, etc.). Context files are staged under
`~/.local/state/gh/ai/context/pull-<N>/` and are refreshed on every
invocation; the agent reads them on demand.

```bash
gh ai pr analyze 42
gh ai pr analyze 42 -i                          # interactive session
gh ai pr analyze -d "focus on the security changes" -i
gh ai pr analyze                                # auto-detect PR from current branch
gh ai pr analyze 42 | gh pr comment 42 --body -    # pipe analysis as a PR comment
gh ai pr analyze 42 | gh pr edit 42 --body -       # replace PR description
gh ai --session-id <UUID> pr analyze 42 -i      # named agent session
```

### Issue

Creates a structured GitHub issue from a brief description.

```bash
gh ai issue create -d "Login page crashes with special chars"
gh ai issue create -d "Login crash" --label bug --assignee @me
some_command 2>&1 | gh ai issue create -d "Command X fails" # pipe error context
```

Edits an existing issue with AI-generated updates based on a description of
what to change.

```bash
gh ai issue edit 42 -d "add acceptance criteria"
gh ai issue edit 42 -d "fix typos and improve clarity"
gh ai issue edit 42 -d "rephrase as a bug report" --add-label bug
```

Analyzes an issue. Without `-i`, prints the analysis to stdout. With `-i`,
opens an interactive agent session that begins with the analysis and asks
how you'd like to proceed — discuss scope, draft an implementation plan,
draft a clarifying comment, or begin work. Context files are staged under
`~/.local/state/gh/ai/context/issue-<N>/` and are refreshed on every
invocation.

```bash
gh ai issue analyze 42
gh ai issue analyze 42 -i                       # interactive session
gh ai issue analyze 42 -d "focus on the auth module" -i
gh ai issue analyze 42 | pbcopy                 # pipe the analysis
gh ai --session-id <UUID> issue analyze 42 -i   # named agent session
```

### Run

Analyzes a GitHub Actions workflow run. Without `-i`, prints the analysis
to stdout. With `-i`, opens an interactive agent session that begins with
the analysis and asks how you'd like to proceed (investigate a failure,
draft a fix, retry, etc.). Uses `--log-failed` for failed runs, `--log`
otherwise. Context files are staged under
`~/.local/state/gh/ai/context/run-<ID>/` and refreshed on every
invocation.

```bash
gh ai run analyze 123456
gh ai run analyze 123456 -i                       # interactive session
gh ai run analyze 123456 -d "focus on test failures" -i
gh ai --session-id <UUID> run analyze 123456 -i   # named agent session
```

## Recipes

**Pipe an issue analysis directly into an AI agent**

```bash
gh ai issue analyze 42 | claude  # or: jules new, gh agent-task create -F -
```

**Start work on an issue, generate a plan, and open a draft PR in one command**

Check out a development branch for the issue, record an empty commit to mark
the start of work, then pipe the AI-generated analysis directly into a new
pull request body.

```bash
gh issue develop 42 --checkout && \
  git commit --allow-empty -m "chore: start work on #42" && git push && \
  gh ai issue analyze 42 -d "produce an implementation plan with task IDs" \
    | gh pr create --title "Implementation plan for #42" -F -
```

**Open an interactive analyze session inside an isolated worktree with [gh-worktree](https://github.com/gh-extensions/gh-worktree)**

[gh-worktree](https://github.com/gh-extensions/gh-worktree) creates a dedicated git worktree for the
resource, then runs a command inside it. Combine it with `gh ai` to start an
interactive session in the correct branch with no impact on your working tree.

```bash
gh worktree pr 42 -- gh ai pr analyze 42 -i
gh worktree issue 42 -- gh ai issue analyze 42 -i
gh worktree run 12345678 -- gh ai run analyze 12345678 -i
```

Inside tmux, open the session in a new window so your current work is not interrupted:

```bash
tmux new-window -n "pull-42" "gh worktree pr 42 -- gh ai pr analyze 42 -i"
tmux new-window -n "issue-42" "gh worktree issue 42 -- gh ai issue analyze 42 -i"
```

**Start a dedicated tmux session for a PR or issue**

Create a named tmux session in the background, then attach to it. Useful when you want a fully isolated terminal session you can detach from and return to later.

```bash
gh worktree pr 42 --keep -- tmux new-session -d -s "pull-42" "gh ai pr analyze 42 -i" && tmux attach -t "pull-42"
gh worktree issue 42 --keep -- tmux new-session -d -s "issue-42" "gh ai issue analyze 42 -i" && tmux attach -t "issue-42"
gh worktree run 123 --keep -- tmux new-session -d -s "run-123" "gh ai run analyze 123 -i" && tmux attach -t "run-123"
```

**Consolidate Dependabot PRs into one tracked issue and implement with an AI agent**

Pipe the list of open Dependabot PRs into `gh ai issue create` so the AI names
each PR in the issue body, then hand off an analysis of the new issue to an
AI agent.

```bash
# Pipe the plan to any agent: jules new, gh agent-task create -F -, claude, etc.
gh pr list --search "author:app/dependabot is:pr" --json number,title \
  | gh ai issue create -d "Your task is to consolidate Dependabot pull requests." \
  | xargs -I{} sh -c 'gh ai issue analyze "{}" | jules new'
```

## Agent Sessions

The CLI is agent-agnostic and does not manage session IDs internally. It always
fetches the latest data from GitHub, stages it under
`~/.local/state/gh/ai/context/{pull,issue,run}-<N>/`, and passes the
file paths as a context prompt to the agent.

You can manage agent-specific sessions by passing flags directly:

```bash
# Start a new interactive session with context
gh ai pr analyze 42 -i

# Resume a specific Claude session (agent handles history)
gh ai --resume <ID> pr analyze 42 -i
```

## Configuration

Override the AI provider and model via `gh config`.

| Key              | Default       | Description                            |
| ---------------- | ------------- | -------------------------------------- |
| `ai.agent`       | `claude`      | AI agent (`claude`, `codex`, `gemini`) |
| `ai.model`       | Agent default | Model for all commands (fallback)      |
| `ai.pr.model`    |               | Model override for `pr` subcommands    |
| `ai.issue.model` |               | Model override for `issue` subcommands |
| `ai.run.model`   |               | Model override for `run` subcommands   |

Agent defaults:

- `claude`: `haiku`
- `codex`: `gpt-5.4-mini`
- `gemini`: `gemini-2.0-flash`

Priority: `--model` flag > per-command config > `ai.model` > agent default.

```bash
# Override the model for a single invocation
gh ai --model sonnet pr analyze 42 -i

# Set the default model
gh config set ai.model haiku

# Use Gemini
gh config set ai.agent gemini
gh config set ai.model gemini-2.0-flash
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

| Context        | Key     | Action                                                  |
| -------------- | ------- | ------------------------------------------------------- |
| `gh-fzf issue` | `alt-A` | Analyze the selected issue with AI                      |
| `gh-fzf issue` | `alt-C` | Open an interactive AI session for the selected issue   |
| `gh-fzf pr`    | `alt-A` | Analyze the selected PR with AI                         |
| `gh-fzf pr`    | `alt-R` | Request changes on the selected PR via AI review        |
| `gh-fzf pr`    | `alt-C` | Open an interactive AI session for the selected PR      |
| `gh-fzf run`   | `alt-A` | Analyze the selected workflow run with AI               |
| `gh-fzf run`   | `alt-C` | Open an interactive AI session for the selected run     |

When inside tmux, interactive bindings (`alt-C`) automatically open in a new
tmux window so fzf stays interactive. Set `GH_AI_FZF_TMUX=0` to disable this
and always run inline.

## The gh-extensions Ecosystem

| Repo                                                        | What it provides                                          |
| ----------------------------------------------------------- | --------------------------------------------------------- |
| **gh-ai** ← you are here                                    | AI-powered copilot for the GitHub CLI                     |
| [gh-fzf](https://github.com/gh-extensions/gh-fzf)           | Fuzzy finder for GitHub CLI                               |
| [gh-worktree](https://github.com/gh-extensions/gh-worktree) | Isolated git worktrees for PRs, issues, and workflow runs |

## License

[MIT](LICENSE) — Copyright (c) 2025 gh-extensions

<!-- markdownlint-disable-file MD013 MD036 -->
