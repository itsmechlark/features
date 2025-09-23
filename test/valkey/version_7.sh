#!/bin/bash

set -e

source dev-container-features-test-lib

check "valkey-server-7" bash -lc "valkey-server --version | grep 'v=7'"
check "valkey-cli-7" bash -lc "valkey-cli --version | grep '^valkey-cli 7'"

reportResults
