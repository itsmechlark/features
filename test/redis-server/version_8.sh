#!/bin/bash

set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "server" redis-server -v | grep "^Redis server v=8"
check "client" redis-cli -v | grep "^redis-cli 8"

# Report result
reportResults