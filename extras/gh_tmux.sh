#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x

set -euo pipefail

# Print usage to stdout
_show_help() {
	cat <<'EOF'
gh_tmux.sh - tmux helpers for gh-ai

USAGE:
    gh_tmux.sh new-session <name> [command...]
    gh_tmux.sh new-window  <name> [command...]

SUBCOMMANDS:
    new-session   Create a tmux session if it does not already exist, then
                  switch the client to it. '#' is stripped from the name.

    new-window    Open a new tmux window with the given name and command.
                  '#' is stripped from the name.

ARGUMENTS:
    name          Session or window name. Any '#' characters are removed
                  and '.' characters are replaced with '_' before passing
                  to tmux (# is a tmux format string prefix).
    command       Optional command to run inside the session or window.
EOF
}

# Strip '#' and replace '.' with '_' in a tmux session or window name.
#
# Usage: _tmux_strip_name <name>
_tmux_strip_name() {
	printf '%s' "${1//#/}" | tr . _
}

# Create a tmux session (if it does not already exist) and switch to it.
#
# Usage: _tmux_new_session <name> [command...]
_tmux_new_session() {
	local name
	name=$(_tmux_strip_name "$1")
	shift
	local cmd=("$@")

	if ! tmux has-session -t "=$name" 2>/dev/null; then
		tmux new-session -d -s "$name" "${cmd[@]+"${cmd[@]}"}"
	fi
	tmux switch-client -t "=$name" 2>/dev/null || true
}

# Open a new tmux window with the given name and command.
#
# Usage: _tmux_new_window <name> [command...]
_tmux_new_window() {
	local name
	name=$(_tmux_strip_name "$1")
	shift
	local cmd=("$@")

	tmux new-window -n "$name" "${cmd[@]+"${cmd[@]}"}"
}

case "${1:-}" in
--help | -h | help)
	_show_help
	;;
new-session)
	shift
	[[ $# -ge 1 ]] || {
		gum log --level error 'new-session: name required'
		exit 1
	}
	_tmux_new_session "$@"
	;;
new-window)
	shift
	[[ $# -ge 1 ]] || {
		gum log --level error 'new-window: name required'
		exit 1
	}
	_tmux_new_window "$@"
	;;
*)
	gum log --level error "unknown subcommand: ${1:-(none)}"
	gum log --level warn 'Run gh_tmux.sh --help for usage.'
	exit 1
	;;
esac
