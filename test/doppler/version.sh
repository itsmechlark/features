#!/bin/bash

set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "version" doppler --version | grep 3.66
check "config" ls /var/lib/doppler
check "user-config" ls /home/vscode/.doppler

# Report result
reportResults