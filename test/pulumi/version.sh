#!/bin/bash

set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "version" pulumi version | grep 3.191.0

# Report result
reportResults
