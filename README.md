<!-- markdownlint-disable-file MD013 -->

# gh-ai

A GitHub CLI extension that uses AI to generate commit messages, pull request
descriptions, and code reviews.

![License](https://img.shields.io/github/license/gh-extensions/gh-ai)
![Version](https://img.shields.io/github/v/release/gh-extensions/gh-ai)

## Prerequisites

- [GitHub CLI](https://cli.github.com/) (`gh`)
- [Claude Code](https://docs.anthropic.com/en/docs/build-with-claude/claude-code) (`claude`)
- [gum](https://github.com/charmbracelet/gum)

## Installation

```bash
gh extension install gh-extensions/gh-ai
```

## Usage

```bash
gh ai commit [GIT_COMMIT_OPTIONS]
gh ai pr create [GH_PR_CREATE_OPTIONS]
gh ai pr review [PR_NUMBER] [GH_PR_REVIEW_OPTIONS]
```

### Commit

Generates a conventional commit message from your staged changes.

```bash
git add -p
gh ai commit
gh ai commit --signoff
```

### Pull Request

Creates a pull request with an AI-generated title and description.

```bash
gh ai pr create
gh ai pr create --draft --base develop
```

Reviews a pull request with AI-generated feedback.

```bash
gh ai pr review 42
gh ai pr review 42 --approve
gh ai pr review # auto-detects PR for the current branch
```

## Configuration

Override the AI provider and model via `gh config`.

| Key                         | Default     | Description                           |
| --------------------------- | ----------- | ------------------------------------- |
| `gh-ai.provider`     | `anthropic` | AI provider (`anthropic`)             |
| `gh-ai.model`        | `haiku`     | Model for all commands (fallback)     |
| `gh-ai.commit.model` |             | Model override for `commit`           |
| `gh-ai.pr.model`     |             | Model override for `pr create/review` |

Per-command keys take priority over `gh-ai.model`.

```bash
# Set the default model
gh config set gh-ai.model haiku

# Use a stronger model for PRs
gh config set gh-ai.pr.model sonnet
```

> **Note:** `gh config set` will print a warning for keys it doesn't
> recognize (e.g. `'gh-ai.pr.model' is not a known configuration key`).
> This is expected — the values are still saved and used by the extension.

## License

[MIT](LICENSE) — Copyright (c) 2025 gh-extensions
