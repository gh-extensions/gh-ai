# gh-ai

A GitHub CLI extension that uses AI to generate commit messages, create and
edit pull requests with smart titles and descriptions, review code with
actionable feedback, manage issues and generate implementation plans, and
explain CI failures.

![License](https://img.shields.io/github/license/gh-extensions/gh-ai)
![Version](https://img.shields.io/github/v/release/gh-extensions/gh-ai)

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
gh ai commit [-d <DESCRIPTION>] [-- GIT_COMMIT_OPTIONS]
gh ai pr create [-d <DESCRIPTION>] [-B <BASE>] [-- GH_PR_CREATE_OPTIONS]
gh ai pr edit [PR_NUMBER] -d <DESCRIPTION> [-- GH_PR_EDIT_OPTIONS]
gh ai pr review [PR_NUMBER] [-d <DESCRIPTION>] [-- GH_PR_REVIEW_OPTIONS]
gh ai pr explain [PR_NUMBER] [--comment | --edit]
gh ai issue create -d <DESCRIPTION> [-- GH_ISSUE_CREATE_OPTIONS]
gh ai issue edit <ISSUE_NUMBER> -d <DESCRIPTION> [-- GH_ISSUE_EDIT_OPTIONS]
gh ai issue plan <ISSUE_NUMBER> [-d <DESCRIPTION>]
gh ai run explain <RUN_ID>
```

### Commit

Generates a conventional commit message from your staged changes. Use
`-d`/`--description` to provide extra context or constraints that guide
the AI when writing the message.

```bash
git add -p
gh ai commit
gh ai commit -d "focus on the security improvements"
gh ai commit -- --signoff
gh ai commit -- --no-verify
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

### Run

Analyzes a GitHub Actions workflow run and explains what happened.

```bash
gh ai run explain 123456 # uses --log-failed for failed runs, --log otherwise
```

## Configuration

Override the AI provider and model via `gh config`.

| Key                  | Default     | Description                                        |
| -------------------- | ----------- | -------------------------------------------------- |
| `gh-ai.provider`     | `anthropic` | AI provider (`anthropic`)                          |
| `gh-ai.model`        | `haiku`     | Model for all commands (fallback)                  |
| `gh-ai.commit.model` |             | Model override for `commit`                        |
| `gh-ai.pr.model`     |             | Model override for `pr create/edit/review/explain` |
| `gh-ai.issue.model`  |             | Model override for `issue create/edit/plan`        |
| `gh-ai.run.model`    |             | Model override for `run explain`                   |

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

<!-- markdownlint-disable-file MD013 -->
