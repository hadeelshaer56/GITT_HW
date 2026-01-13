#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSV_FILE="${SCRIPT_DIR}/tasks.csv"

usage() {
  echo "Usage: ./commit.sh <TASK_ID> \"<Optional Message>\""
  exit 1
}

# --- args ---
if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
fi

TASK_ID="$1"
OPT_MSG="${2-}"   # optional, can be empty

if [[ ! "$TASK_ID" =~ ^[0-9]+$ ]]; then
  echo "ERROR: TASK_ID must be a number"
  exit 2
fi

if [[ ! -f "$CSV_FILE" ]]; then
  echo "ERROR: CSV file not found: $CSV_FILE"
  exit 3
fi

# --- find row by TaskID ---
# Expected CSV headers: RepoPath,GitHubURL,Developer,Branch,Description,TaskID
# We search by last column == TASK_ID (more robust if commas appear in description? assumes no commas or proper CSV)
ROW="$(awk -F',' -v id="$TASK_ID" 'NR>1 {gsub(/\r/,""); if ($NF==id) {print; exit}}' "$CSV_FILE" || true)"

if [[ -z "$ROW" ]]; then
  echo "ERROR: TASK_ID $TASK_ID was not found in CSV"
  exit 4
fi

# --- parse fields ---
# If your CSV may contain commas inside quotes, we’ll replace parsing method later.
RepoPath="$(echo "$ROW" | cut -d',' -f1)"
GitHubURL="$(echo "$ROW" | cut -d',' -f2)"
Developer="$(echo "$ROW" | cut -d',' -f3)"
Branch="$(echo "$ROW" | cut -d',' -f4)"
Description="$(echo "$ROW" | cut -d',' -f5)"
TaskID="$(echo "$ROW" | cut -d',' -f6)"

# trim spaces
trim() { echo "$1" | sed 's/^ *//; s/ *$//'; }
RepoPath="$(trim "$RepoPath")"
GitHubURL="$(trim "$GitHubURL")"
Developer="$(trim "$Developer")"
Branch="$(trim "$Branch")"
Description="$(trim "$Description")"
TaskID="$(trim "$TaskID")"

if [[ -z "$RepoPath" || -z "$GitHubURL" || -z "$Developer" || -z "$Branch" || -z "$Description" || -z "$TaskID" ]]; then
  echo "ERROR: Invalid CSV row for TASK_ID $TASK_ID (one or more required fields are empty)"
  exit 8
fi

echo "=== Selected Task (from CSV) ==="
echo "TaskID:      $TaskID"
echo "RepoPath:    $RepoPath"
echo "GitHubURL:   $GitHubURL"
echo "Developer:   $Developer"
echo "Branch:      $Branch"
echo "Description: $Description"
echo "OptionalMsg: $OPT_MSG"
echo "================================"

if [[ ! -d "$RepoPath" ]]; then
  echo "ERROR: RepoPath does not exist: $RepoPath"
  exit 5
fi

# --- go to repo ---
cd "$RepoPath"

if [[ ! -d ".git" ]]; then
  echo "ERROR: RepoPath is not a git repository (missing .git): $RepoPath"
  exit 6
fi

# --- ensure remote exists (origin) ---
if ! git remote get-url origin >/dev/null 2>&1; then
  echo "INFO: remote 'origin' not found. Adding origin = $GitHubURL"
  git remote add origin "$GitHubURL"
fi

# --- fetch and checkout/create branch ---
git fetch origin >/dev/null 2>&1 || true

if git show-ref --verify --quiet "refs/heads/$Branch"; then
  git checkout "$Branch" >/dev/null
else
  # if exists on remote, track it; else create new
  if git ls-remote --exit-code --heads origin "$Branch" >/dev/null 2>&1; then
    git checkout -b "$Branch" "origin/$Branch" >/dev/null
  else
    git checkout -b "$Branch" >/dev/null
  fi
fi

# --- count existing commits for this TASK_ID in commit messages ---
# If the repo has no commits yet, git log fails; treat as 0.
if git rev-parse --verify HEAD >/dev/null 2>&1; then
  EXISTING_COMMITS="$(git log --pretty=%s | grep -E "^${TASK_ID} -" | wc -l | tr -d ' ')"
else
  EXISTING_COMMITS=0
fi

# --- build commit message ---
NOW="$(date '+%Y-%m-%d %H:%M')"
BASE_MSG="${TASK_ID} - ${NOW} - ${Branch} - ${Developer} - ${Description}"
if [[ -n "$OPT_MSG" ]]; then
  COMMIT_MSG="${BASE_MSG} - ${OPT_MSG}"
else
  COMMIT_MSG="${BASE_MSG}"
fi

echo "Existing commits for TASK_ID $TASK_ID: $EXISTING_COMMITS"
echo "Commit message:"
echo "$COMMIT_MSG"

# --- stage changes and commit ---
git add -A

# if nothing to commit, fail gracefully
if git diff --cached --quiet; then
  echo "ERROR: No changes to commit (working tree clean)."
  exit 7
fi

git commit -m "$COMMIT_MSG" >/dev/null

HASH="$(git rev-parse HEAD)"
echo "Commit created successfully."
echo "Commit hash: $HASH"

# --- push ---
# First push will create the branch on the remote if it doesn't exist yet.
git push -u origin "$Branch" >/dev/null
echo "Push to GitHub completed successfully."