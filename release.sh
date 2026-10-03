#!/bin/bash
# Create a GitHub release zip for AnkiKoFlash and publish with gh.
#
# First-time setup (once per machine):
#   gh auth login
#
# Usage:
#   bash release.sh                       # bump patch, commit, tag, push, publish
#   bash release.sh 1.0.4                 # release a specific version
#   bash release.sh --publish-only        # publish zip for current _meta.lua version
#   bash release.sh --dry-run             # show planned steps only
#   bash release.sh --notes-file notes.md # custom release notes body

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
META_FILE="$SCRIPT_DIR/_meta.lua"
PLUGIN_FOLDER="AnkiKoFlash.koplugin"
ZIP_DIR="$(dirname "$SCRIPT_DIR")"

VERSION=""
PUBLISH_ONLY=0
DRY_RUN=0
SKIP_PUSH=0
NOTES_FILE=""

usage() {
    cat <<'EOF'
release.sh - Build release zip and publish to GitHub

USAGE
  bash release.sh [OPTIONS] [VERSION]

OPTIONS
  --publish-only     Publish zip for version in _meta.lua (tag must exist)
  --dry-run          Print steps without changing anything
  --skip-push        Build zip/tag locally but do not git push
  --notes-file PATH  Release notes markdown file
  -h, --help         Show this help

EXAMPLES
  bash release.sh
  bash release.sh 1.0.4
  bash release.sh --publish-only
EOF
}

step() { echo "==> $*"; }

read_meta_version() {
    sed -n 's/.*version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$META_FILE" | head -n 1
}

set_meta_version() {
    local ver="$1"
    local tmp
    tmp="$(mktemp)"
    sed -E "s/(version[[:space:]]*=[[:space:]]*\")[^\"]*(\")/\1${ver}\2/" "$META_FILE" > "$tmp"
    mv "$tmp" "$META_FILE"
}

bump_patch() {
    local cur="$1"
    local major minor patch
    IFS='.' read -r major minor patch <<< "$cur"
    patch=$((patch + 1))
    echo "${major}.${minor}.${patch}"
}

default_notes() {
    local ver="$1"
    cat <<EOF
## Install
Download \`AnkiKoFlash-v${ver}.zip\`, unzip, and copy the \`AnkiKoFlash.koplugin\` folder into your KOReader \`plugins/\` directory.

See [Getting started](https://github.com/3gnome/AnkiKoFlash.koplugin/blob/main/docs/getting-started.md) for setup.
EOF
}

ensure_gh() {
    if ! command -v gh >/dev/null 2>&1; then
        echo "ERROR: GitHub CLI (gh) not found. Install it first." >&2
        exit 1
    fi
    if ! gh auth status >/dev/null 2>&1; then
        echo "ERROR: gh is not authenticated. Run once: gh auth login" >&2
        exit 1
    fi
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --publish-only) PUBLISH_ONLY=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --skip-push) SKIP_PUSH=1; shift ;;
        --notes-file) NOTES_FILE="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        --) shift; break ;;
        -*) echo "Unknown option: $1" >&2; usage; exit 1 ;;
        *) VERSION="$1"; shift ;;
    esac
done

cd "$SCRIPT_DIR"
CURRENT="$(read_meta_version)"
if [ -z "$CURRENT" ]; then
    echo "ERROR: Could not read version from _meta.lua" >&2
    exit 1
fi

if [ "$PUBLISH_ONLY" -eq 1 ]; then
    VERSION="$CURRENT"
    step "Publish-only mode for v$VERSION"
elif [ -z "$VERSION" ]; then
    VERSION="$(bump_patch "$CURRENT")"
    step "Bumping version $CURRENT -> $VERSION"
    if [ "$DRY_RUN" -eq 0 ]; then
        set_meta_version "$VERSION"
        git add _meta.lua
        git commit -m "Bump version to $VERSION"
    fi
else
    step "Using version $VERSION"
    if [ "$VERSION" != "$CURRENT" ] && [ "$DRY_RUN" -eq 0 ]; then
        set_meta_version "$VERSION"
        git add _meta.lua
        git commit -m "Bump version to $VERSION"
    fi
fi

TAG="v$VERSION"
ZIP_NAME="AnkiKoFlash-v$VERSION.zip"
ZIP_PATH="$ZIP_DIR/$ZIP_NAME"

step "Building $ZIP_NAME"
if [ "$DRY_RUN" -eq 0 ]; then
    rm -f "$ZIP_PATH"
    git archive --format=zip --prefix="$PLUGIN_FOLDER/" -o "$ZIP_PATH" HEAD
fi

TAG_EXISTS=0
if git rev-parse "refs/tags/$TAG" >/dev/null 2>&1; then
    TAG_EXISTS=1
fi

if [ "$PUBLISH_ONLY" -eq 0 ] && [ "$TAG_EXISTS" -eq 0 ]; then
    step "Creating tag $TAG"
    if [ "$DRY_RUN" -eq 0 ]; then
        git tag -a "$TAG" -m "$TAG"
    fi
fi

if [ "$SKIP_PUSH" -eq 0 ] && [ "$PUBLISH_ONLY" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
    step "Pushing main"
    git push origin main
    if [ "$TAG_EXISTS" -eq 0 ]; then
        step "Pushing tag $TAG"
        git push origin "$TAG"
    fi
fi

ensure_gh

if [ -n "$NOTES_FILE" ] && [ -f "$NOTES_FILE" ]; then
    NOTES="$(cat "$NOTES_FILE")"
else
    NOTES="$(default_notes "$VERSION")"
fi

step "Publishing GitHub release $TAG"
if [ "$DRY_RUN" -eq 1 ]; then
    echo "Dry run complete. Would publish $ZIP_PATH as $TAG"
    exit 0
fi

if gh release view "$TAG" >/dev/null 2>&1; then
    step "Release exists; uploading asset"
    gh release upload "$TAG" "$ZIP_PATH" --clobber
else
    gh release create "$TAG" "$ZIP_PATH" --title "$TAG" --notes "$NOTES"
fi

step "Done: https://github.com/3gnome/AnkiKoFlash.koplugin/releases/tag/$TAG"
echo "Zip: $ZIP_PATH"
