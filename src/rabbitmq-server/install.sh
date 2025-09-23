#!/usr/bin/env bash

RABBITMQ_VERSION=${VERSION:-"latest"}
RABBITMQ_ARCHIVE_ARCHITECTURES="amd64 arm64 i386 ppc64el"
RABBITMQ_ARCHIVE_VERSION_CODENAMES="bookworm bullseye sid focal jammy lunar bionic noble trixie"
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

setup_rabbitmq() {
    tee /usr/local/share/rabbitmq-server-init.sh << 'EOF'
#!/bin/sh
set -e

chown -fR rabbitmq:rabbitmq /var/lib/rabbitmq \
    && chmod 1777 /var/lib/rabbitmq \
    && sudo /etc/init.d/rabbitmq-server start

set +e

# Execute whatever commands were passed in (if any). This allows us
# to set this script to ENTRYPOINT while still executing the default CMD.
exec "$@"
EOF
    chmod +x /usr/local/share/rabbitmq-server-init.sh \
        && chown ${USERNAME}:root /usr/local/share/rabbitmq-server-init.sh
}

install_using_apt() {
    # Install dependencies
    check_packages apt-transport-https curl ca-certificates gnupg2 sudo

    # Import the repository signing key
    ## Primary RabbitMQ signing key
    curl -1sLf "https://github.com/rabbitmq/signing-keys/releases/download/2.0/rabbitmq-release-signing-key.asc" | gpg --dearmor | tee /usr/share/keyrings/com.github.rabbitmq.signing.gpg > /dev/null
    # Launchpad PPA signing key for apt
    curl -1sLf "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xf77f1eda57ebb1cc" | gpg --dearmor | tee /usr/share/keyrings/net.launchpad.ppa.rabbitmq.erlang.gpg > /dev/null

    # Determine the OS and distribution
    RABBITMQ_OS=${ID}
    RABBITMQ_DISTRIBUTION=${VERSION_CODENAME}
    if [ "${VERSION_CODENAME}" = "lunar" ] || [ "${VERSION_CODENAME}" = "jammy" ]; then
        RABBITMQ_DISTRIBUTION=jammy
    elif [ "${VERSION_CODENAME}" = "focal" ]; then
        RABBITMQ_DISTRIBUTION=focal
    elif [ "${VERSION_CODENAME}" = "bionic" ]; then
        RABBITMQ_DISTRIBUTION=bionic
    elif [ "${RABBITMQ_OS}" = "debian" ] || [ "${ID_LIKE}" = "debian" ]; then
        RABBITMQ_DISTRIBUTION=bullseye
    fi

    # Create the file repository configuration
    ## Add apt repositories maintained by Team RabbitMQ
    if [ "${RABBITMQ_OS}" = "ubuntu" ]; then
        sudo tee /etc/apt/sources.list.d/rabbitmq.list <<EOF
deb [signed-by=/usr/share/keyrings/net.launchpad.ppa.rabbitmq.erlang.gpg] http://ppa.launchpad.net/rabbitmq/rabbitmq-erlang/ubuntu ${RABBITMQ_DISTRIBUTION} main
deb-src [signed-by=/usr/share/keyrings/net.launchpad.ppa.rabbitmq.erlang.gpg] http://ppa.launchpad.net/rabbitmq/rabbitmq-erlang/ubuntu ${RABBITMQ_DISTRIBUTION} main
EOF
    else
        sudo tee /etc/apt/sources.list.d/rabbitmq.list <<EOF
## Provides modern Erlang/OTP releases
##
deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/rabbitmq.E495BB49CC4BBE5B.gpg] https://ppa1.novemberain.com/rabbitmq/rabbitmq-erlang/deb/${RABBITMQ_OS} ${RABBITMQ_DISTRIBUTION} main
deb-src [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/rabbitmq.E495BB49CC4BBE5B.gpg] https://ppa1.novemberain.com/rabbitmq/rabbitmq-erlang/deb/${RABBITMQ_OS} ${RABBITMQ_DISTRIBUTION} main

# another mirror for redundancy
deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/rabbitmq.E495BB49CC4BBE5B.gpg] https://ppa2.novemberain.com/rabbitmq/rabbitmq-erlang/deb/${RABBITMQ_OS} ${RABBITMQ_DISTRIBUTION} main
deb-src [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/rabbitmq.E495BB49CC4BBE5B.gpg] https://ppa2.novemberain.com/rabbitmq/rabbitmq-erlang/deb/${RABBITMQ_OS} ${RABBITMQ_DISTRIBUTION} main

## Provides RabbitMQ
##
deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/rabbitmq.9F4587F226208342.gpg] https://ppa1.novemberain.com/rabbitmq/rabbitmq-server/deb/${RABBITMQ_OS} ${RABBITMQ_DISTRIBUTION} main
deb-src [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/rabbitmq.9F4587F226208342.gpg] https://ppa1.novemberain.com/rabbitmq/rabbitmq-server/deb/${RABBITMQ_OS} ${RABBITMQ_DISTRIBUTION} main

# another mirror for redundancy
deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/rabbitmq.9F4587F226208342.gpg] https://ppa2.novemberain.com/rabbitmq/rabbitmq-server/deb/${RABBITMQ_OS} ${RABBITMQ_DISTRIBUTION} main
deb-src [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/rabbitmq.9F4587F226208342.gpg] https://ppa2.novemberain.com/rabbitmq/rabbitmq-server/deb/${RABBITMQ_OS} ${RABBITMQ_DISTRIBUTION} main
EOF
    fi

    # Update lists
    apt-get update -yq

    # Soft version matching for CLI
    if [ "${RABBITMQ_VERSION}" = "latest" ] || [ "${RABBITMQ_VERSION}" = "lts" ] || [ "${RABBITMQ_VERSION}" = "stable" ]; then
        # Empty, meaning grab whatever "latest" is in apt repo
        version_major=""
        version_suffix=""
    else
        version_major="$(echo "${RABBITMQ_VERSION}" | grep -oE -m 1 "^([0-9]+)")"
        version_suffix="=$(apt-cache show rabbitmq-server | awk -F"Version: " '{print $2}' | grep -E -m 1 "^(${RABBITMQ_VERSION})(\.|$|\+.*|-.*)")"

        if [ -z ${version_suffix} ] || [ ${version_suffix} = "=" ]; then
            echo "Provided RABBITMQ_VERSION (${RABBITMQ_VERSION}) was not found in the apt-cache for this package+distribution combo";
            return 1
        fi
        echo "version_major ${version_major}"
        echo "version_suffix ${version_suffix}"
    fi

    (apt-get install -yq --fix-missing rabbitmq-server${version_suffix} \
        && setup_rabbitmq) || return 1
}

export DEBIAN_FRONTEND=noninteractive

# Source /etc/os-release to get OS info
. /etc/os-release
architecture="$(dpkg --print-architecture)"

if [[ "${RABBITMQ_ARCHIVE_ARCHITECTURES}" = *"${architecture}"* ]] && [[  "${RABBITMQ_ARCHIVE_VERSION_CODENAMES}" = *"${VERSION_CODENAME}"* ]]; then
    install_using_apt || use_zip="true"
else
    use_zip="true"
fi

# Clean up
rm -rf /var/lib/apt/lists/*

echo "Done!"
