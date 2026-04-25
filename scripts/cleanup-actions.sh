#!/usr/bin/env bash
# Cancel all active workflow runs, then delete all runs, caches, and artifacts.
#
# Usage:
#   chmod +x cleanup-actions.sh
#   ./cleanup-actions.sh
#
# Prerequisites:
#   - GitHub CLI (gh) installed and authenticated

set -eu

if ! command -v gh &> /dev/null; then
  echo "ERROR: GitHub CLI (gh) not found. Install from https://cli.github.com"
  exit 1
fi

# ── Prompt for repo ──────────────────────────────────────────────────────────
echo ""
echo "GitHub Actions cleanup — cancels active runs, then deletes all runs,"
echo "caches, and artifacts for the given repository."
echo ""

while true; do
  read -rp "  Repository (e.g. Stensel8/Signal-Android-patches): " REPO
  [ -n "$REPO" ] && break
  echo "  Repository cannot be empty."
done

# Strip full URL prefix if user pastes a GitHub URL
REPO="${REPO#https://github.com/}"
REPO="${REPO%/}"

echo ""
echo "Target: $REPO"
read -rp "  Proceed? [y/N]: " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
echo ""

# ── Cancel in-progress and queued runs ───────────────────────────────────────
echo "[1/3] Cancelling active runs..."
ACTIVE=$(gh run list --repo "$REPO" --status in_progress --json databaseId --jq '.[].databaseId' 2>/dev/null || true)
QUEUED=$(gh run list --repo "$REPO" --status queued     --json databaseId --jq '.[].databaseId' 2>/dev/null || true)
ALL_ACTIVE=""
[ -n "$ACTIVE" ] && ALL_ACTIVE="$ACTIVE"
[ -n "$QUEUED" ] && ALL_ACTIVE="${ALL_ACTIVE:+${ALL_ACTIVE}$'\n'}${QUEUED}"

if [ -z "$ALL_ACTIVE" ]; then
  echo "  No active runs."
else
  COUNT=0
  while IFS= read -r id; do
    gh run cancel "$id" --repo "$REPO" 2>/dev/null && echo "  Cancelled run $id" && COUNT=$((COUNT+1)) || true
  done <<< "$ALL_ACTIVE"
  echo "  Cancelled $COUNT run(s). Waiting 5s for GitHub to process..."
  sleep 5
fi

# ── Delete all runs ───────────────────────────────────────────────────────────
echo "[2/3] Deleting all workflow runs..."
DELETED=0
FAILED=0
FIRST_ERR=""
IDS=$(gh api "repos/$REPO/actions/runs" --paginate --jq '.workflow_runs[].id' 2>/dev/null || true)
if [ -z "$IDS" ]; then
  echo "  No runs."
else
  while IFS= read -r id; do
    _OUT=$(gh api -X DELETE "repos/$REPO/actions/runs/$id" 2>&1) \
      && DELETED=$((DELETED+1)) \
      || { FAILED=$((FAILED+1)); [ -z "$FIRST_ERR" ] && FIRST_ERR="run $id: $_OUT"; }
    printf "\r  Deleted %d run(s)..." "$DELETED"
  done <<< "$IDS"
  echo ""
fi
[ -n "$FIRST_ERR" ] && echo "  WARNING: $FAILED failed. First error: $FIRST_ERR"
echo "  Deleted $DELETED run(s)."

# ── Delete all caches ─────────────────────────────────────────────────────────
echo "[3/3] Deleting all caches..."
if gh cache delete --all --repo "$REPO" 2>/dev/null; then
  echo "  All caches deleted."
else
  CDELETED=0
  while true; do
    IDS=$(gh cache list --repo "$REPO" --limit 100 --json id --jq '.[].id' 2>/dev/null || true)
    [ -z "$IDS" ] && break
    while IFS= read -r id; do
      gh cache delete "$id" --repo "$REPO" 2>/dev/null || true
      CDELETED=$((CDELETED+1))
      printf "\r  Deleted %d cache(s)..." "$CDELETED"
    done <<< "$IDS"
  done
  echo ""
  echo "  Deleted $CDELETED cache(s)."
fi

echo ""
echo "Done. $REPO is clean."
