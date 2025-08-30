#!/usr/bin/env bash

CLI_VERSION=${VERSION:-"latest"}
CLI_ARCHIVE_ARCHITECTURES="amd64 arm64 i386"
CLI_ARCHIVE_VERSION_CODENAMES="bookworm bullseye buster bionic focal mantic jammy kinetic noble trixie"

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

install_using_apt() {
    # Install dependencies
    check_packages apt-transport-https curl ca-certificates gnupg2 dirmngr

    # Add the key for the 1Password Apt repository
    curl -sS https://downloads.1password.com/linux/keys/1password.asc | gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg
    # Add the 1Password Apt repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | tee /etc/apt/sources.list.d/1password.list
    # Add the debsig-verify policy
    mkdir -p /etc/debsig/policies/AC2D62742012EA22/ \
        && curl -sS https://downloads.1password.com/linux/debian/debsig/1password.pol | tee /etc/debsig/policies/AC2D62742012EA22/1password.pol \
        && mkdir -p /usr/share/debsig/keyrings/AC2D62742012EA22 \
        && curl -sS https://downloads.1password.com/linux/keys/1password.asc | gpg --dearmor --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg

    # Update lists
    apt-get update -yq

    # Soft version matching for CLI
    if [ "${CLI_VERSION}" = "latest" ] || [ "${CLI_VERSION}" = "lts" ] || [ "${CLI_VERSION}" = "stable" ]; then
        # Empty, meaning grab whatever "latest" is in apt repo
        version_suffix=""
    else
        version_suffix="=$(apt-cache madison 1password-cli | awk -F"|" '{print $2}' | sed -e 's/^[ \t]*//' | grep -E -m 1 "^(${CLI_VERSION})(\.|$|\+.*|-.*)")"

        if [ -z ${version_suffix} ] || [ ${version_suffix} = "=" ]; then
            echo "Provided CLI_VERSION (${CLI_VERSION}) was not found in the apt-cache for this package+distribution combo";
            return 1
        fi
        echo "version_suffix ${version_suffix}"
    fi

    apt-get install -yq 1password-cli${version_suffix} || return 1
}

export DEBIAN_FRONTEND=noninteractive

# Source /etc/os-release to get OS info
. /etc/os-release
architecture="$(dpkg --print-architecture)"

if [[ "${CLI_ARCHIVE_ARCHITECTURES}" = *"${architecture}"* ]] && [[  "${CLI_ARCHIVE_VERSION_CODENAMES}" = *"${VERSION_CODENAME}"* ]]; then
    install_using_apt || use_zip="true"
else
    use_zip="true"
fi

# Clean up
rm -rf /var/lib/apt/lists/*

echo "Done!"
