#!/bin/bash

set -e

source dev-container-features-test-lib

check "cloudflared stable version" bash -lc "cloudflared --version | head -n 1 | grep -E 'cloudflared version [0-9]'"

reportResults
