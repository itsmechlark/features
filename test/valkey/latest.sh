#!/bin/bash

set -e

source dev-container-features-test-lib

check "valkey-server-stable" bash -lc "valkey-server --version | grep 'Valkey server v=' | grep -v 'rc'"

reportResults
