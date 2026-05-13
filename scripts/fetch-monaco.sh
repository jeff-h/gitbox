#!/usr/bin/env bash
# Downloads Monaco Editor into Resources/MonacoDiff/vs/ for the built-in diff
# viewer. Idempotent: skips work if the expected version is already present.
# Used both as a manual setup step and as an Xcode "Run Script" build phase.
set -euo pipefail

MONACO_VERSION="${MONACO_VERSION:-0.45.0}"

# Resolve project root (works whether invoked directly or via Xcode).
if [ -n "${PROJECT_DIR:-}" ]; then
    ROOT="$PROJECT_DIR"
else
    ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi

DEST="$ROOT/Resources/MonacoDiff/vs"
STAMP="$ROOT/Resources/MonacoDiff/.monaco-version"

if [ -d "$DEST" ] && [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$MONACO_VERSION" ]; then
    echo "Monaco $MONACO_VERSION already present at $DEST"
    exit 0
fi

echo "Fetching monaco-editor $MONACO_VERSION..."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

curl -fsSL "https://registry.npmjs.org/monaco-editor/-/monaco-editor-${MONACO_VERSION}.tgz" \
    -o "$TMP/monaco.tgz"
tar -xzf "$TMP/monaco.tgz" -C "$TMP"

rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")"
mv "$TMP/package/min/vs" "$DEST"
echo "$MONACO_VERSION" > "$STAMP"

echo "Monaco $MONACO_VERSION installed at $DEST"
