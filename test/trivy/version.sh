#!/bin/bash

set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "version" trivy  --version | grep 0.44

# Report result
reportResults