#!/usr/bin/env bash
set -euo pipefail

# Rebuild script for vectorize-io/hindsight
# Runs on existing source tree (CWD = hindsight-docs/). Installs deps and builds.
# The staging repo contains the full monorepo structure; npm install runs from root.

REPO_URL="https://github.com/vectorize-io/hindsight"
BRANCH="main"

# --- Node version ---
# Docusaurus 3.9.2 requires Node >=20
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    # shellcheck source=/dev/null
    . "$NVM_DIR/nvm.sh"
    nvm use 20 2>/dev/null || nvm install 20
fi
echo "[INFO] Using Node $(node --version)"

# --- Package manager + dependencies ---
# npm workspace monorepo: node_modules are hoisted to the workspace root (../).
# If the root package.json exists, install from there. Otherwise clone source for deps.
if [ -f "../package.json" ]; then
    echo "[INFO] Installing dependencies from workspace root..."
    (cd .. && npm install --ignore-scripts)
else
    echo "[INFO] Root package.json not found — cloning source for workspace deps..."
    TEMP_SOURCE="/tmp/hindsight-source-deps-$$"
    git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$TEMP_SOURCE"
    (cd "$TEMP_SOURCE" && npm install --ignore-scripts)
    # Copy node_modules from temp clone to parent (workspace root equivalent)
    cp -r "$TEMP_SOURCE/node_modules" ../node_modules
    rm -rf "$TEMP_SOURCE"
fi

# --- Build ---
echo "[INFO] Building Docusaurus site..."
npm run build

echo "[DONE] Build complete."
