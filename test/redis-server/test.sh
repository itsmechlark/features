#!/bin/bash

set -e

# Optional: Import test library
source dev-container-features-test-lib

# Feature specific tests
check "redis-init-exists" bash -c "ls /usr/local/share/redis-server-init.sh"

# Report result
reportResults
