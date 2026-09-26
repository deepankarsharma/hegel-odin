#!/usr/bin/env bash
# Fetch hegel-odin from GitHub into deps/hegel-odin and build its libhegel.
#
#   ./setup.sh            clone if missing, build libhegel if missing
#   ./setup.sh --update   also pull the latest $HEGEL_ODIN_REF
#
# $HEGEL_ODIN_REPO and $HEGEL_ODIN_REF pick the repository and branch or tag.
# $HEGEL_RUST_DIR, if set, is passed through to hegel-odin's build script to
# reuse an existing hegel-rust checkout. Requires git and cargo.
set -euo pipefail

HEGEL_ODIN_REPO="${HEGEL_ODIN_REPO:-https://github.com/deepankarsharma/hegel-odin.git}"
HEGEL_ODIN_REF="${HEGEL_ODIN_REF:-main}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HERE/deps/hegel-odin"

if [[ ! -d "$DEST/.git" ]]; then
	echo "Cloning $HEGEL_ODIN_REPO ($HEGEL_ODIN_REF) into $DEST"
	git clone --depth 1 --branch "$HEGEL_ODIN_REF" "$HEGEL_ODIN_REPO" "$DEST"
elif [[ "${1:-}" == "--update" ]]; then
	echo "Updating $DEST to $HEGEL_ODIN_REF"
	git -C "$DEST" fetch --depth 1 origin "$HEGEL_ODIN_REF"
	git -C "$DEST" checkout --detach FETCH_HEAD
fi
echo "Using hegel-odin $(git -C "$DEST" rev-parse --short HEAD)"

if [[ ! -f "$DEST/hegel/libhegel/lib/libhegel_c.a" && ! -f "$DEST/hegel/libhegel/lib/hegel_c.lib" ]] || [[ "${1:-}" == "--update" ]]; then
	"$DEST/scripts/build_libhegel.sh"
fi
