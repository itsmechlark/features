#!/bin/bash

set -e

source dev-container-features-test-lib

check "sqlite3 available" sqlite3 --version

reportResults
