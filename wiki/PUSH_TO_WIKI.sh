#!/bin/bash
# Push wiki/ directory contents to the GitHub wiki git repo.
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

echo "Copying wiki pages..."
cp wiki/*.md "$WIKI_DIR/"

# Publish image assets (#781). GitHub wikis render images committed into the
# wiki repo when referenced by a relative path, e.g. `![alt](images/foo.png)`.
# The capture step (tests/ui-smoke/capture_screenshots.py) writes PNGs here.
if [ -d wiki/images ]; then
  echo "Copying wiki images..."
  mkdir -p "$WIKI_DIR/images"
  cp -r wiki/images/. "$WIKI_DIR/images/"
fi

cd "$WIKI_DIR"
git add -A
git commit -m "Update wiki from main repo wiki/ directory" || echo "No changes to commit"
git push origin master

echo "Wiki updated successfully!"
echo "View at: https://github.com/risk-sentinel/sparc/wiki"

rm -rf "$WIKI_DIR"
