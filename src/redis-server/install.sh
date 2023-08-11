#!/usr/bin/env bash

REDIS_SERVER_VERSION=${VERSION:-"latest"}
REDIS_SERVER_ARCHIVE_ARCHITECTURES="amd64 arm64 i386 ppc64el"
REDIS_SERVER_ARCHIVE_VERSION_CODENAMES="bookworm bullseye buster sid bionic focal jammy kinetic"
USERNAME="${USERNAME:-"${_REMOTE_USER:-"automatic"}"}"

# Default: Exit on any failure.
set -e

# Clean up
rm -rf /var/lib/apt/lists/*

# Setup STDERR.
err() {
    echo "(!) $*" >&2
}

if [ "$(id -u)" -ne 0 ]; then
    err 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
    exit 1
fi

# Determine the appropriate non-root user
if [ "${USERNAME}" = "auto" ] || [ "${USERNAME}" = "automatic" ]; then
    USERNAME=""
    POSSIBLE_USERS=("vscode" "node" "codespace" "$(awk -v val=1000 -F ":" '$3==val{print $1}' /etc/passwd)")
    for CURRENT_USER in "${POSSIBLE_USERS[@]}"; do
        if id -u ${CURRENT_USER} > /dev/null 2>&1; then
            USERNAME=${CURRENT_USER}
            break
        fi
    done
    if [ "${USERNAME}" = "" ]; then
        USERNAME=root
    fi
elif [ "${USERNAME}" = "none" ] || ! id -u ${USERNAME} > /dev/null 2>&1; then
    USERNAME=root
fi

apt_get_update()
{
    if [ "$(find /var/lib/apt/lists/* | wc -l)" = "0" ]; then
        echo "Running apt-get update..."
        apt-get update -y
    fi
}

# Checks if packages are installed and installs them if not
check_packages() {
    if ! dpkg -s "$@" > /dev/null 2>&1; then
        apt_get_update
        apt-get -y install --no-install-recommends "$@"
    fi
}

setup_redis() {
    tee /usr/local/share/redis-server-init.sh << 'EOF'
#!/bin/sh
set -e

chown -R redis:redis /var/lib/redis-server/data \
    && chmod 777 /var/lib/redis-server/data \
    && echo "dir /var/lib/redis-server/data" >> /etc/redis/redis.conf \
    && sudo /etc/init.d/redis-server start

set +e

# Execute whatever commands were passed in (if any). This allows us
# to set this script to ENTRYPOINT while still executing the default CMD.
exec "$@"
EOF
    chmod +x /usr/local/share/redis-server-init.sh \
        && chown ${USERNAME}:root /usr/local/share/redis-server-init.sh
}

install_using_apt() {
    # Install dependencies
    check_packages apt-transport-https curl ca-certificates gnupg2 sudo

    # Import the repository signing key
    curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    # Create the file repository configuration
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb ${VERSION_CODENAME} main" | sudo tee /etc/apt/sources.list.d/redis.list

    # Update lists
    apt-get update -yq

    # Soft version matching for CLI
    if [ "${REDIS_SERVER_VERSION}" = "latest" ] || [ "${REDIS_SERVER_VERSION}" = "lts" ] || [ "${REDIS_SERVER_VERSION}" = "stable" ]; then
        # Empty, meaning grab whatever "latest" is in apt repo
        version_major=""
        version_suffix=""
    else
        version_major="$(echo "${REDIS_SERVER_VERSION}" | grep -oE -m 1 "^([0-9]+)")"
        version_suffix="=$(apt-cache show redis-server | awk -F"Version: " '{print $2}' | grep -E -m 1 "^([0-9]:)(${REDIS_SERVER_VERSION})(\.|$|\+.*|-.*)")"

        if [ -z ${version_suffix} ] || [ ${version_suffix} = "=" ]; then
            echo "Provided REDIS_SERVER_VERSION (${REDIS_SERVER_VERSION}) was not found in the apt-cache for this package+distribution combo";
            return 1
        fi
        echo "version_major ${version_major}"
        echo "version_suffix ${version_suffix}"
    fi

    (apt-get install -yq redis-server${version_suffix} \
        && setup_redis) || return 1
}

export DEBIAN_FRONTEND=noninteractive

# Source /etc/os-release to get OS info
. /etc/os-release
architecture="$(dpkg --print-architecture)"

if [[ "${REDIS_SERVER_ARCHIVE_ARCHITECTURES}" = *"${architecture}"* ]] && [[  "${REDIS_SERVER_ARCHIVE_VERSION_CODENAMES}" = *"${VERSION_CODENAME}"* ]]; then
    install_using_apt || use_zip="true"
else
    use_zip="true"
fi

# Clean up
rm -rf /var/lib/apt/lists/*

echo "Done!"
