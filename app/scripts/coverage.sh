#!/bin/bash
# Generate test coverage report for Central Station
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Running tests with coverage..."
swift test --enable-code-coverage 2>&1 | tail -5

PROFDATA=$(find .build -name "default.profdata" -path "*/codecov/*" | head -1)
BIN=".build/debug/CentralStationPackageTests.xctest/Contents/MacOS/CentralStationPackageTests"

if [ ! -f "$PROFDATA" ]; then
    echo "Error: No profdata found. Did tests run?"
    exit 1
fi

echo ""
echo "=== Coverage Report (CentralStationCore) ==="
echo ""

xcrun llvm-cov report "$BIN" \
    --instr-profile="$PROFDATA" \
    --ignore-filename-regex='.build/|Tests/'

echo ""

# Export lcov for tooling integration
LCOV_PATH=".build/coverage.lcov"
xcrun llvm-cov export "$BIN" \
    --instr-profile="$PROFDATA" \
    --ignore-filename-regex='.build/|Tests/' \
    --format=lcov \
    > "$LCOV_PATH"

echo "LCOV data written to $LCOV_PATH"
