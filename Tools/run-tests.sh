#!/bin/bash
# Formatting checks, run headless — no app window, nothing typed into your notes.
#   ./Tools/run-tests.sh
set -e
cd "$(dirname "$0")/.."
SRC=Sources/Silica
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
# swiftc only allows top-level statements in a file called main.swift.
cp Tools/FormattingTests.swift "$OUT/main.swift"
swiftc -o "$OUT/tests" "$OUT/main.swift" \
    "$SRC/Editor.swift" "$SRC/Markdown.swift" "$SRC/Theme.swift" "$SRC/Library.swift"
"$OUT/tests"
