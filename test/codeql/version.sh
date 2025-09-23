#!/bin/bash

set -e

source dev-container-features-test-lib

check "codeql 2.23" codeql --version | grep 2.23

reportResults
