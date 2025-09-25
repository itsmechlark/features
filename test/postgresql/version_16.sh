#!/bin/bash

set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "etc" ls /etc/postgresql | grep 16
check "client" psql --version | grep 16
check "data" sudo cat /var/lib/postgresql/data/PG_VERSION | grep 16
check "pq-init-exists" bash -c "ls /usr/local/share/pq-init.sh"

# Report result
reportResults
