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
#   MCP_CONFIG_PATH          Path to .mcp.json
#   CLAUDE_MODEL             Claude model ID to use (default: claude-haiku-4-5-latest)

set -euo pipefail

if [ -z "${DIFF:-}" ]; then
  echo "No dbt model changes detected, skipping Elementary review."
  exit 0
fi

if [ -z "${MCP_CONFIG_PATH:-}" ]; then
  echo "ERROR: MCP_CONFIG_PATH is not set." >&2
  exit 1
fi

CLAUDE_MODEL="${CLAUDE_MODEL:-claude-haiku-4-5-latest}"
COMMENT_FILE="/tmp/elementary-comment.md"

# Step 1: Claude generates the comment and writes it to a file
claude -p "
You are a data quality reviewer for a pull/merge request.

Git diff of changed dbt models:
\`\`\`diff
${DIFF}
\`\`\`

Using the Elementary MCP tools available to you, follow these steps:

0. Discover the working environment using get_environments, then scope all
   subsequent queries to the relevant environment.
1. For each changed model, use get_table_asset to retrieve its metadata and
   associated tests. Then use get_tests and get_test_execution_history to
   fetch test results and recent execution patterns.
2. Use get_asset_incidents_history to check for active or recent data quality
   incidents affecting these models.
3. Use get_downstream_assets (depth 2) to assess the blast radius of changes.
   For any renamed or removed columns, also use get_column_downstream_columns
   to identify column-level impact on downstream models and BI tools.
4. Summarize overall model health, test coverage, and change risk.

Write a Markdown comment summarising your findings to the file: ${COMMENT_FILE}

Format requirements:
- First line must be exactly: ${COMMENT_MARKER}
- Use proper Markdown with newlines between each section and list item
- Use ## headings for each section
- Use bullet points with a blank line between groups
- Include a test pass/fail table per model where data is available
- Call out downstream impact clearly
- If a model has no Elementary history yet, say so explicitly
- If the MCP server is unreachable, say so rather than omitting the section
- End with: _Posted by [Elementary CI](https://www.elementary-data.com)_

Only write the file. Do not post to any API.
" \
  --mcp-config "${MCP_CONFIG_PATH}" \
  --model "${CLAUDE_MODEL}" \
  --allowedTools "mcp__elementary__*,Bash(cat:*,echo:*,tee:*,printf:*)" \
  --output-format text

if [ ! -f "${COMMENT_FILE}" ]; then
  echo "ERROR: Claude did not write the comment file." >&2
  exit 1
fi

# Step 2: Post or update the comment via the API using Python for correct JSON encoding
python3 - <<PYEOF
import json, os, urllib.request, urllib.error

comment_file = "${COMMENT_FILE}"
post_url = "${POST_COMMENT_URL}"
list_url = "${LIST_COMMENTS_URL}"
update_tpl = "${UPDATE_COMMENT_URL_TPL}"
auth_header_name = "${AUTH_HEADER_NAME}"
auth_header_value = "${AUTH_HEADER_VALUE}"
marker = "${COMMENT_MARKER}"

with open(comment_file) as f:
    body = f.read().strip()

headers = {
    auth_header_name: auth_header_value,
    "Content-Type": "application/json",
}

def api(method, url, data=None):
    req = urllib.request.Request(url, method=method, headers=headers,
                                  data=json.dumps(data).encode() if data else None)
    try:
        resp = urllib.request.urlopen(req)
        return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code} {method} {url}: {e.read().decode()}")
        raise

# Find existing Elementary comment
existing_id = None
page = 1
while True:
    notes = api("GET", f"{list_url}?per_page=100&page={page}")
    if not notes:
        break
    for note in notes:
        if marker in note.get("body", ""):
            existing_id = note["id"]
            break
    if existing_id or len(notes) < 100:
        break
    page += 1

if existing_id:
    url = update_tpl.replace("{id}", str(existing_id))
    # GitHub uses PATCH, GitLab uses PUT
    method = "PUT" if "${AUTH_HEADER_NAME}" == "JOB-TOKEN" else "PATCH"
    result = api(method, url, {"body": body})
    print(f"Updated existing comment (id: {existing_id})")
else:
    result = api("POST", post_url, {"body": body})
    print(f"Posted new comment (id: {result.get('id')})")
PYEOF
