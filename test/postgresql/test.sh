#!/bin/bash

set -e

# Optional: Import test library
source dev-container-features-test-lib

# Feature specific tests
check "etc" ls /etc/postgresql
check "pq-init-exists" bash -c "ls /usr/local/share/pq-init.sh"

# Report result
reportResults
