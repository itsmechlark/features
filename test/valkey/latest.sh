#!/bin/bash

set -e

source dev-container-features-test-lib

check "valkey-cli-latest" bash -lc "! valkey-cli --version | grep -E -- '-(rc|beta|alpha)'"

reportResults
