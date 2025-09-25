#!/usr/bin/env bash

SQLITE_VERSION=${VERSION:-"latest"}

set -e

if [ -d /var/lib/apt/lists ]; then
    rm -rf /var/lib/apt/lists/*
fi

err() {
    echo "(!) $*" >&2
}

if [ "$(id -u)" -ne 0 ]; then
    err 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
    exit 1
fi

apt_get_update() {
    if [ "$(find /var/lib/apt/lists/* 2>/dev/null | wc -l)" = "0" ]; then
        echo "Running apt-get update..."
        apt-get update -y
    fi
}

resolve_sqlite_version() {
    local requested_version=$1

    local version_list
    version_list=$(apt-cache madison sqlite3 | awk '{print $3}' | sort -rV | awk '!seen[$0]++')

    if [ -z "${version_list}" ]; then
        err "Unable to find sqlite3 versions in the apt cache"
        exit 1
    fi

    if [ "${requested_version}" = "latest" ] || [ "${requested_version}" = "stable" ] || [ "${requested_version}" = "lts" ] || [ "${requested_version}" = "nightly" ]; then
        echo "$(echo "${version_list}" | head -n 1)"
        return 0
    fi

    local version_regex
    if echo "${requested_version}" | grep -E "^[0-9]+$" > /dev/null 2>&1; then
        version_regex="^${requested_version}\\."
    else
        version_regex="^${requested_version//./\\.}"
    fi

    local matched_version
    matched_version=$(echo "${version_list}" | grep -E -m 1 "${version_regex}")

    if [ -z "${matched_version}" ]; then
        err "Invalid VERSION value: ${requested_version}"
        err "Available versions:"
        echo "${version_list}" >&2
        exit 1
    fi

    echo "${matched_version}"
}

export DEBIAN_FRONTEND=noninteractive

apt_get_update

resolved_version=$(resolve_sqlite_version "${SQLITE_VERSION}")

packages=("sqlite3=${resolved_version}" "libsqlite3-dev=${resolved_version}")

apt-get install -y --no-install-recommends "${packages[@]}"

rm -rf /var/lib/apt/lists/*

echo "Done!"
