# gh-ai fzf bindings — source this file in your shell config to register all
# gh-ai keybinds with gh-fzf via GH_FZF_*_OPTS.
#
# Usage: add to ~/.bashrc or ~/.zshrc
#   source /path/to/extras/gh_fzf_ai.sh
#
# Keybinds added:
#
#   gh-fzf issue
#     alt-P   Generate and view AI plan for the selected issue
#
#   gh-fzf pr
#     alt-E   Explain the selected PR with AI
#     alt-A   Approve the selected PR via AI review
#     alt-N   Request changes on the selected PR via AI review
#
#   gh-fzf run
#     alt-E   Explain the selected workflow run failure with AI
#
#   gh-fzf search prs
#     alt-E   Explain the selected PR with AI
#     alt-A   Approve the selected PR via AI review
#     alt-N   Request changes on the selected PR via AI review

_gh_fzf_issue_opts=(
	'--bind "alt-P:execute(gh ai issue plan {1} | gum format | gum pager)"'
)
export GH_FZF_ISSUE_OPTS="${_gh_fzf_issue_opts[*]}"
unset _gh_fzf_issue_opts

_gh_fzf_pr_opts=(
	'--bind "alt-E:execute(gh ai pr explain {1} | gum pager)"'
	'--bind "alt-A:execute(gh ai pr review {1} -- --approve)"'
	'--bind "alt-N:execute(gh ai pr review {1} -- --request-changes)"'
)
export GH_FZF_PR_OPTS="${_gh_fzf_pr_opts[*]}"
unset _gh_fzf_pr_opts

_gh_fzf_run_opts=(
	'--bind "alt-E:execute(gh ai run explain {-1} | gum format | gum pager)"'
)
export GH_FZF_RUN_OPTS="${_gh_fzf_run_opts[*]}"
unset _gh_fzf_run_opts

_gh_fzf_search_pr_opts=(
	'--bind "alt-E:execute(gh ai pr explain {1} --repo {2} | gum pager)"'
	'--bind "alt-A:execute(gh ai pr review {1} --repo {2} -- --approve)"'
	'--bind "alt-N:execute(gh ai pr review {1} --repo {2} -- --request-changes)"'
)
export GH_FZF_SEARCH_PR_OPTS="${_gh_fzf_search_pr_opts[*]}"
unset _gh_fzf_search_pr_opts
