#!/bin/bash

set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "version" doppler --version | grep 3.65

# Report result
reportResults