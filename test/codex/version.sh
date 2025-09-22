#!/bin/bash

set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "version" codex --version | grep 0.39.0

# Report result
reportResults
