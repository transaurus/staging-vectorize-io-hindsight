#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/vectorize-io/hindsight"
BRANCH="main"
REPO_DIR="source-repo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Clone (skip if already exists) ---
if [ ! -d "$REPO_DIR" ]; then
    git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$REPO_DIR"
fi

cd "$REPO_DIR"

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
# npm workspace monorepo; hindsight-docs is one workspace.
# Skip prepare script (setup-hooks.sh) since we're not in a git dev environment.
echo "[INFO] Installing dependencies from root (npm workspaces)..."
npm install --ignore-scripts

# --- Apply fixes.json if present ---
FIXES_JSON="$SCRIPT_DIR/fixes.json"
if [ -f "$FIXES_JSON" ]; then
    echo "[INFO] Applying content fixes..."
    node -e "
    const fs = require('fs');
    const path = require('path');
    const fixes = JSON.parse(fs.readFileSync('$FIXES_JSON', 'utf8'));
    for (const [file, ops] of Object.entries(fixes.fixes || {})) {
        if (!fs.existsSync(file)) { console.log('  skip (not found):', file); continue; }
        let content = fs.readFileSync(file, 'utf8');
        for (const op of ops) {
            if (op.type === 'replace' && content.includes(op.find)) {
                content = content.split(op.find).join(op.replace || '');
                console.log('  fixed:', file, '-', op.comment || '');
            }
        }
        fs.writeFileSync(file, content);
    }
    for (const [file, cfg] of Object.entries(fixes.newFiles || {})) {
        const c = typeof cfg === 'string' ? cfg : cfg.content;
        fs.mkdirSync(path.dirname(file), {recursive: true});
        fs.writeFileSync(file, c);
        console.log('  created:', file);
    }
    "
fi

# --- Fix versioned sidebars (JSON structural fix for duplicate keys) ---
# The versioned sidebar JSONs also have duplicate Retain/Recall/Reflect labels
# that need unique key attributes added. This requires JSON manipulation.
echo "[INFO] Fixing versioned sidebar JSON files..."
node -e "
const fs = require('fs');
const path = require('path');

const keyMap = {
    'developer/retain': 'architectureRetain',
    'developer/retrieval': 'architectureRecall',
    'developer/reflect': 'architectureReflect',
    'developer/api/retain': 'apiRetain',
    'developer/api/recall': 'apiRecall',
    'developer/api/reflect': 'apiReflect',
};

function fixItems(items) {
    return items.map(item => {
        if (typeof item !== 'object' || item === null) return item;
        if (item.type === 'category' && Array.isArray(item.items)) {
            return { ...item, items: fixItems(item.items) };
        }
        if (item.type === 'doc' && item.id && keyMap[item.id]) {
            const fixed = { ...item, key: keyMap[item.id] };
            console.log('  Added key', keyMap[item.id], 'to doc', item.id);
            return fixed;
        }
        return item;
    });
}

const versionedDir = 'hindsight-docs/versioned_sidebars';
if (!fs.existsSync(versionedDir)) {
    console.log('  No versioned_sidebars directory found, skipping.');
} else {
    for (const filename of ['version-0.3-sidebars.json', 'version-0.4-sidebars.json']) {
        const filepath = path.join(versionedDir, filename);
        if (!fs.existsSync(filepath)) {
            console.log('  Skipping', filename, '(not found)');
            continue;
        }
        const data = JSON.parse(fs.readFileSync(filepath, 'utf8'));
        const fixed = {};
        for (const [k, v] of Object.entries(data)) {
            fixed[k] = Array.isArray(v) ? fixItems(v) : v;
        }
        fs.writeFileSync(filepath, JSON.stringify(fixed, null, 2));
        console.log('  Fixed', filename);
    }
}
"

echo "[DONE] Repository is ready for docusaurus commands."
