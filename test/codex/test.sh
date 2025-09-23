#!/bin/bash

set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "codex version" codex --version
check "codex latest is stable" bash -c "version=\$(codex --version | awk '{print \$2}') && [[ \$version != *-* ]]"

# Report result
reportResults
