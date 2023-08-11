#!/usr/bin/env bash

CLI_VERSION=${VERSION:-"latest"}
CLI_ARCHIVE_ARCHITECTURES="amd64 arm64 i386 ppc64el"
CLI_ARCHIVE_VERSION_CODENAMES="bookworm bullseye buster bionic focal jammy kinetic"

setup_doppler() {
    tee /usr/local/share/doppler-init.sh << 'EOF'
#!/bin/sh
set -e

chown -R ${USER}:${USER} /var/lib/doppler \
    && chmod 700 /var/lib/doppler

set +e

# Execute whatever commands were passed in (if any). This allows us
# to set this script to ENTRYPOINT while still executing the default CMD.
exec "$@"
EOF
    chmod +x /usr/local/share/doppler-init.sh \
        && chown ${USERNAME}:root /usr/local/share/doppler-init.sh
}

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
    check_packages apt-transport-https ca-certificates curl gnupg

    # Import the repository signing key
    curl -sS https://packages.doppler.com/public/cli/gpg.DE2A7741A397C129.key | gpg --dearmor --output /usr/share/keyrings/doppler-archive-keyring.gpg
     # Create the file repository configuration
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/doppler-archive-keyring.gpg] https://packages.doppler.com/public/cli/deb/debian any-version main" > /etc/apt/sources.list.d/doppler.list

    # Update lists
    apt-get update -yq

    # Soft version matching for CLI
    if [ "${CLI_VERSION}" = "latest" ] || [ "${CLI_VERSION}" = "lts" ] || [ "${CLI_VERSION}" = "stable" ]; then
        # Empty, meaning grab whatever "latest" is in apt repo
        version_major=""
        version_suffix=""
    else
        version_major="-$(echo "${CLI_VERSION}" | grep -oE -m 1 "^([0-9]+)")"
        version_suffix="=$(apt-cache show doppler | awk -F"Version: " '{print $2}' | grep -E -m 1 "^(${CLI_VERSION})(\.|$|\+.*|-.*)")"

        if [ -z ${version_suffix} ] || [ ${version_suffix} = "=" ]; then
            echo "Provided CLI_VERSION (${CLI_VERSION}) was not found in the apt-cache for this package+distribution combo";
            return 1
        fi
        echo "version_major ${version_major}"
        echo "version_suffix ${version_suffix}"
    fi

    (apt-get install -yq doppler${version_suffix} && setup_doppler) || return 1
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
