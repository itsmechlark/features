#!/bin/bash

set -e

source dev-container-features-test-lib

check "sqlite3 version" bash -lc "sqlite3 --version | grep '^3.37'"

reportResults
