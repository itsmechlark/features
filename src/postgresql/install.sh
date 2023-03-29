#!/usr/bin/env bash

PG_VERSION=${VERSION:-"latest"}
PG_ARCHIVE_ARCHITECTURES="amd64 arm64 i386 ppc64el"
PG_ARCHIVE_VERSION_CODENAMES="bookworm bullseye buster bionic focal jammy kinetic"

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

    # Import the repository signing key
    curl -sS https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor --output /usr/share/keyrings/pgdg-archive-keyring.gpg
     # Create the file repository configuration
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/pgdg-archive-keyring.gpg]  http://apt.postgresql.org/pub/repos/apt ${VERSION_CODENAME}-pgdg main" > /etc/apt/sources.list.d/pgdg.list

    # Update lists
    apt-get update -yq

    # Soft version matching for CLI
    if [ "${PG_VERSION}" = "latest" ] || [ "${PG_VERSION}" = "lts" ] || [ "${PG_VERSION}" = "stable" ]; then
        # Empty, meaning grab whatever "latest" is in apt repo
        version_major=""
        version_suffix=""
    else
        version_major="-$(echo "${PG_VERSION}" | grep -oE -m 1 "^([0-9]+)")"
        version_suffix="=$(apt-cache show postgresql${version_major} | awk -F"Version: " '{print $2}' | sed -z "s/\n//g" | grep -E -m 1 "^(${PG_VERSION})(\.|$|\+.*|-.*)")"

        if [ -z ${version_suffix} ] || [ ${version_suffix} = "=" ]; then
            echo "Provided PG_VERSION (${PG_VERSION}) was not found in the apt-cache for this package+distribution combo";
            return 1
        fi
        echo "version_major ${version_major}"
        echo "version_suffix ${version_suffix}"
    fi

    apt-get install -yq postgresql${version_major}${version_suffix} postgresql-client${version_major} || return 1
}

export DEBIAN_FRONTEND=noninteractive

# Source /etc/os-release to get OS info
. /etc/os-release
architecture="$(dpkg --print-architecture)"

if [[ "${PG_ARCHIVE_ARCHITECTURES}" = *"${architecture}"* ]] && [[  "${PG_ARCHIVE_VERSION_CODENAMES}" = *"${VERSION_CODENAME}"* ]]; then
    install_using_apt || use_zip="true"
else
    use_zip="true"
fi

# Clean up
rm -rf /var/lib/apt/lists/*

echo "Done!"
