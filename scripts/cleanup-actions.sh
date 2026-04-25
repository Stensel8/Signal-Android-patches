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
while true; do
  IDS=$(gh run list --repo "$REPO" --limit 100 --json databaseId --jq '.[].databaseId' 2>/dev/null || true)
  [ -z "$IDS" ] && break
  while IFS= read -r id; do
    gh api -X DELETE "repos/$REPO/actions/runs/$id" 2>/dev/null || true
    DELETED=$((DELETED+1))
    printf "\r  Deleted %d run(s)..." "$DELETED"
  done <<< "$IDS"
done
echo ""
echo "  Deleted $DELETED run(s)."

# ── Delete all caches ─────────────────────────────────────────────────────────
echo "[3/3] Deleting all caches..."
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

echo ""
echo "Done. $REPO is clean."
