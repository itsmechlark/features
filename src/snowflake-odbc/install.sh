#!/usr/bin/env bash

SNOWFLAKE_VERSION=${VERSION:-"3.1.0"}
SNOWFLAKE_ARCHIVE_ARCHITECTURES="amd64 arm64 i386 ppc64el"
SNOWFLAKE_ARCHIVE_VERSION_CODENAMES="bookworm bullseye sid focal jammy lunar bionic noble trixie"
SNOWFLAKE_GPG_KEY_ID="630D9F3CAB551AF3"
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

setup_debsig_policy() {
    tee /etc/debsig/policies/${SNOWFLAKE_GPG_KEY_ID} <<EOF
<?xml version="1.0"?>
<!DOCTYPE Policy SYSTEM "http://www.debian.org/debsig/1.0/policy.dtd">
<Policy xmlns="https://www.debian.org/debsig/1.0/">
<Origin Name="Snowflake Computing" id="${SNOWFLAKE_GPG_KEY_ID}"
Description="Snowflake ODBC Driver DEB package"/>

<Selection>
<Required Type="origin" File="debsig.gpg" id="${SNOWFLAKE_GPG_KEY_ID}"/>
</Selection>

<Verification MinOptional="0">
<Required Type="origin" File="debsig.gpg" id="${SNOWFLAKE_GPG_KEY_ID}"/>
</Verification>

</Policy>
EOF
}

install_using_apt() {
    # Install dependencies
    check_packages apt-transport-https curl ca-certificates gnupg2 sudo unixodbc unixodbc-dev odbcinst

    # Import the repository signing key
    gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys ${SNOWFLAKE_GPG_KEY_ID}  && \
        check_packages debsig-verify && \
        mkdir /usr/share/debsig/keyrings/${SNOWFLAKE_GPG_KEY_ID} && \
        gpg --export ${SNOWFLAKE_GPG_KEY_ID} > snowflakeKey.asc && \
        touch /usr/share/debsig/keyrings/${SNOWFLAKE_GPG_KEY_ID}/debsig.gpg && \
        gpg --no-default-keyring --keyring /usr/share/debsig/keyrings/${SNOWFLAKE_GPG_KEY_ID}/debsig.gpg --import snowflakeKey.asc && \
        setup_debsig_policy

    # Determine the architecture
    SNOWFLAKE_ARCHITECTURE=x86_64
    SNOWFLAKE_DISTRIBUTION=linux
    architecture="$(dpkg --print-architecture)"
    if [ "${architecture}" = "arm64" ]; then
        SNOWFLAKE_ARCHITECTURE=aarch64
        SNOWFLAKE_DISTRIBUTION=linuxaarch64
    fi

    # Update lists
    apt-get update -yq

    # Install the package
    (export TMP_DIR="/tmp/tmp-snowflake" && \
        mkdir -p ${TMP_DIR} && \
        curl -sSL \
            -o ${TMP_DIR}/odbc.deb \
            "https://sfc-repo.snowflakecomputing.com/odbc/${SNOWFLAKE_DISTRIBUTION}/${SNOWFLAKE_VERSION}/snowflake-odbc-${SNOWFLAKE_VERSION}.${SNOWFLAKE_ARCHITECTURE}.deb" && \
        sudo dpkg -i ${TMP_DIR}/odbc.deb && \
        sudo apt-get install -f) || return 1
}

export DEBIAN_FRONTEND=noninteractive

# Source /etc/os-release to get OS info
. /etc/os-release
architecture="$(dpkg --print-architecture)"

if [[ "${SNOWFLAKE_ARCHIVE_ARCHITECTURES}" = *"${architecture}"* ]] && [[  "${SNOWFLAKE_ARCHIVE_VERSION_CODENAMES}" = *"${VERSION_CODENAME}"* ]]; then
    install_using_apt || use_zip="true"
else
    use_zip="true"
fi

# Clean up
rm -rf /var/lib/apt/lists/*

echo "Done!"
