#!/bin/bash
# Push wiki/ directory contents to the GitHub wiki git repo.
#
# #1061 — PUBLISHING IS NOW AUTOMATIC. .github/workflows/publish-wiki.yml
# publishes on every push to main that touches wiki/, so you should not normally
# need to run this. It is kept for local/manual recovery: a re-sync after
# someone edited the wiki in the web UI, or publishing from a machine when the
# workflow is unavailable.
#
# Prerequisites:
#   1. Initialize the wiki by visiting https://github.com/risk-sentinel/sparc/wiki
#      and creating any page (e.g., "Home") through the web UI
#   2. Run this script from the SPARC repo root
#
# Usage:
#   chmod +x wiki/PUSH_TO_WIKI.sh
#   ./wiki/PUSH_TO_WIKI.sh

set -e

WIKI_DIR=$(mktemp -d)
REPO_URL="https://github.com/risk-sentinel/sparc.wiki.git"

echo "Cloning wiki repo..."
git clone "$REPO_URL" "$WIKI_DIR"

# AUTHORITATIVE SYNC (#1061).
#
# This used to be `cp wiki/*.md "$WIKI_DIR/"` — it only ever copied INTO the
# wiki, so `git add -A` below never saw a deletion and a page removed from
# source stayed published forever. User-Guide-Trust-Store.md was deleted from
# source in f9b57321 (v1.15.0) and was still live on the wiki months later.
#
# rsync --delete makes wiki/ the single authority. Image assets (#781) ride the
# same sync: GitHub wikis render images committed into the wiki repo when
# referenced relatively, and tests/ui-smoke/capture_screenshots.py writes them
# into wiki/images.
#
# This script itself is excluded — it lives under wiki/ but is tooling, and was
# never published.
echo "Syncing wiki pages (authoritative — removals propagate)..."
rsync -a --delete \
  --exclude '.git/' \
  --exclude 'PUSH_TO_WIKI.sh' \
  wiki/ "$WIKI_DIR/"

cd "$WIKI_DIR"
git add -A
git commit -m "Update wiki from main repo wiki/ directory" || echo "No changes to commit"
git push origin master

echo "Wiki updated successfully!"
echo "View at: https://github.com/risk-sentinel/sparc/wiki"

rm -rf "$WIKI_DIR"
