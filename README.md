# Elementary CI

Automated data quality review for Pull Requests and Merge Requests.

When a developer opens or updates a PR/MR touching dbt models, this action:
1. Detects changed models via `git diff`
2. Queries the Elementary MCP server for test results, active incidents, and downstream lineage
3. Posts a summary comment to the PR/MR (updates it on reruns - no spam)

---

## GitHub Actions

### Quick start

```yaml
# .github/workflows/elementary-review.yml
name: Elementary Data Quality Review

on:
  pull_request:
    paths:
      - "models/**/*.sql"
      - "models/**/*.yml"
      - "dbt_project.yml"

jobs:
  elementary-review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0          # required for git diff across branches

      - uses: elementary-data/elementary-ci@v1
        with:
          anthropic-api-key: ${{ secrets.ANTHROPIC_API_KEY }}
```

### Inputs

| Input | Default | Description |
|---|---|---|
| `anthropic-api-key` | required | Anthropic API key for Claude |
| `models-path` | `models/` | Path to dbt models directory |
| `diff-filter` | `ACM` | git diff filter (A=added, C=copied, M=modified) |
| `edr-version` | latest | Pin to a specific `elementary-data` version |
| `claude-model` | `claude-haiku-4-5-20251001` | Claude model ID |
| `mcp-config-path` | `.mcp.json` | Path to MCP config file |
| `base-ref` | PR base branch | Branch to diff against |

### Required secrets

| Secret | Description |
|---|---|
| `ANTHROPIC_API_KEY` | Anthropic API key |
| Warehouse credentials | Whatever `edr` needs to connect (e.g. `SNOWFLAKE_PASSWORD`) |

`GITHUB_TOKEN` is provided automatically by GitHub Actions.

---

## GitLab CI/CD Component

### Quick start

```yaml
# .gitlab-ci.yml
include:
  - component: gitlab.com/elementary-data/ci-components/mr-review@v1
```

That's it. Override inputs only if needed:

```yaml
include:
  - component: gitlab.com/elementary-data/ci-components/mr-review@v1
    inputs:
      models_path: "dbt/models/"
      edr_version: "0.15.0"
      claude_model: "claude-sonnet-4-6"
      stage: "data-quality"
```

### Inputs

| Input | Default | Description |
|---|---|---|
| `stage` | `test` | Pipeline stage |
| `models_path` | `models/` | Path to dbt models directory |
| `diff_filter` | `ACM` | git diff filter |
| `edr_version` | latest | Pin to a specific `elementary-data` version |
| `claude_model` | `claude-haiku-4-5-20251001` | Claude model ID |
| `mcp_config_path` | `.mcp.json` | Path to MCP config file |
| `allow_failure` | `true` | Whether to block the MR on job failure |

### Required CI/CD variables

Set these in **Settings > CI/CD > Variables** (mark sensitive ones as masked):

| Variable | Description |
|---|---|
| `ANTHROPIC_API_KEY` | Anthropic API key |
| `GITLAB_API_TOKEN` | Project/group token with `api` scope |
| Warehouse credentials | Whatever `edr` needs (e.g. `SNOWFLAKE_PASSWORD`) |

---

## MCP config

Both integrations require a `.mcp.json` file checked into your repo:

```json
{
  "mcpServers": {
    "elementary": {
      "command": "edr",
      "args": ["run-mcp"]
    }
  }
}
```

Adjust the `command` and `args` to match your `edr` version. Run `edr --help` to confirm the MCP subcommand name.

---

## Model selection

The `claude-model` / `claude_model` input accepts any Anthropic model ID.
See the [Anthropic models documentation](https://docs.anthropic.com/en/docs/about-claude/models) for available options.

| Model | When to use |
|---|---|
| `claude-haiku-4-5-20251001` | Default - fast and cost-efficient for routine reviews |
| `claude-sonnet-4-6` | Richer analysis, better reasoning about complex lineage |
| `claude-opus-4-6` | Deep investigation on critical models |
