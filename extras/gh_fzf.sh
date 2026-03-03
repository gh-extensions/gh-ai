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
#     alt-C   Chat about the selected issue with AI
#
#   gh-fzf pr
#     alt-E   Explain the selected PR with AI
#     alt-A   Approve the selected PR via AI review
#     alt-N   Request changes on the selected PR via AI review
#     alt-C   Chat about the selected PR with AI
#
#   gh-fzf run
#     alt-E   Explain the selected workflow run failure with AI
#     alt-C   Chat about the selected workflow run with AI
#
# When inside tmux, chat bindings (alt-C) open in a new tmux window so fzf
# stays interactive. Set GH_AI_FZF_TMUX=0 to disable this and always run
# inline.

_gh_fzf_use_tmux=0
# Track if tmux is avaialble
if [[ -n "${TMUX:-}" ]] && [[ "${GH_AI_FZF_TMUX:-1}" != "0" ]]; then
	_gh_fzf_use_tmux=1
fi

_gh_fzf_issue_opts=(
	'--bind "alt-P:execute(gh ai issue plan {1} | gum format | gum pager)"'
)

if [[ "$_gh_fzf_use_tmux" -eq 1 ]]; then
	_gh_fzf_issue_opts+=('--bind "alt-C:execute-silent(tmux new-window -n I#{1} gh ai issue chat {1})"')
else
	_gh_fzf_issue_opts+=('--bind "alt-C:execute(gh ai issue chat {1})"')
fi

export GH_FZF_ISSUE_OPTS="${GH_FZF_ISSUE_OPTS:+${GH_FZF_ISSUE_OPTS} }${_gh_fzf_issue_opts[*]}"
unset _gh_fzf_issue_opts

_gh_fzf_pr_opts=(
	'--bind "alt-E:execute(gh ai pr explain {1} | gum pager)"'
	'--bind "alt-A:execute(gh ai pr review {1} -- --approve)"'
	'--bind "alt-N:execute(gh ai pr review {1} -- --request-changes)"'
)

if [[ "$_gh_fzf_use_tmux" -eq 1 ]]; then
	_gh_fzf_pr_opts+=('--bind "alt-C:execute-silent(tmux new-window -n P#{1} gh ai pr chat {1})"')
else
	_gh_fzf_pr_opts+=('--bind "alt-C:execute(gh ai pr chat {1})"')
fi

export GH_FZF_PR_OPTS="${GH_FZF_PR_OPTS:+${GH_FZF_PR_OPTS} }${_gh_fzf_pr_opts[*]}"
unset _gh_fzf_pr_opts

_gh_fzf_run_opts=(
	'--bind "alt-E:execute(gh ai run explain {-1} | gum format | gum pager)"'
)

if [[ "$_gh_fzf_use_tmux" -eq 1 ]]; then
	_gh_fzf_run_opts+=('--bind "alt-C:execute-silent(tmux new-window -n R#{-1} gh ai run chat {-1})"')
else
	_gh_fzf_run_opts+=('--bind "alt-C:execute(gh ai run chat {-1})"')
fi

export GH_FZF_RUN_OPTS="${GH_FZF_RUN_OPTS:+${GH_FZF_RUN_OPTS} }${_gh_fzf_run_opts[*]}"
unset _gh_fzf_run_opts _gh_fzf_use_tmux
