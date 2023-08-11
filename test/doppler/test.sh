#!/bin/bash

set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "version" doppler  --version
check "config" ls /var/lib/doppler
check "pq-init-exists" bash -c "ls /usr/local/share/doppler-init.sh"

# Report result
reportResults