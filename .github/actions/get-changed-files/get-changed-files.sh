#!/bin/bash

# Required environment variables:
# $INPUT_FILES: Pattern(s) to filter files by (e.g., "content/** data/**")
# $INPUT_PR: Pull request number (if running in PR context)
# $INPUT_HEAD: Current branch or SHA for git diff
# $INPUT_OUTPUT_FILE: Optional file to redirect output to.
# $GH_TOKEN: the access token

# Default value for files parameter if not provided
FILTER=${INPUT_FILES:-.}

# Print the filter
echo "__ using filter: __"
echo "$FILTER"

# Find the file diff in the pull request or merge group
# If its a pull request, use the faster call to the GitHub API
# For push, workflow_dispatch, and merge_group, use git diff
if [ -n "$INPUT_PR" ]
then
  echo "__ running gh pr diff __"
  DIFF=$(gh pr diff $INPUT_PR --name-only)
  if [ -z "$DIFF" ]; then
    echo "__ gh pr diff failed, falling back to git diff __"
    HEAD=$(gh pr view $INPUT_PR --json headRefName --jq .headRefName)
  fi
fi

if [ -z "$DIFF" ]; then
  echo "__ using branch name $INPUT_HEAD __"
  git fetch origin main --depth 1
  echo "__ running git diff __"

  temp_file=$(mktemp)
  git diff --name-only origin/main $INPUT_HEAD > "$temp_file" 2>/dev/null
  GIT_EXIT_CODE=$?

  DIFF=$(cat "$temp_file")
  rm -f "$temp_file"

  if [ $GIT_EXIT_CODE -ne 0 ]; then
    echo "__ git diff failed with exit code $GIT_EXIT_CODE, fetching unshallow __"
    git fetch --depth=100 origin $INPUT_HEAD
    git diff --name-only origin/main $INPUT_HEAD > "$temp_file" 2>/dev/null
    DIFF=$(cat "$temp_file")
    rm -f "$temp_file"
  else
    echo "__ git diff succeeded __"
  fi
fi

# So we can inspect the output
echo "__ DIFF found __"
echo "$DIFF"

# Filter the DIFF to just the directories specified in the input files
if [ "$FILTER" != "." ]; then
  echo "__ filtering DIFF to only include $FILTER __"
  FILTERED_DIFF=""
  IFS=$'\n'
  for file in $DIFF; do
    while IFS= read -r pattern || [ -n "$pattern" ]; do
      clean_pattern=${pattern%/}
      if [[ $file == $clean_pattern || $file == $clean_pattern/* ]]; then
        FILTERED_DIFF="$FILTERED_DIFF $file"
        break
      fi
    done <<< "$FILTER"
  done
  unset IFS
  DIFF=$FILTERED_DIFF
  echo "__ filtered DIFF __"
  echo "$DIFF"
fi

echo "__ formatting output __"
FORMATTED_DIFF=$(echo "$DIFF" | tr '\n' ' ' | tr -s ' ' | sed 's/^ *//' | sed 's/ *$//')
echo "Formatted diff: '$FORMATTED_DIFF'"

# Set the output for GitHub Actions
if [[ -n "$INPUT_OUTPUT_FILE" ]]; then
  ALL_FORMATTED=$(echo "$DIFF" | tr '\n' ' ' | tr -s ' ' | sed 's/^ *//' | sed 's/ *$//')

  # Only set outputs if there are actually changed files
  if [[ -z "$ALL_FORMATTED" ]]; then
    echo "No changed files detected, setting empty outputs"
    echo "all_changed_files=" >> "$INPUT_OUTPUT_FILE"
    echo "filtered_changed_files=" >> "$INPUT_OUTPUT_FILE"
  else
    echo "Setting non-empty outputs"
    echo "all_changed_files=$ALL_FORMATTED" >> "$INPUT_OUTPUT_FILE"
    echo "filtered_changed_files=$FORMATTED_DIFF" >> "$INPUT_OUTPUT_FILE"
  fi
else
  echo "all_changed_files='$DIFF'"
  echo "filtered_changed_files='$FORMATTED_DIFF'"
fi
