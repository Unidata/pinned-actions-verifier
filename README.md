# Pinned Actions Verifier

This tool helps ensure your GitHub Actions workflows are secure by verifying that all external actions are pinned to a full commit SHA.
It also validates that the pinned SHA exists on the default branch of the repository.
This project was largely bootstrapped using Junie, the AI coding agent by JetBrains.

## Features

- Verifies that external GitHub Actions are pinned to a 40-character commit SHA.
- Checks if the pinned SHA is valid and reachable from the default branch of the action's repository using the GitHub API.
- Skips local actions (starting with `./` or `../`).
- Supports running against a single file or automatically finding all workflows in `.github/workflows`.
- Can use a `TOKEN` to avoid API rate limiting.

## Prerequisites

- `bash`
- `curl`
- `jq` (command-line JSON processor)

## Usage

### GitHub Action Workflow Example:

```yaml
on:
  pull_request:

permissions:
  contents: read

jobs:
  verify-pinned-actions:
    name: Verify Pinned Actions
    runs-on: ubuntu-slim
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
      - uses: unidata/pinned-actions-verifier@f35d45122e5b5db9d5c1726cbf890d3d4d980568 # v1.0.0
```

### Run against all workflows
If no argument is provided, the script searches for all `.yml` and `.yaml` files in the `.github/workflows` directory.

```bash
./verify-action-sha.sh
```

### Run against a specific file
You can pass the path to a specific workflow file as an argument.

```bash
./verify-action-sha.sh .github/workflows/ci.yml
```

### Environment Variables

#### `TOKEN`
By default, the script will use an internal GitHub token if one is set.
For higher rate limits and to access private repositories, you can set your own GitHub token.
When running locally for debugging, you can set the `TOKEN` environment variable like so:

```bash
TOKEN="your_personal_access_token" bash verify-action-sha.sh
```

## Exit Codes

- `0`: All external actions are pinned to valid SHAs on the default branch.
- `1`: One or more actions are not pinned correctly, or verification failed.

## Testing

The project includes a `run-tests.sh` script to verify the tool's behavior against valid and invalid pinning in workflows.

```bash
./run-tests.sh
```
