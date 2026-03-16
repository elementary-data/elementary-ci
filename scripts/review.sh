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
#   AUTH_HEADER_NAME         Header name:  "Authorization" (GitHub) | "PRIVATE-TOKEN" or "JOB-TOKEN" (GitLab)
#   AUTH_HEADER_VALUE        Header value: "Bearer <token>" (GitHub) | "<token>" (GitLab)
#   MCP_CONFIG_PATH          Path to .mcp.json
#   CLAUDE_MODEL             Claude model ID to use (default: claude-haiku-4-5)

set -euo pipefail

if [ -z "${DIFF:-}" ]; then
  echo "No dbt model changes detected, skipping Elementary review."
  exit 0
fi

if [ -z "${MCP_CONFIG_PATH:-}" ]; then
  echo "ERROR: MCP_CONFIG_PATH is not set." >&2
  exit 1
fi

CLAUDE_MODEL="${CLAUDE_MODEL:-claude-haiku-4-5}"
export COMMENT_FILE="/tmp/elementary-comment.md"

# Step 1: Claude generates the comment — output captured directly from stdout
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

Output ONLY the Markdown comment — no tool calls, no explanation, just the comment.

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
" \
  --mcp-config "${MCP_CONFIG_PATH}" \
  --model "${CLAUDE_MODEL}" \
  --allowedTools "mcp__elementary__*" \
  --output-format text \
  > "${COMMENT_FILE}"

if [ ! -s "${COMMENT_FILE}" ]; then
  echo "ERROR: Claude produced empty output." >&2
  exit 1
fi

# Step 2: Post or update the comment via the API using Node.js for correct JSON encoding
node - <<'JSEOF'
const fs = require("fs");
const https = require("https");
const http = require("http");

const body = fs.readFileSync(process.env.COMMENT_FILE || "/tmp/elementary-comment.md", "utf8").trim();
const postUrl = process.env.POST_COMMENT_URL;
const listUrl = process.env.LIST_COMMENTS_URL;
const updateTpl = process.env.UPDATE_COMMENT_URL_TPL;
const authName = process.env.AUTH_HEADER_NAME;
const authValue = process.env.AUTH_HEADER_VALUE;
const marker = process.env.COMMENT_MARKER;

function api(method, reqUrl, data) {
  return new Promise((resolve, reject) => {
    const parsed = new URL(reqUrl);
    const mod = parsed.protocol === "https:" ? https : http;
    const opts = {
      method,
      hostname: parsed.hostname,
      port: parsed.port,
      path: parsed.pathname + parsed.search,
      headers: { [authName]: authValue, "Content-Type": "application/json" },
    };
    const req = mod.request(opts, (res) => {
      let chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => {
        const text = Buffer.concat(chunks).toString();
        if (res.statusCode >= 400) {
          console.error(`HTTP ${res.statusCode} ${method} ${reqUrl}: ${text}`);
          return reject(new Error(`HTTP ${res.statusCode}`));
        }
        resolve(text ? JSON.parse(text) : {});
      });
    });
    req.on("error", reject);
    if (data) req.write(JSON.stringify(data));
    req.end();
  });
}

(async () => {
  // Find existing Elementary comment
  let existingId = null;
  let page = 1;
  while (true) {
    const notes = await api("GET", `${listUrl}?per_page=100&page=${page}`);
    if (!Array.isArray(notes) || notes.length === 0) break;
    for (const note of notes) {
      if (note.body && note.body.includes(marker)) {
        existingId = note.id;
        break;
      }
    }
    if (existingId || notes.length < 100) break;
    page++;
  }

  if (existingId) {
    const updateUrl = updateTpl.replace("{id}", String(existingId));
    // GitHub uses PATCH, GitLab uses PUT
    const method = (authName === "JOB-TOKEN" || authName === "PRIVATE-TOKEN") ? "PUT" : "PATCH";
    await api(method, updateUrl, { body });
    console.log(`Updated existing comment (id: ${existingId})`);
  } else {
    const result = await api("POST", postUrl, { body });
    console.log(`Posted new comment (id: ${result.id})`);
  }
})();
JSEOF
