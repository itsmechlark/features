#!/bin/bash

set -e

# Optional: Import test library
source dev-container-features-test-lib

# Feature specific tests
check "policies-exists" sudo cat /etc/debsig/policies/630D9F3CAB551AF3 | grep Snowflake
check "snowflake-ini-exists" bash -c "ls /usr/lib/snowflake/odbc/lib/simba.snowflake.ini"
check "odbcinst-ini-exists" sudo cat /etc/odbcinst.ini | grep Snowflake

# Report result
reportResults
