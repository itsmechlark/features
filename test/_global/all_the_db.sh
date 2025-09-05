#!/bin/bash

set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "check for redis-server" redis-server --version
check "check for psql" psql --version
check "check for rabbitmqctl" rabbitmqctl --version

# Report result
reportResults