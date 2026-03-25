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

exit_code=0

for file in $workflow_files; do
  echo "Checking $file..."

  # Parsing to extract action names/references from 'uses:' lines
  # This handles trailing comments and whitespace, and ignores 'uses:' within run: blocks
  actions=$(grep -E '^\s*-\s*uses:|[[:space:]]uses:' "$file" | sed -E 's/.*uses:[[:space:]]*//' | sed 's/#.*//' | sed 's/[[:space:]]*$//')

  for action in $actions; do
    # Skip local actions starting with ./ or ../
    if [[ $action == ./* ]] || [[ $action == ../* ]]; then
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

    # 2. check that the github action is SHA pinned (40 characters of hex)
    if [[ ! "$ref_part" =~ ^[0-9a-f]{40}$ ]]; then
      echo "    [ERROR] Not pinned to a SHA: $ref_part"
      exit_code=1
      continue
    fi

    # 3. that the SHA is valid and belongs to the main repository for the github action
    # 4. that the SHA exists on the default branch of the repository

    # First get default branch and repo info
    repo_api_url="https://api.github.com/repos/$repo_part"
    repo_info=$(curl -s "${auth_header[@]}" "$repo_api_url")

    if echo "$repo_info" | grep -q '"message": "Not Found"'; then
      echo "    [ERROR] Repository $repo_part not found"
      exit_code=1
      continue
    elif echo "$repo_info" | grep -q '"message": "API rate limit exceeded"'; then
      echo "    [ERROR] API rate limit exceeded. Please provide a TOKEN."
      exit_code=1
      break 2
    fi

    default_branch=$(echo "$repo_info" | jq -r '.default_branch')

    if [ -z "$default_branch" ] || [ "$default_branch" == "null" ]; then
      echo "    [ERROR] Could not determine default branch for $repo_part"
      exit_code=1
      continue
    fi

    # Check if SHA is reachable from default branch using comparison
    compare_url="https://api.github.com/repos/${repo_part}/compare/${default_branch}...${ref_part}"
    compare_info=$(curl -s "${auth_header[@]}" "$compare_url")

    status=$(echo "$compare_info" | jq -r '.status')

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
done

exit $exit_code
