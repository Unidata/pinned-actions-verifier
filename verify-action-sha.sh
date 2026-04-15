#!/usr/bin/env bash
# Copyright (c) 2026 University Corporation for Atmospheric Research/Unidata
# See LICENSE for license information.

# Check for required commands
declare -a required_cmds=("curl" "jq")
for cmd in "${required_cmds[@]}"; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: required command '$cmd' not found." >&2
    exit 1
  fi
done

# Check for GitHub token
auth_header=()
if [ -n "$TOKEN" ]; then
  auth_header=(-H "Authorization: token $TOKEN")
else
  echo "Warning: TOKEN is not set. API rate limits will be restrictive."
fi

# Run against a single workflow (as passed to the script)
# or find all workflow files
if [ -z "$1" ]; then
  workflow_files=$(find .github/workflows -name "*.yml" -o -name "*.yaml")
else
  workflow_files="$1"
fi
if [ -z "$workflow_files" ]; then
  echo "No workflow files found in .github/workflows"
  exit 0
fi

set -o pipefail

check_workflow_file() {
  # Declare local variables
  # Input / function state
  local file="$1"
  local exit_code=0
  local -a actions=()

  # Workflow parsing
  local action action_dir

  # GitHub repository / API data
  local repo_part ref_part repo_only
  local repo_api_url repo_info default_branch compare_url status

  echo "Checking $file..."

  # Parsing to extract action names/references from 'uses:' lines
  # This handles trailing comments and whitespace
  actions=$(grep -E '^\s*-\s*uses:|[[:space:]]uses:' "$file" | sed -E 's/.*uses:[[:space:]]*//' | sed 's/#.*//' | sed 's/[[:space:]]*$//')

  for action in $actions; do
    # Handle local actions starting with ./ or ../
    if [[ $action == ./* ]] || [[ $action == ../* ]]; then
      echo "  Action: $action"
      # The directory for the action is relative to the file containing the reference
      # However, GitHub actions are usually relative to the repository root.
      # Let's check both possibilities.
      action_dir=$(dirname "$file")/$action
      if [ ! -d "$action_dir" ]; then
        # Check relative to repo root
        action_dir=$action
      fi

      if [ -f "$action_dir/action.yml" ]; then
        if ! check_workflow_file "$action_dir/action.yml"; then
          exit_code=1
        fi
      elif [ -f "$action_dir/action.yaml" ]; then
        if ! check_workflow_file "$action_dir/action.yaml"; then
          exit_code=1
        fi
      else
        echo "      [ERROR] Local action directory $action_dir does not contain action.yml or action.yaml"
        exit_code=1
      fi
      continue
    fi

    echo "  Action: $action"

    # Check if action has a @ separator
    if [[ $action != *@* ]]; then
      echo "    [ERROR] No version specified (expected @<sha>)"
      exit_code=1
      continue
    fi

    repo_part=$(echo "$action" | cut -d'@' -f1)
    ref_part=$(echo "$action" | cut -d'@' -f2)

    # If repo_part has more than one slash, it contains a subdirectory
    # We only want the org/repo part for API calls
    repo_only=$(echo "$repo_part" | cut -d'/' -f1,2)

    # 2. check that the github action is SHA pinned (40 characters of hex)
    if [[ ! "$ref_part" =~ ^[0-9a-f]{40}$ ]]; then
      echo "    [ERROR] Not pinned to a SHA: $ref_part"
      exit_code=1
      continue
    fi

    # 3. that the SHA is valid and belongs to the main repository for the github action
    # 4. that the SHA exists on the default branch of the repository

    # First get default branch and repo info
    repo_api_url="https://api.github.com/repos/$repo_only"
    repo_info=$(curl -s "${auth_header[@]}" "$repo_api_url")

    if echo "$repo_info" | grep -q '"message": "Not Found"'; then
      echo "    [ERROR] Repository $repo_only not found"
      exit_code=1
      continue
    elif echo "$repo_info" | grep -q '"message": "API rate limit exceeded"'; then
      echo "    [ERROR] API rate limit exceeded. Please provide a TOKEN."
      exit_code=1
      break 2
    fi

    default_branch=$(echo "$repo_info" | jq -r '.default_branch')

    if [ -z "$default_branch" ] || [ "$default_branch" == "null" ]; then
      echo "    [ERROR] Could not determine default branch for $repo_only"
      exit_code=1
      continue
    fi

    # Check if SHA is reachable from default branch using comparison
    compare_url="https://api.github.com/repos/${repo_only}/compare/${default_branch}...${ref_part}"
    status=$(curl -s "${auth_header[@]}" "$compare_url" | jq -r '.status' 2>/dev/null)

    # If ref_part is on default_branch, status will be 'identical' or 'behind' (if it's an ancestor)
    # If it's not on default_branch, it might be 'ahead' or 'diverged'
    if [[ "$status" == "identical" ]] || [[ "$status" == "behind" ]]; then
      echo "    [OK] Valid SHA pinned and reachable from default branch ($default_branch)"
    else
      if [ -z "$status" ] || [ "$status" == "null" ]; then
         echo "    [ERROR] Could not verify SHA $ref_part for $repo_part (API error or SHA not found)"
      else
         echo "    [ERROR] SHA $ref_part is not on the default branch ($default_branch). Status: $status"
      fi
      exit_code=1
    fi
  done
  return $exit_code
}

for file in $workflow_files; do
  check_workflow_file "$file"
done
