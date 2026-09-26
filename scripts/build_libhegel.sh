#!/usr/bin/env bash
# Build the libhegel static library that hegel/libhegel links against.
#
# Uses the hegel-rust checkout at $HEGEL_RUST_DIR (default: ref/hegel-rust).
# When that directory does not exist, the pinned release tag is cloned into
# .cache/hegel-rust first. Requires cargo.
set -euo pipefail

LIBHEGEL_TAG="libhegel-v0.43.7"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUST_DIR="${HEGEL_RUST_DIR:-$ROOT/ref/hegel-rust}"
OUT_DIR="$ROOT/hegel/libhegel/lib"

if [[ ! -d "$RUST_DIR" ]]; then
	RUST_DIR="$ROOT/.cache/hegel-rust"
	if [[ ! -d "$RUST_DIR" ]]; then
		echo "Cloning hegel-rust ($LIBHEGEL_TAG) into $RUST_DIR"
		git clone --depth 1 --branch "$LIBHEGEL_TAG" https://github.com/hegeldev/hegel-rust.git "$RUST_DIR"
	fi
fi

echo "Building libhegel from $RUST_DIR"
(cd "$RUST_DIR" && cargo build -p hegeltest-c --release)

mkdir -p "$OUT_DIR"
case "$(uname -s)" in
	MINGW*|MSYS*|CYGWIN*) cp "$RUST_DIR/target/release/hegel_c.lib" "$OUT_DIR/hegel_c.lib" ;;
	*) cp "$RUST_DIR/target/release/libhegel_c.a" "$OUT_DIR/libhegel_c.a" ;;
esac
echo "Installed libhegel into $OUT_DIR"
