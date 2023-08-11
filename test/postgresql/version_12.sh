#!/bin/bash

set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "etc" ls /etc/postgresql | grep 12
check "client" psql --version | grep 12

# Report result
reportResults