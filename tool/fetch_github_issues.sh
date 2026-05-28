#!/bin/bash
set -euo pipefail

REPO="flutter/flutter"
OUT_DIR="assets/comments"
CHUNK_SIZE=64
TARGET_MESSAGES=10000

# NDJSON collection file — one JSON object per line. Appending is O(1) so the
# growth phase is linear in total messages (the previous full-array rewrite
# inside the loop was O(n^2)).
NDJSON_FILE=$(mktemp)
trap 'rm -f "$NDJSON_FILE" "${NDJSON_FILE}.array"' EXIT

mkdir -p "$OUT_DIR"

echo "Fetching top issues by comment count from $REPO..."
: > "$NDJSON_FILE"

MSG_COUNT=0
ISSUES_PAGE=1

# Paginate through issues sorted by most comments
while [ "$MSG_COUNT" -lt "$TARGET_MESSAGES" ]; do
  echo "Fetching issues page $ISSUES_PAGE..."
  ISSUES=$(gh api "repos/$REPO/issues?state=all&sort=comments&direction=desc&per_page=100&page=$ISSUES_PAGE" --jq '.[].number')

  if [ -z "$ISSUES" ]; then
    echo "No more issues found."
    break
  fi

  for ISSUE_NUM in $ISSUES; do
    if [ "$MSG_COUNT" -ge "$TARGET_MESSAGES" ]; then
      break 2
    fi

    echo "Fetching issue #$ISSUE_NUM..."

    # Get the issue itself
    ISSUE_MSG=$(gh api "repos/$REPO/issues/$ISSUE_NUM" --jq '{
      sender: .user.login,
      content: .body,
      createdAt: .created_at,
      title: .title
    }')

    TITLE=$(echo "$ISSUE_MSG" | jq -r '.title')
    SENDER=$(echo "$ISSUE_MSG" | jq -r '.sender')
    BODY=$(echo "$ISSUE_MSG" | jq -r '.content // ""')
    CREATED=$(echo "$ISSUE_MSG" | jq -r '.createdAt')

    # Skip if body is empty or sender looks like a bot
    if [ -z "$BODY" ] || echo "$SENDER" | grep -qiE 'bot$|\[bot\]'; then
      echo "  Skipping (empty or bot)"
      continue
    fi

    ISSUE_CONTENT="## $TITLE

$BODY"

    # Append issue body as a single NDJSON line (O(1) append).
    jq -nc --arg s "$SENDER" --arg c "$ISSUE_CONTENT" --arg d "$CREATED" \
      '{sender: $s, content: $c, createdAt: $d}' >> "$NDJSON_FILE"
    MSG_COUNT=$((MSG_COUNT + 1))

    # Fetch all comments (paginate)
    PAGE=1
    while true; do
      RAW=$(gh api "repos/$REPO/issues/$ISSUE_NUM/comments?per_page=100&page=$PAGE")
      RAW_COUNT=$(echo "$RAW" | jq 'length')
      if [ "$RAW_COUNT" -eq 0 ]; then
        break
      fi

      # Filter + stream as NDJSON, append directly (O(1) per comment).
      COUNT_BEFORE="$MSG_COUNT"
      while IFS= read -r LINE; do
        [ -n "$LINE" ] || continue
        echo "$LINE" >> "$NDJSON_FILE"
        MSG_COUNT=$((MSG_COUNT + 1))
      done < <(echo "$RAW" | jq -c '.[] | select(.body != null and .body != "" and (.user.login | test("bot$|\\[bot\\]"; "i") | not)) | {
        sender: .user.login,
        content: .body,
        createdAt: .created_at
      }')

      ADDED=$((MSG_COUNT - COUNT_BEFORE))
      echo "  Page $PAGE: +$ADDED comments (total: $MSG_COUNT)"

      if [ "$RAW_COUNT" -lt 100 ]; then
        break
      fi
      PAGE=$((PAGE + 1))
    done
  done

  ISSUES_PAGE=$((ISSUES_PAGE + 1))
done

echo "Total messages: $MSG_COUNT"

# Slurp NDJSON into a single JSON array once. Subsequent chunk slicing reads
# this file (small and bounded), not the growing collection file.
jq -s '.' "$NDJSON_FILE" > "${NDJSON_FILE}.array"

# Clean old chunks
rm -f "$OUT_DIR"/chunk_*.json

# Collect unique senders
SENDERS=$(jq '[.[].sender] | unique' "${NDJSON_FILE}.array")

# Split into chunks
CHUNK_INDEX=0
OFFSET=0
CHUNK_FILES="[]"

while [ "$OFFSET" -lt "$MSG_COUNT" ]; do
  CHUNK_FILE=$(printf "chunk_%03d.json" $CHUNK_INDEX)

  jq --argjson off "$OFFSET" --argjson size "$CHUNK_SIZE" \
    '[.[$off:$off+$size] | to_entries[] | {
      id: (.key + $off),
      sender: .value.sender,
      content: .value.content,
      createdAt: .value.createdAt
    }]' "${NDJSON_FILE}.array" > "$OUT_DIR/$CHUNK_FILE"

  CHUNK_FILES=$(echo "$CHUNK_FILES" | jq --arg f "$CHUNK_FILE" '. + [$f]')

  OFFSET=$((OFFSET + CHUNK_SIZE))
  CHUNK_INDEX=$((CHUNK_INDEX + 1))
done

# Write manifest
jq -n \
  --arg title "Flutter GitHub Discussions" \
  --argjson totalMessages "$MSG_COUNT" \
  --argjson chunkSize "$CHUNK_SIZE" \
  --argjson chunks "$CHUNK_FILES" \
  --argjson senders "$SENDERS" \
  '{
    title: $title,
    totalMessages: $totalMessages,
    chunkSize: $chunkSize,
    chunks: $chunks,
    senders: $senders
  }' > "$OUT_DIR/manifest.json"

echo "Done! Generated $CHUNK_INDEX chunks in $OUT_DIR/"
echo "Manifest: $OUT_DIR/manifest.json"
