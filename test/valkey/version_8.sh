#!/bin/bash

set -e

source dev-container-features-test-lib

check "valkey-server-8" bash -lc "valkey-server --version | grep 'v=8'"
check "valkey-cli-8" bash -lc "valkey-cli --version | grep '^valkey-cli 8'"

reportResults
