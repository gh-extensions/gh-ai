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
#     alt-R   Request changes on the selected PR via AI review
#     alt-C   Chat about the selected PR with AI
#
#   gh-fzf run
#     alt-E   Explain the selected workflow run failure with AI
#     alt-C   Chat about the selected workflow run with AI
#
# When inside tmux, chat bindings (alt-C) open in a new tmux window so fzf
# stays interactive.

_gh_fzf_dir=$(dirname "${BASH_SOURCE[0]:-$0}")
[[ "$_gh_fzf_dir" = /* ]] || _gh_fzf_dir="$(cd "$_gh_fzf_dir" && pwd)"

# shellcheck source=../scripts/gh_cmd.sh
source "$_gh_fzf_dir/../scripts/gh_cmd.sh"
_gh_fzf_agent=$(_gh_config_ai_agent)

_gh_fzf_tmux_use=0
if [[ -n "${TMUX:-}" ]]; then
	_gh_fzf_tmux_cmd="$_gh_fzf_dir/gh_tmux_cmd.sh"
	_gh_fzf_tmux_use=1
fi

if [[ "$_gh_fzf_tmux_use" -eq 1 ]]; then
	_gh_fzf_issue_opts=(
		"--bind=alt-P:execute(gh ai issue plan {1} | gum format | gum pager)"
		"--bind=alt-C:execute-silent(${_gh_fzf_tmux_cmd} new-window ${_gh_fzf_agent}/issue-{1} gh ai issue chat {1})+abort"
	)
else
	_gh_fzf_issue_opts=(
		"--bind=alt-P:execute(gh ai issue plan {1} | gum format | gum pager)"
		"--bind=alt-C:execute(gh ai issue chat {1})+abort"
	)
fi
GH_FZF_ISSUE_OPTS+="${GH_FZF_ISSUE_OPTS:+ }$(printf '%q ' "${_gh_fzf_issue_opts[@]}")"
GH_FZF_ISSUE_OPTS="${GH_FZF_ISSUE_OPTS% }"
export GH_FZF_ISSUE_OPTS
unset _gh_fzf_issue_opts

if [[ "$_gh_fzf_tmux_use" -eq 1 ]]; then
	_gh_fzf_pr_opts=(
		"--bind=alt-E:execute(gh ai pr explain {1} | gum pager)"
		"--bind=alt-R:execute(gh ai pr review {1} -- --request-changes)+abort"
		"--bind=alt-C:execute-silent(${_gh_fzf_tmux_cmd} new-window ${_gh_fzf_agent}/pull-{1} gh ai pr chat {1})+abort"
	)
else
	_gh_fzf_pr_opts=(
		"--bind=alt-E:execute(gh ai pr explain {1} | gum pager)"
		"--bind=alt-R:execute(gh ai pr review {1} -- --request-changes)+abort"
		"--bind=alt-C:execute(gh ai pr chat {1})+abort"
	)
fi
GH_FZF_PR_OPTS+="${GH_FZF_PR_OPTS:+ }$(printf '%q ' "${_gh_fzf_pr_opts[@]}")"
GH_FZF_PR_OPTS="${GH_FZF_PR_OPTS% }"
export GH_FZF_PR_OPTS
unset _gh_fzf_pr_opts

if [[ "$_gh_fzf_tmux_use" -eq 1 ]]; then
	_gh_fzf_run_opts=(
		"--bind=alt-E:execute(gh ai run explain {-1} | gum format | gum pager)"
		"--bind=alt-C:execute-silent(${_gh_fzf_tmux_cmd} new-window ${_gh_fzf_agent}/run-{-1} gh ai run chat {-1})+abort"
	)
else
	_gh_fzf_run_opts=(
		"--bind=alt-E:execute(gh ai run explain {-1} | gum format | gum pager)"
		"--bind=alt-C:execute(gh ai run chat {-1})+abort"
	)
fi
GH_FZF_RUN_OPTS+="${GH_FZF_RUN_OPTS:+ }$(printf '%q ' "${_gh_fzf_run_opts[@]}")"
GH_FZF_RUN_OPTS="${GH_FZF_RUN_OPTS% }"
export GH_FZF_RUN_OPTS
unset _gh_fzf_run_opts _gh_fzf_tmux_use _gh_fzf_tmux_cmd _gh_fzf_dir _gh_fzf_agent
