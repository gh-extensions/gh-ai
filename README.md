<!-- markdownlint-disable-file MD013 -->

# gh-assistant

A GitHub CLI extension that uses AI to generate commit messages, pull request
descriptions, and code reviews.

![License](https://img.shields.io/github/license/gh-extensions/gh-assistant)
![Version](https://img.shields.io/github/v/release/gh-extensions/gh-assistant)

## Prerequisites

- [GitHub CLI](https://cli.github.com/) (`gh`)
- [Claude Code](https://docs.anthropic.com/en/docs/build-with-claude/claude-code) (`claude`)
- [gum](https://github.com/charmbracelet/gum)

## Installation

```bash
gh extension install gh-extensions/gh-assistant
```

## Usage

```bash
gh assistant commit [GIT_COMMIT_OPTIONS]
gh assistant pr create [GH_PR_CREATE_OPTIONS]
gh assistant pr review [PR_NUMBER] [GH_PR_REVIEW_OPTIONS]
```

### Commit

Generates a conventional commit message from your staged changes.

```bash
git add -p
gh assistant commit
gh assistant commit --signoff
```

### Pull Request

Creates a pull request with an AI-generated title and description.

```bash
gh assistant pr create
gh assistant pr create --draft --base develop
```

Reviews a pull request with AI-generated feedback.

```bash
gh assistant pr review 42
gh assistant pr review 42 --approve
gh assistant pr review # auto-detects PR for the current branch
```

## Alias

To use `gh ai` as a shorthand:

```bash
gh alias set ai assistant
```

```bash
gh ai commit
gh ai pr create
gh ai pr review 42
```

## Configuration

Override the AI provider and model via `gh config`.

| Key                         | Default     | Description                           |
| --------------------------- | ----------- | ------------------------------------- |
| `gh-assistant.provider`     | `anthropic` | AI provider (`anthropic`)             |
| `gh-assistant.model`        | `haiku`     | Model for all commands (fallback)     |
| `gh-assistant.commit.model` |             | Model override for `commit`           |
| `gh-assistant.pr.model`     |             | Model override for `pr create/review` |

Per-command keys take priority over `gh-assistant.model`.

```bash
# Set the default model
gh config set gh-assistant.model haiku

# Use a stronger model for PRs
gh config set gh-assistant.pr.model sonnet
```

> **Note:** `gh config set` will print a warning for keys it doesn't
> recognize (e.g. `'gh-assistant.pr.model' is not a known configuration key`).
> This is expected — the values are still saved and used by the extension.

## License

[MIT](LICENSE) — Copyright (c) 2025 gh-extensions
