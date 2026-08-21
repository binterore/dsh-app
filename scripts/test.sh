#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p .build/tests
swiftc \
  Sources/WorkspaceModels.swift \
  Tests/TestMain.swift \
  -o .build/tests/DeepSeekCoreTests
.build/tests/DeepSeekCoreTests

swiftc \
  Sources/TerminalSession.swift \
  Tests/TerminalSmokeMain.swift \
  -o .build/tests/DeepSeekTerminalSmokeTests
.build/tests/DeepSeekTerminalSmokeTests

swift build
