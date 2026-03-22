# Elementary CI

Automated data quality review for Pull Requests and Merge Requests.

When a developer opens or updates a PR/MR touching dbt models, this action:
1. Detects changed models via `git diff`
2. Calls the Elementary API to analyse test results, active incidents, and downstream lineage
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
          elementary-api-key: ${{ secrets.ELEMENTARY_API_KEY }}
```

### Inputs

| Input | Default | Description |
|---|---|---|
| `elementary-api-key` | required | Elementary Cloud API key |
| `models-path` | `models/` | Path to dbt models directory |
| `diff-filter` | `ACMR` | git diff filter (A=added, C=copied, M=modified, R=renamed) |
| `base-ref` | PR base branch | Branch to diff against |

### Required secrets

| Secret | Description |
|---|---|
| `ELEMENTARY_API_KEY` | Elementary Cloud API key |

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
      stage: "data-quality"
```

### Inputs

| Input | Default | Description |
|---|---|---|
| `stage` | `test` | Pipeline stage |
| `models_path` | `models/` | Path to dbt models directory |
| `diff_filter` | `ACMR` | git diff filter |
| `allow_failure` | `true` | Whether to block the MR on job failure |

### Required CI/CD variables

Set these in **Settings > CI/CD > Variables** (mark sensitive ones as masked):

| Variable | Description |
|---|---|
| `ELEMENTARY_API_KEY` | Elementary Cloud API key |

`CI_JOB_TOKEN` is provided automatically. Optionally set `GITLAB_API_TOKEN` (project/group token with `api` scope) if `CI_JOB_TOKEN` lacks comment permissions.
