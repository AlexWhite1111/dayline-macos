#!/bin/zsh
set -euo pipefail
PROJECT_ROOT=${0:A:h:h}
cd "$PROJECT_ROOT"
swift test
swift build -c release
BIN_PATH=$(swift build -c release --show-bin-path)
python3 scripts/smoke-automation.py "$BIN_PATH"
print 'Checks passed.'
