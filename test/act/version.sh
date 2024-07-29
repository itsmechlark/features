#!/bin/bash

set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "version" act --version | grep 0.2.64

# Report result
reportResults
