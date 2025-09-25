#!/bin/bash

set -e

source dev-container-features-test-lib

check "valkey-cli-rc" valkey-cli --version

reportResults
