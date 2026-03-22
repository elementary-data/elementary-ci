#!/usr/bin/env bash
# Elementary CI Review - core logic
# Called by both the GitHub Action and GitLab CI component.
#
# Required environment variables (set by the wrapper):
#   REPOSITORY               Repository identifier (e.g. "owner/repo")
#   BRANCH                   Branch name to review
#   ELEMENTARY_API_KEY       Elementary account API key
#   COMMENT_MARKER           HTML marker for idempotency, e.g. <!-- elementary-mr-review -->
#   POST_COMMENT_URL         API URL to POST a new comment
#   LIST_COMMENTS_URL        API URL to GET existing comments (for idempotency check)
#   UPDATE_COMMENT_URL_TPL   URL template for updating a comment, with {id} placeholder
#   AUTH_HEADER_NAME         Header name:  "Authorization" (GitHub) | "PRIVATE-TOKEN" or "JOB-TOKEN" (GitLab)
#   AUTH_HEADER_VALUE        Header value: "Bearer <token>" (GitHub) | "<token>" (GitLab)

set -euo pipefail

if [ -z "${ELEMENTARY_API_KEY:-}" ]; then
  echo "ERROR: ELEMENTARY_API_KEY is not set." >&2
  exit 1
fi

if [ -z "${REPOSITORY:-}" ] || [ -z "${BRANCH:-}" ]; then
  echo "ERROR: REPOSITORY and BRANCH must be set." >&2
  exit 1
fi

export COMMENT_FILE="/tmp/elementary-comment.md"

# Step 1: Elementary API generates the comment
RESPONSE=$(curl -sf --max-time 120 \
  -X POST \
  -H "Authorization: Bearer ${ELEMENTARY_API_KEY}" \
  -H "Content-Type: application/json" \
  --data-raw "{\"repository\": \"${REPOSITORY}\", \"branch\": \"${BRANCH}\"}" \
  "https://prod.api.elementary-data.com/api/v1/ci/review") || {
  echo "ERROR: Elementary API request failed." >&2
  exit 1
}

printf '%s' "${RESPONSE}" | jq -r '.comment' > "${COMMENT_FILE}"

if [ ! -s "${COMMENT_FILE}" ]; then
  echo "ERROR: Elementary API returned empty comment." >&2
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
        try {
          resolve(text ? JSON.parse(text) : {});
        } catch (e) {
          console.error(`Failed to parse JSON from ${method} ${reqUrl}: ${text.slice(0, 500)}`);
          reject(new Error(`Invalid JSON response from ${reqUrl}`));
        }
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
