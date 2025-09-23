#!/bin/bash

set -e

source dev-container-features-test-lib

check "valkey-init-exists" bash -c "ls /usr/local/share/valkey-init.sh"
check "valkey-server-version" valkey-server --version
check "valkey-config-dir" bash -c "grep '^dir /var/lib/valkey/data' /etc/valkey/valkey.conf"
check "valkey-user" id valkey

reportResults
