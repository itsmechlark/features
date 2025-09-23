#!/bin/bash

set -e

source dev-container-features-test-lib

check "codeql version" codeql --version

reportResults
