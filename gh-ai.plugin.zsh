# gh-ai.plugin.zsh — zsh plugin entry point
#
# Options (set before sourcing):
#   GH_AI_FZF=0   Disable extras/gh_fzf.sh (Claude keybindings in gh-fzf)

if [[ "${GH_AI_FZF:-1}" != "0" ]]; then
  source "${0:A:h}/extras/gh_fzf.sh"
fi
