#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift build
BIN_DIR="$(swift build --show-bin-path)"
CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT
# Compile the production code with an assertion runner instead of the app entry point.
SOURCES=()
while IFS= read -r source; do
    SOURCES+=("$source")
done < <(find Sources/StickyNotes -name '*.swift' ! -name 'StickyNotesApp.swift')
swiftc -parse-as-library "${SOURCES[@]}" \
    "$BIN_DIR/StickyNotes.build/DerivedSources/resource_bundle_accessor.swift" \
    Tests/NoteInteractionChecks.swift -o "$CHECK_DIR/check-interaction"
"$CHECK_DIR/check-interaction"
