#!/usr/bin/env bash
# Elementary CI Review - core logic
# Called by both the GitHub Action and GitLab CI component.
#
# Required environment variables (set by the wrapper):
#   DIFF                     git diff output of changed dbt models
#   COMMENT_MARKER           HTML marker for idempotency, e.g. <!-- elementary-mr-review -->
#   POST_COMMENT_URL         API URL to POST a new comment
#   LIST_COMMENTS_URL        API URL to GET existing comments (for idempotency check)
#   UPDATE_COMMENT_URL_TPL   URL template for updating a comment, with {id} placeholder
#   AUTH_HEADER_NAME         Header name:  "Authorization"  (GitHub) | "PRIVATE-TOKEN" (GitLab)
#   AUTH_HEADER_VALUE        Header value: "Bearer <token>" (GitHub) | "<token>"       (GitLab)
#   MCP_CONFIG_PATH          Path to .mcp.json (default: .mcp.json)
#   CLAUDE_MODEL             Claude model ID to use (default: claude-haiku-4-5-20251001)

set -euo pipefail

if [ -z "${DIFF:-}" ]; then
  echo "No dbt model changes detected, skipping Elementary review."
  exit 0
fi

if [ -z "${MCP_CONFIG_PATH:-}" ]; then
  echo "ERROR: MCP_CONFIG_PATH is not set." >&2
  exit 1
fi

CLAUDE_MODEL="${CLAUDE_MODEL:-claude-haiku-4-5-20251001}"

claude -p "
You are a data quality reviewer for a pull/merge request.

Git diff of changed dbt models:
\`\`\`diff
${DIFF}
\`\`\`

Using the Elementary MCP tools available to you:
1. For each changed model, fetch test results from the last 7 days
2. Check for any active data quality incidents affecting these models
3. Get downstream lineage (depth 2) to assess blast radius of changes
4. Summarize overall model health

After gathering context, post a single comment via the API.

Step 1 - check for an existing Elementary comment (idempotency):
  GET ${LIST_COMMENTS_URL}
  ${AUTH_HEADER_NAME}: ${AUTH_HEADER_VALUE}

  Search the response for any comment whose body contains exactly: ${COMMENT_MARKER}
  Note its id if found.

Step 2 - post or update the comment:
  If a matching comment was found:
    PATCH/PUT ${UPDATE_COMMENT_URL_TPL}   (replace {id} with the found comment id)
  Otherwise:
    POST ${POST_COMMENT_URL}

  In both cases:
    ${AUTH_HEADER_NAME}: ${AUTH_HEADER_VALUE}
    Content-Type: application/json
    Body: {\"body\": \"<your markdown comment>\"}

Format requirements for the comment body:
- First line must be exactly: ${COMMENT_MARKER}
- Use Markdown with a clear section per changed model
- Include a test pass/fail count table per model where data is available
- Call out downstream impact (which models/dashboards are affected)
- If a model has no Elementary history yet, say so explicitly
- If the MCP server is unreachable, say so rather than omitting the section
- End with: _Posted by [Elementary CI](https://www.elementary-data.com)_
" \
  --mcp-config "${MCP_CONFIG_PATH}" \
  --model "${CLAUDE_MODEL}" \
  --allowedTools "mcp__elementary__*,Bash" \
  --output-format text
