#!/bin/bash

set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "etc" ls /etc/postgresql

# Report result
reportResults
