# Elementary CI

Automated data quality review for Pull Requests and Merge Requests.

When a developer opens or updates a PR/MR, this action:
1. Sends the repository name and branch to the Elementary API
2. Elementary fetches the diff, analyses test results, active incidents, and downstream lineage
3. Posts a summary comment to the PR/MR (updates it on reruns - no spam)

**Prerequisites:** Connect your code repository in the Elementary Cloud UI.

---

## GitHub Actions

### Quick start

```yaml
# .github/workflows/elementary-review.yml
name: Elementary Data Quality Review

on:
  pull_request:

jobs:
  elementary-review:
    runs-on: ubuntu-latest
    steps:
      - uses: elementary-data/elementary-ci@v2
        with:
          elementary-api-key: ${{ secrets.ELEMENTARY_API_KEY }}
```

### Inputs

| Input | Default | Description |
|---|---|---|
| `elementary-api-key` | required | Elementary Cloud API key |
| `elementary-api-url` | `https://prod.api.elementary-data.com` | Elementary API base URL |
| `elementary-env-id` | none | Elementary environment ID (UUID). Required when the repository is connected to more than one environment |
| `post-inline-comments` | `true` | Post findings as review comments on the changed lines they refer to, in addition to the summary comment. Set to `false` for the summary comment only. Elementary posts these through your connected GitHub integration, so no extra token is needed. Findings that cannot be anchored to a line in the diff stay in the summary comment |

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

### Required CI/CD variables

Set these in **Settings > CI/CD > Variables** (mark sensitive ones as masked):

| Variable | Description |
|---|---|
| `ELEMENTARY_API_KEY` | Elementary Cloud API key |

`CI_JOB_TOKEN` is provided automatically. Optionally set `GITLAB_API_TOKEN` (project/group token with `api` scope) if `CI_JOB_TOKEN` lacks comment permissions.
