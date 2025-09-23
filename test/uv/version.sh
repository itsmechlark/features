#!/bin/bash

set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "version" uv --version | grep 0.8
check "version" uvx --version | grep 0.8

# Report result
reportResults
