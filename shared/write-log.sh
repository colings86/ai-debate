#!/usr/bin/env bash
# write-log.sh — Atomically appends a JSONL entry to shared/debate-log.jsonl
#
# Usage:
#   ./shared/write-log.sh <phase> <speaker> <type> <content_file> [sources_json] [rebuttal_to_seq] [target_seq]
#
# Arguments:
#   phase            — debate phase (e.g. "opening", "rebuttal", "closing", "system")
#   speaker          — agent name (chair, promoter, detractor, reporter, verifier)
#   type             — entry type (see CLAUDE.md for full list)
#   content_file     — path to a file containing the entry's content (avoids quoting issues)
#   sources_json     — optional JSON array of source objects, e.g. '[{"url":"https://...","title":"..."}]'
#                      pass "null" or omit to leave empty
#   rebuttal_to_seq  — optional seq number being rebutted (integer or "")
#   target_seq       — optional seq number being challenged/verified (integer or "")
#
# Outputs the assigned seq number to stdout on success.
# Exits non-zero on error.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/debate-log.jsonl"
LOCK_FILE="${SCRIPT_DIR}/debate-log.lock"

# --- Validate arguments ---
if [[ $# -lt 4 ]]; then
  echo "Usage: write-log.sh <phase> <speaker> <type> <content_file> [sources_json] [rebuttal_to_seq] [target_seq]" >&2
  exit 1
fi

PHASE="$1"
SPEAKER="$2"
TYPE="$3"
CONTENT_FILE="$4"
SOURCES_JSON="${5:-null}"
ARG_REBUTTAL_TO_SEQ="${6:-}"
ARG_TARGET_SEQ="${7:-}"

if [[ ! -f "$CONTENT_FILE" ]]; then
  echo "Error: content_file '$CONTENT_FILE' not found" >&2
  exit 1
fi

CONTENT="$(cat "$CONTENT_FILE")"

# --- Build the JSONL entry using flock for atomic append ---
(
  flock -x 200

  # Compute seq from current line count (0-indexed)
  if [[ -f "$LOG_FILE" ]]; then
    SEQ=$(wc -l < "$LOG_FILE" | tr -d ' ')
  else
    SEQ=0
  fi

  TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  # Build optional fields from positional arguments
  OPTIONAL_FIELDS=""
  if [[ -n "$ARG_REBUTTAL_TO_SEQ" ]]; then
    OPTIONAL_FIELDS="${OPTIONAL_FIELDS}, \"rebuttal_to_seq\": ${ARG_REBUTTAL_TO_SEQ}"
  fi
  if [[ -n "$ARG_TARGET_SEQ" ]]; then
    OPTIONAL_FIELDS="${OPTIONAL_FIELDS}, \"target_seq\": ${ARG_TARGET_SEQ}"
  fi

  # Escape content for JSON (handles backslashes, quotes, newlines, tabs, etc.)
  ESCAPED_CONTENT=$(printf '%s' "$CONTENT" \
    | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))')

  # Build and append the JSONL entry
  printf '{"seq":%d,"timestamp":"%s","phase":"%s","speaker":"%s","type":"%s","content":%s,"sources":%s%s}\n' \
    "$SEQ" \
    "$TIMESTAMP" \
    "$PHASE" \
    "$SPEAKER" \
    "$TYPE" \
    "$ESCAPED_CONTENT" \
    "$SOURCES_JSON" \
    "$OPTIONAL_FIELDS" \
    >> "$LOG_FILE"

  # Print assigned seq to stdout for callers to reference
  echo "$SEQ"

) 200>"$LOCK_FILE"
