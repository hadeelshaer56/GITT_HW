#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSV_FILE="${SCRIPT_DIR}/tasks.csv"
OUT_FILE="${SCRIPT_DIR}/TASK_REPORT.md"

if [[ ! -f "$CSV_FILE" ]]; then
  echo "ERROR: CSV file not found: $CSV_FILE"
  exit 1
fi

trim() { echo "$1" | sed 's/\r//g; s/^ *//; s/ *$//'; }

now_human() { date '+%Y-%m-%d %H:%M'; }

# Write a line to BOTH terminal and file
out() {
  echo "$1"
  echo "$1" >> "$OUT_FILE"
}

: > "$OUT_FILE"
out "# TASK REPORT"
out "Generated: $(now_human)"
out ""

# Headers: RepoPath,GitHubURL,Developer,Branch,Description,TaskID
tail -n +2 "$CSV_FILE" | while IFS=',' read -r RepoPath GitHubURL Developer Branch Description TaskID; do
  RepoPath="$(trim "${RepoPath:-}")"
  GitHubURL="$(trim "${GitHubURL:-}")"
  Developer="$(trim "${Developer:-}")"
  Branch="$(trim "${Branch:-}")"
  Description="$(trim "${Description:-}")"
  TaskID="$(trim "${TaskID:-}")"

  out "## Task $TaskID — $Description"
  out ""
  out "TaskID: $TaskID"
  out "Developer:$Developer"
  out "Branch: $Branch"

  STATUS="NOT_STARTED"
  COMMITS_COUNT=0
  LAST_DATE="-"
  CHANGED_FILES=""

  if [[ -d "$RepoPath/.git" ]]; then
    pushd "$RepoPath" >/dev/null

    # ensure origin exists
    if ! git remote get-url origin >/dev/null 2>&1; then
      [[ -n "$GitHubURL" ]] && git remote add origin "$GitHubURL" >/dev/null 2>&1 || true
    fi

    git fetch origin >/dev/null 2>&1 || true

    REF=""
    if git show-ref --verify --quiet "refs/heads/$Branch"; then
      REF="$Branch"
    elif git ls-remote --exit-code --heads origin "$Branch" >/dev/null 2>&1; then
      REF="origin/$Branch"
    fi

    if [[ -n "$REF" ]] && git rev-parse --verify "$REF" >/dev/null 2>&1; then
      COMMITS_COUNT="$(git log "$REF" --pretty=%s 2>/dev/null | grep -E "^${TaskID} -" | wc -l | tr -d ' ')"
      if [[ "$COMMITS_COUNT" =~ ^[0-9]+$ ]] && [[ "$COMMITS_COUNT" -gt 0 ]]; then
        STATUS="PUSHED"
        LAST_HASH="$(git log "$REF" --grep "^${TaskID} -" -n 1 --pretty=format:%H 2>/dev/null || true)"
        LAST_DATE="$(git log "$REF" --grep "^${TaskID} -" -n 1 --pretty=format:%ad --date=format:'%Y-%m-%d %H:%M' 2>/dev/null || true)"
        if [[ -n "${LAST_HASH:-}" ]]; then
          CHANGED_FILES="$(git show --name-only --pretty='' "$LAST_HASH" 2>/dev/null | sed '/^$/d' || true)"
          [[ -z "$CHANGED_FILES" ]] && CHANGED_FILES="-"
        fi
      fi
    fi

    popd >/dev/null
  fi

  out "Commits: $COMMITS_COUNT"
  out "Last Commit: $LAST_DATE"
  out ""
  out "Changed files:"

  if [[ "$STATUS" == "NOT_STARTED" || -z "$CHANGED_FILES" ]]; then
    out "-"
  else
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      out "- $f"
    done <<< "$CHANGED_FILES"
  fi

  out ""
done

echo "Report generated: $OUT_FILE"
