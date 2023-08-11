#!/bin/bash

set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "etc" ls /etc/postgresql | grep 13
check "client" psql --version | grep 13

# Report result
reportResults