#!/usr/bin/env bash

set -e

# Clean up
rm -rf /var/lib/apt/lists/*

PULUMI_VERSION=${VERSION:-"latest"}
USERNAME="${USERNAME:-"${_REMOTE_USER:-"automatic"}"}"

if [ "$(id -u)" -ne 0 ]; then
    echo -e 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
    exit 1
fi

# Determine the appropriate non-root user
if [ "${USERNAME}" = "auto" ] || [ "${USERNAME}" = "automatic" ]; then
    USERNAME=""
    POSSIBLE_USERS=("vscode" "node" "codespace" "$(awk -v val=1000 -F ":" '$3==val{print $1}' /etc/passwd)")
    for CURRENT_USER in "${POSSIBLE_USERS[@]}"; do
        if id -u "${CURRENT_USER}" > /dev/null 2>&1; then
            USERNAME="${CURRENT_USER}"
            break
        fi
    done
    if [ "${USERNAME}" = "" ]; then
        USERNAME=root
    fi
elif [ "${USERNAME}" = "none" ] || ! id -u "${USERNAME}" > /dev/null 2>&1; then
    USERNAME=root
fi

apt_get_update()
{
    echo "Running apt-get update..."
    apt-get update -y
}

# Checks if packages are installed and installs them if not
check_packages() {
    if ! dpkg -s "$@" > /dev/null 2>&1; then
        if [ "$(find /var/lib/apt/lists/* | wc -l)" = "0" ]; then
            apt_get_update
        fi
        apt-get -y install --no-install-recommends "$@"
    fi
}

export DEBIAN_FRONTEND=noninteractive

# Figure out correct version of a three part version number is not passed
find_version_from_git_tags() {
    local variable_name=$1
    local requested_version=${!variable_name}
    if [ "${requested_version}" = "none" ]; then return; fi
    local repository=$2
    local prefix=${3:-"tags/v"}
    local separator=${4:-"."}
    local last_part_optional=${5:-"false"}
    if [ "$(echo "${requested_version}" | grep -o "." | wc -l)" != "2" ]; then
        local escaped_separator=${separator//./\\.}
        local last_part
        if [ "${last_part_optional}" = "true" ]; then
            last_part="(${escaped_separator}[0-9]+)?"
        else
            last_part="${escaped_separator}[0-9]+"
        fi
        local regex="${prefix}\\K[0-9]+${escaped_separator}[0-9]+${last_part}$"
        local version_list="$(git ls-remote --tags ${repository} | grep -oP "${regex}" | tr -d ' ' | tr "${separator}" "." | sort -rV)"
        if [ "${requested_version}" = "latest" ] || [ "${requested_version}" = "current" ] || [ "${requested_version}" = "lts" ]; then
            declare -g ${variable_name}="$(echo "${version_list}" | head -n 1)"
        else
            set +e
            declare -g ${variable_name}="$(echo "${version_list}" | grep -E -m 1 "^${requested_version//./\\.}([\\.\\s]|$)")"
            set -e
        fi
    fi
    if [ -z "${!variable_name}" ] || ! echo "${version_list}" | grep "^${!variable_name//./\\.}$" > /dev/null 2>&1; then
        echo -e "Invalid ${variable_name} value: ${requested_version}\nValid values:\n${version_list}" >&2
        exit 1
    fi
    echo "${variable_name}=${!variable_name}"
}

setup_pulumi() {
    tee /usr/local/share/pulumi-init.sh << 'EOF'
#!/bin/sh
set -e

# Resolve USERNAME chosen during install from this script's owner, fallback to common users/root
OWNER="$(stat -c '%U' /usr/local/share/pulumi-init.sh 2>/dev/null || true)"
if [ -n "$OWNER" ] && [ "$OWNER" != "root" ]; then
    USERNAME="$OWNER"
elif [ -z "$USERNAME" ] || ! id -u "$USERNAME" >/dev/null 2>&1; then
    for u in vscode node codespace "$(awk -F: '$3==1000{print $1}' /etc/passwd)"; do
        if id -u "$u" >/dev/null 2>&1; then
            USERNAME="$u"
            break
        fi
    done
    [ -z "$USERNAME" ] && USERNAME="root"
fi

mkdir -p /var/lib/pulumi/data \
    && chown -R "$USERNAME":"$USERNAME" /var/lib/pulumi/data \
    && chmod 0750 /var/lib/pulumi/data

set +e

# Execute whatever commands were passed in (if any). This allows us
# to set this script to ENTRYPOINT while still executing the default CMD.
exec "$@"
EOF
    chmod +x /usr/local/share/pulumi-init.sh \
        && chown ${USERNAME}:root /usr/local/share/pulumi-init.sh
}

# Install dependencies
check_packages ca-certificates curl git tar

architecture="$(uname -m)"
case $architecture in
    x86_64) architecture="x64";;
    aarch64 | armv8* | arm64) architecture="arm64";;
    *) echo "(!) Architecture $architecture unsupported"; exit 1 ;;
esac

# Use a temporary location for pulumi archive
export TMP_DIR="/tmp/tmp-pulumi"
mkdir -p ${TMP_DIR}
chmod 700 ${TMP_DIR}

# Install pulumi
echo "(*) Installing pulumi..."
find_version_from_git_tags PULUMI_VERSION https://github.com/pulumi/pulumi

PULUMI_VERSION="${PULUMI_VERSION#"v"}"
curl -sSL -o ${TMP_DIR}/pulumi.tar.gz "https://github.com/pulumi/pulumi/releases/download/v${PULUMI_VERSION}/pulumi-v${PULUMI_VERSION}-linux-${architecture}.tar.gz" \
    && tar -xzf "${TMP_DIR}/pulumi.tar.gz" -C "${TMP_DIR}" pulumi \
    && cp ${TMP_DIR}/pulumi/* /usr/local/bin \
    && chmod 0755 /usr/local/bin/pulumi* \
    && setup_pulumi

# Clean up
rm -rf /var/lib/apt/lists/*

echo "Done!"
