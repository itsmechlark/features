#!/bin/bash

set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "server" redis-server -v | grep 7
check "client" redis-cli -v | grep 7

# Report result
reportResults