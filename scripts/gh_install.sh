#!/usr/bin/env bash

[ -z "$DEBUG" ] || set -x

set -eo pipefail

# Install configuration files for AI tools

# Install configuration for Claude Code
#
# Copies commands to .claude/commands/ with nested directory structure.
# Filenames are split by underscore to create directories.
# Example: gh_issue_develop.md -> gh/issue/develop.md
#
# Usage: _gh_install_claude <global>
_gh_install_claude() {
	local global="$1"
	local target_base

	if [[ "$global" == true ]]; then
		target_base="$HOME/.claude/commands"
	else
		target_base=".claude/commands"
	fi

	# shellcheck disable=SC2154
	local source_dir="$_gh_assistant_source_dir/commands"

	if [[ ! -d "$source_dir" ]]; then
		gum log --level error "Source directory not found: $source_dir"
		return 1
	fi

	for file in "$source_dir"/*.md; do
		[[ -f "$file" ]] || continue

		local basename="${file##*/}"
		local name="${basename%.md}"

		# Split by underscore into array
		IFS='_' read -ra parts <<<"$name"

		# All but last part become directories
		local dir_path=""
		for ((i = 0; i < ${#parts[@]} - 1; i++)); do
			dir_path="$dir_path/${parts[i]}"
		done

		# Last part is the filename
		local last_idx=$((${#parts[@]} - 1))
		local filename="${parts[$last_idx]}.md"

		local target_dir="$target_base$dir_path"
		mkdir -p "$target_dir"
		cp -f "$file" "$target_dir/$filename"
	done

	local scope="local"
	[[ "$global" == true ]] && scope="global"
	gum log --level info "Installed claude configuration ($scope) to $target_base/"
}

# Install configuration for Gemini CLI
#
# Converts markdown commands to TOML and installs to .gemini/commands/
# with nested directory structure for namespacing.
# Example: gh_issue_develop.md -> gh/issue/develop.toml -> /gh:issue:develop
#
# Usage: _gh_install_gemini <global>
_gh_install_gemini() {
	local global="$1"
	local target_base

	if [[ "$global" == true ]]; then
		target_base="$HOME/.gemini/commands"
	else
		target_base=".gemini/commands"
	fi

	# shellcheck disable=SC2154
	local source_dir="$_gh_assistant_source_dir/commands"

	if [[ ! -d "$source_dir" ]]; then
		gum log --level error "Source directory not found: $source_dir"
		return 1
	fi

	for file in "$source_dir"/*.md; do
		[[ -f "$file" ]] || continue

		local basename="${file##*/}"
		local name="${basename%.md}"

		# Split by underscore into array for namespacing
		IFS='_' read -ra parts <<<"$name"

		# All but last part become directories
		local dir_path=""
		for ((i = 0; i < ${#parts[@]} - 1; i++)); do
			dir_path="$dir_path/${parts[i]}"
		done

		# Last part is the filename (with .toml extension)
		local last_idx=$((${#parts[@]} - 1))
		local filename="${parts[$last_idx]}.toml"

		local target_dir="$target_base$dir_path"
		mkdir -p "$target_dir"

		# Convert markdown to TOML
		_gh_convert_md_to_toml "$file" "$target_dir/$filename"
	done

	local scope="local"
	[[ "$global" == true ]] && scope="global"
	gum log --level info "Installed gemini configuration ($scope) to $target_base/"
}

# Install configuration for OpenCode
#
# Copies commands to .opencode/command/ (local) or ~/.config/opencode/command/ (global)
#
# Usage: _gh_install_opencode <global>
_gh_install_opencode() {
	local global="$1"
	local target_dir

	if [[ "$global" == true ]]; then
		target_dir="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/command"
	else
		target_dir=".opencode/command"
	fi

	# shellcheck disable=SC2154
	local source_dir="$_gh_assistant_source_dir/commands"

	if [[ ! -d "$source_dir" ]]; then
		gum log --level error "Source directory not found: $source_dir"
		return 1
	fi

	mkdir -p "$target_dir"
	cp -rf "$source_dir"/* "$target_dir"/

	local scope="local"
	[[ "$global" == true ]] && scope="global"
	gum log --level info "Installed opencode configuration ($scope) to $target_dir/"
}

# Convert markdown command file to TOML format
#
# Extracts description from YAML frontmatter and content as prompt.
#
# Usage: _gh_convert_md_to_toml <input_file> <output_file>
_gh_convert_md_to_toml() {
	local input_file="$1"
	local output_file="$2"

	# Extract description from YAML frontmatter
	local description
	description=$(sed -n '/^---$/,/^---$/{ /^description:/{ s/^description:[[:space:]]*//p; q; } }' "$input_file")

	# Extract content after frontmatter (after second ---)
	local prompt
	prompt=$(awk '/^---$/{if(++c==2){getline; p=1}} p' "$input_file")

	# Write TOML file
	# Use literal strings (''') to avoid escape sequence processing
	{
		echo "description = \"$description\""
		echo ""
		echo "prompt = '''"
		echo "$prompt"
		echo "'''"
	} >"$output_file"
}

# Show install help
_gh_install_help() {
	cat <<'EOF'
gh assistant install - Install configuration files

USAGE:
    gh assistant install --tool <name> [options]

TOOLS:
    claude      Install Claude Code commands to .claude/commands/
    gemini      Install Gemini CLI commands to .gemini/commands/
    opencode    Install OpenCode commands to .opencode/command/

OPTIONS:
    -t, --tool <name>  Tool to install for (required)
    -g, --global       Install globally instead of locally
    -h, --help         Show this help message

EXAMPLES:
    gh assistant install --tool claude
    gh assistant install -g -t gemini
    gh assistant install --global --tool opencode
EOF
}

# Main install entry point
#
# Installs configuration files for the specified AI tool.
# Use -g/--global for global install, otherwise requires git repository.
#
# Usage: _gh_install --tool <name> [-g|--global] [-h|--help]
_gh_install() {
	local global=false
	local tool=""

	# Parse flags
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-g | --global)
			global=true
			shift
			;;
		-t | --tool)
			tool="$2"
			shift 2
			;;
		-h | --help)
			_gh_install_help
			return 0
			;;
		*)
			gum log --level error "Unknown option: $1"
			_gh_install_help
			return 1
			;;
		esac
	done

	# Validate tool is set
	if [[ -z "$tool" ]]; then
		gum log --level error "Tool is required"
		gum log --level info "Usage: gh assistant install --tool <name>"
		gum log --level info "Run 'gh assistant install --help' for more information"
		return 1
	fi

	# For local install, require git repo
	if [[ "$global" != true ]]; then
		if ! git rev-parse --git-dir >/dev/null 2>&1; then
			gum log --level error "Not in a git repository"
			gum log --level info "Use --global for global installation"
			return 1
		fi
	fi

	# Dispatch to tool-specific function
	case "$tool" in
	claude)
		_gh_install_claude "$global"
		;;
	gemini)
		_gh_install_gemini "$global"
		;;
	opencode)
		_gh_install_opencode "$global"
		;;
	*)
		gum log --level error "Unknown tool: $tool"
		gum log --level info "Available tools: claude, gemini, opencode"
		return 1
		;;
	esac
}
