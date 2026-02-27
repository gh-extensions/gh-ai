# gh-ai fzf bindings — source this file in your shell config to register all
# gh-ai keybinds with gh-fzf via GH_FZF_*_OPTS.
#
# Usage: add to ~/.bashrc or ~/.zshrc
#   source /path/to/extras/gh_fzf.sh
#
# Keybinds added:
#
#   gh-fzf issue
#     alt-P   Generate and view AI plan for the selected issue
#     alt-D   Open a Claude Code chat session for the issue (tmux only)
#
#   gh-fzf pr
#     alt-E   Explain the selected PR with AI
#     alt-A   Approve the selected PR via AI review
#     alt-N   Request changes on the selected PR via AI review
#     alt-R   Open a Claude Code review session for the PR (tmux only)
#
#   gh-fzf run
#     alt-E   Explain the selected workflow run failure with AI
#     alt-D   Open a Claude Code debug session for the run (tmux only)
#

_gh_fzf_issue_opts=(
	'--bind "alt-P:execute(gh ai issue plan {1} | gum format | gum pager)"'
)
if [[ -n "${TMUX:-}" ]]; then
	_gh_fzf_issue_opts+=(
		'--bind "alt-D:execute(tmux new-window -n I{1} gh ai issue chat {1})"'
	)
fi
export GH_FZF_ISSUE_OPTS="${GH_FZF_ISSUE_OPTS:+${GH_FZF_ISSUE_OPTS} }${_gh_fzf_issue_opts[*]}"
unset _gh_fzf_issue_opts

_gh_fzf_pr_opts=(
	'--bind "alt-E:execute(gh ai pr explain {1} | gum pager)"'
	'--bind "alt-A:execute(gh ai pr review {1} -- --approve)"'
	'--bind "alt-N:execute(gh ai pr review {1} -- --request-changes)"'
)
if [[ -n "${TMUX:-}" ]]; then
	_gh_fzf_pr_opts+=(
		'--bind "alt-R:execute(tmux new-window -n P{1} gh ai pr chat {1})"'
	)
fi
export GH_FZF_PR_OPTS="${GH_FZF_PR_OPTS:+${GH_FZF_PR_OPTS} }${_gh_fzf_pr_opts[*]}"
unset _gh_fzf_pr_opts

_gh_fzf_run_opts=(
	'--bind "alt-E:execute(gh ai run explain {-1} | gum format | gum pager)"'
)
if [[ -n "${TMUX:-}" ]]; then
	_gh_fzf_run_opts+=(
		'--bind "alt-D:execute(tmux new-window -n R{-1} gh ai run chat {-1})"'
	)
fi
export GH_FZF_RUN_OPTS="${GH_FZF_RUN_OPTS:+${GH_FZF_RUN_OPTS} }${_gh_fzf_run_opts[*]}"
unset _gh_fzf_run_opts
