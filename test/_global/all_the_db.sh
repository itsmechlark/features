#!/bin/bash

set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "check for redis-server" redis-server --version
check "check for psql" psql --version

# Report result
reportResults