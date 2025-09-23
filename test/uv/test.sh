#!/bin/bash

set -e

source dev-container-features-test-lib

check "uv version" uv --version
check "uvx version" uvx --version

reportResults
