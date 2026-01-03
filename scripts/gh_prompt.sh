#!/usr/bin/env bash

[ -z "$DEBUG" ] || set -x

set -eo pipefail

# Prompt management functions for gh-assistant

# Get prompt directory path
#
# Returns the path to the prompt directory relative to source_dir.
# Requires $_gh_assistant_source_dir to be set by the main script.
#
# Usage: prompt_dir=$(_get_prompt_dir)
_get_prompt_dir() {
	# shellcheck disable=SC2154
	echo "$_gh_assistant_source_dir/prompts"
}

# List all available prompts
#
# Displays a table of all prompts in the prompts directory with their
# metadata (name, title, kind, version, status) extracted from frontmatter.
#
# Usage: _gh_prompt_list
_gh_prompt_list() {
	local prompt_dir
	prompt_dir=$(_get_prompt_dir)

	if [[ ! -d "$prompt_dir" ]]; then
		gum log --level error "Prompt directory not found: $prompt_dir"
		return 1
	fi

	# Header
	printf "%-20s %-20s %-25s %-10s %-10s\n" "NAME" "TITLE" "KIND" "VERSION" "STATUS"
	printf "%-20s %-20s %-25s %-10s %-10s\n" "----" "-----" "----" "-------" "------"

	# List all .md files and extract frontmatter
	for file in "$prompt_dir"/*.md; do
		[[ -f "$file" ]] || continue

		local name title kind version status
		name=$(basename "$file" .md)

		# Extract frontmatter values using sed
		title=$(sed -n '/^---$/,/^---$/{ /^title:/{ s/^title:[[:space:]]*//p; q; } }' "$file")
		kind=$(sed -n '/^---$/,/^---$/{ /^kind:/{ s/^kind:[[:space:]]*//p; q; } }' "$file")
		version=$(sed -n '/^---$/,/^---$/{ /^version:/{ s/^version:[[:space:]]*//p; q; } }' "$file")
		status=$(sed -n '/^---$/,/^---$/{ /^status:/{ s/^status:[[:space:]]*//p; q; } }' "$file")

		printf "%-20s %-20s %-25s %-10s %-10s\n" "$name" "$title" "$kind" "$version" "$status"
	done
}

# View a prompt's content
#
# Displays the full content of a prompt file. If glow is available,
# renders the markdown with syntax highlighting.
#
# Usage: _gh_prompt_view <name>
_gh_prompt_view() {
	local name="$1"
	local prompt_dir
	local prompt_file

	if [[ -z "$name" ]]; then
		gum log --level error "Prompt name required"
		gum log --level info "Usage: gh assistant prompt view <name>"
		return 1
	fi

	prompt_dir=$(_get_prompt_dir)
	# Convert to lowercase for case-insensitive matching
	name=$(echo "$name" | tr '[:upper:]' '[:lower:]')
	prompt_file="$prompt_dir/${name}.md"

	if [[ ! -f "$prompt_file" ]]; then
		gum log --level error "Prompt not found: $name"
		gum log --level info "Run 'gh assistant prompt list' to see available prompts"
		return 1
	fi

	# Use glow for rendering if available, otherwise cat
	if command -v glow &>/dev/null; then
		glow "$prompt_file"
	else
		cat "$prompt_file"
	fi
}

# Get a prompt's file path
#
# Returns the absolute path to a prompt file. Useful for scripting
# and piping to other commands.
#
# Usage: _gh_prompt_get <name>
# Example: cat "$(gh assistant prompt get gh_commit)"
_gh_prompt_get() {
	local name="$1"
	local prompt_dir
	local prompt_file

	if [[ -z "$name" ]]; then
		gum log --level error "Prompt name required"
		gum log --level info "Usage: gh assistant prompt get <name>"
		return 1
	fi

	prompt_dir=$(_get_prompt_dir)
	# Convert to lowercase for case-insensitive matching
	name=$(echo "$name" | tr '[:upper:]' '[:lower:]')
	prompt_file="$prompt_dir/${name}.md"

	if [[ ! -f "$prompt_file" ]]; then
		gum log --level error "Prompt not found: $name"
		gum log --level info "Run 'gh assistant prompt list' to see available prompts"
		return 1
	fi

	realpath "$prompt_file"
}

# Show prompt help
_gh_prompt_help() {
	cat <<'EOF'
gh assistant prompt - Manage prompt templates

USAGE:
    gh assistant prompt <command> [name]

COMMANDS:
    list        List all available prompts
    view        Display a prompt's content (rendered with glow if available)
    get         Return the file path of a prompt

EXAMPLES:
    gh assistant prompt list
    gh assistant prompt view gh_commit
    gh assistant prompt get gh_pr_ready
    cat "$(gh assistant prompt get gh_commit)"
EOF
}

# Prompt subcommand handler
#
# Routes prompt subcommands (list, view, get) to their appropriate
# handler functions. Shows help for unknown commands.
#
# Usage: _gh_prompt <subcommand> [name]
_gh_prompt() {
	local subcommand="$1"
	shift

	case $subcommand in
	list)
		_gh_prompt_list "$@"
		;;
	view)
		_gh_prompt_view "$@"
		;;
	get)
		_gh_prompt_get "$@"
		;;
	--help | -h | help | "")
		_gh_prompt_help
		;;
	*)
		gum log --level error "Unknown prompt command '$subcommand'"
		gum log --level info "Available commands: list, view, get"
		gum log --level info "Run 'gh assistant prompt --help' for usage information"
		exit 1
		;;
	esac
}
