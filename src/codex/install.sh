#!/usr/bin/env bash

set -e

# Clean up
rm -rf /var/lib/apt/lists/*

CODEX_VERSION=${VERSION:-"latest"}
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
    local prefix=${3:-"tags/rust-v"}
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
        local raw_version_list
        raw_version_list="$(git ls-remote --tags ${repository} | grep -oP "${regex}" | tr -d ' ' | tr "${separator}" "." | sort -rV)"
        local version_list="${raw_version_list}"
        if [ -n "${version_list}" ] && { [ "${requested_version}" = "latest" ] || [ "${requested_version}" = "current" ] || [ "${requested_version}" = "lts" ]; }; then
            local stable_version_list
            stable_version_list="$(echo "${version_list}" | grep -E '^[0-9]+(\.[0-9]+){1,2}$' || true)"
            if [ -n "${stable_version_list}" ]; then
                version_list="${stable_version_list}"
            fi
        fi
        if [ -z "${version_list}" ]; then
            echo "Unable to determine a valid version from ${repository}" >&2
            exit 1
        fi
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

setup_codex() {
    tee /usr/local/share/codex-init.sh << 'EOF'
#!/bin/sh
set -e

# Resolve USERNAME chosen during install from this script's owner, fallback to common users/root
OWNER="$(stat -c '%U' /usr/local/share/codex-init.sh 2>/dev/null || true)"
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

mkdir -p /var/lib/codex/data \
    && chown -R "$USERNAME":"$USERNAME" /var/lib/codex/data \
    && chmod 0750 /var/lib/codex/data

set +e

# Execute whatever commands were passed in (if any). This allows us
# to set this script to ENTRYPOINT while still executing the default CMD.
exec "$@"
EOF
    chmod +x /usr/local/share/codex-init.sh \
        && chown ${USERNAME}:root /usr/local/share/codex-init.sh
}

# Install dependencies
check_packages ca-certificates curl git tar libc6

architecture="$(uname -m)"
case $architecture in
    x86_64) architecture="x86_64";;
    aarch64 | armv8* | arm64) architecture="aarch64";;
    *) echo "(!) Architecture $architecture unsupported"; exit 1 ;;
esac

# Use a temporary location for codex archive
export TMP_DIR="/tmp/tmp-codex"
mkdir -p ${TMP_DIR}
chmod 700 ${TMP_DIR}

# Install codex
echo "(*) Installing codex..."
find_version_from_git_tags CODEX_VERSION https://github.com/openai/codex

CODEX_VERSION="${CODEX_VERSION#"v"}"
echo "    Using version ${CODEX_VERSION}"

install_codex_binary() {
    local target archive_url archive_path
    for target in "$@"; do
        archive_url="https://github.com/openai/codex/releases/download/rust-v${CODEX_VERSION}/${target}.tar.gz"
        archive_path="${TMP_DIR}/${target}.tar.gz"
        echo "    Attempting download for ${target}"
        if curl -fsSL -o "${archive_path}" "${archive_url}"; then
            if tar -xzf "${archive_path}" -C "${TMP_DIR}" "${target}"; then
                cp "${TMP_DIR}/${target}" /usr/local/bin/codex
                chmod 0755 /usr/local/bin/codex
                echo "    Installed ${target}"
                return 0
            else
                echo "    Failed to extract ${target}; trying next option" >&2
            fi
        else
            echo "    Failed to download ${archive_url}; trying next option" >&2
        fi
    done
    return 1
}

codex_targets=()
# Prefer musl builds when available to stay compatible with older glibc releases.
case "${architecture}" in
    x86_64|aarch64)
        codex_targets+=("codex-${architecture}-unknown-linux-musl")
        ;;
esac
codex_targets+=("codex-${architecture}-unknown-linux-gnu")

if ! install_codex_binary "${codex_targets[@]}"; then
    echo "    Unable to install codex for architecture ${architecture}" >&2
    exit 1
fi

setup_codex

# Clean up
rm -rf /var/lib/apt/lists/* ${TMP_DIR}

echo "Done!"
