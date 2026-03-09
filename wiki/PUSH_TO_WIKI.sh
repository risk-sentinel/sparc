#!/bin/bash
# Push wiki/ directory contents to the GitHub wiki git repo.
#
# Prerequisites:
#   1. Initialize the wiki by visiting https://github.com/Rebel-Raiders/sparc/wiki
#      and creating any page (e.g., "Home") through the web UI
#   2. Run this script from the SPARC repo root
#
# Usage:
#   chmod +x wiki/PUSH_TO_WIKI.sh
#   ./wiki/PUSH_TO_WIKI.sh

set -e

WIKI_DIR=$(mktemp -d)
REPO_URL="https://github.com/Rebel-Raiders/sparc.wiki.git"

echo "Cloning wiki repo..."
git clone "$REPO_URL" "$WIKI_DIR"

echo "Copying wiki pages..."
cp wiki/*.md "$WIKI_DIR/"

cd "$WIKI_DIR"
git add -A
git commit -m "Update wiki from main repo wiki/ directory" || echo "No changes to commit"
git push origin master

echo "Wiki updated successfully!"
echo "View at: https://github.com/Rebel-Raiders/sparc/wiki"

rm -rf "$WIKI_DIR"
