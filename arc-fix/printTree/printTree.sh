#!/bin/bash

# Tree printer with colorized console output and Markdown export
# Excludes files listed in .gitignore using git check-ignore
# Outputs to README.md in the target directory

dir="${1:-.}"
output_file="$dir/README.md"
temp_output=$(mktemp)

# ANSI color codes
BLACK='\u001b[30m'
RED='u001b[30m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
MAGENTA='\033[1;35m'
WHITE='\033[1;37m'
RESET='\033[0m'
BOLD='u001b[30m'
UNDERLINE='\u001b[4m'

# Get color based on file extension
get_color() {
  case "$1" in
    *.js) echo "$YELLOW" ;;
    *.ts) echo "$BLUE" ;;
    *.tsx) echo "$CYAN" ;;
    *.css) echo "$MAGENTA" ;;
    *.md) echo "$GREEN" ;;
    *.html) echo "RED" ;;
    *) echo "$WHITE" ;;
  esac
}

# Check if a file should be ignored by .gitignore
is_ignored() {
  if [ -d "$dir/.git" ]; then
    git check-ignore -q "$1" && return 0
  fi
  return 1
}

# Print tree with depth limit and relative formatting
print_tree() {
  local directory=$1
  local prefix=$2
  local current_depth=$3

  # Only allow max depth = 3 (i.e., depth 0 = root, 1 = children, 2 = grandchildren)
  if [ "$current_depth" -ge 3 ]; then
    return
  fi

  IFS=$'\n' read -d '' -r -a items < <(
    find "$directory" -mindepth 1 -maxdepth 1 \
      \( -name ".git" -o -name "node_modules" \) -prune -o \
      ! -name ".gitignore" -print | sort && printf '\0'
  )

  local filtered=()
  for item in "${items[@]}"; do
    if ! is_ignored "$item"; then
      filtered+=("$item")
    fi
  done

  local total=${#filtered[@]}
  local count=0

  for item in "${filtered[@]}"; do
    count=$((count + 1))
    local base=$(basename "$item")
    local connector="├──"
    local subprefix="$prefix│   "

    if [ "$count" -eq "$total" ]; then
      connector="└──"
      subprefix="$prefix    "
    fi

    if [ -d "$item" ]; then
      echo -e "${prefix}${connector} ${BLUE}${base}${RESET}/"
      echo "${prefix}${connector} ${base}/" >> "$temp_output"
      print_tree "$item" "$subprefix" $((current_depth + 1))
    else
      local color=$(get_color "$base")
      echo -e "${prefix}${connector} ${color}${base}${RESET}"
      echo "${prefix}${connector} ${base}" >> "$temp_output"
    fi
  done
}

# Start printing from base directory
basename_dir=$(basename "$dir")
echo -e "${BLUE}${basename_dir}${RESET}/"
echo "$basename_dir/" > "$temp_output"
print_tree "$dir" "" 0

# Write output to README.md
{
  echo "# Project Structure"
  echo
  echo '```'
  cat "$temp_output"
  echo '```'
} > "$output_file"

rm "$temp_output"

echo -e "\n✅ Markdown tree (maxdepth 2) written to: ${GREEN}$output_file${RESET}"

