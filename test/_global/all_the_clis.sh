#!/bin/bash

set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "check for op" op --version
check "check for doppler" doppler  --version

# Report result
reportResults