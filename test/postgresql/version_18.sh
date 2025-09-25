#!/bin/bash

set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "etc" ls /etc/postgresql | grep 18
check "client" psql --version | grep 18
check "data" sudo cat /var/lib/postgresql/data/PG_VERSION | grep 18
check "pq-init-exists" bash -c "ls /usr/local/share/pq-init.sh"
check "init" sudo --preserve-env=PGDATA,PGHOST,PGUSER /usr/local/share/pq-init.sh /bin/true
check "start" sudo /etc/init.d/postgresql start
check "ready" bash -c "pg_isready -t 60"
check "connect" bash -c "psql -U postgres -tAc 'SELECT 1;' | grep 1"

# Report result
reportResults
