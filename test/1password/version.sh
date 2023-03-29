#!/bin/bash

set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "version" op  --version | grep 2.16.0

# Report result
reportResults