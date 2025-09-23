#!/usr/bin/env bash

VALKEY_VERSION=${VERSION:-"latest"}
USERNAME="${USERNAME:-"${_REMOTE_USER:-"automatic"}"}"

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

apt_get_update() {
    if [ "$(find /var/lib/apt/lists/* 2>/dev/null | wc -l)" = "0" ]; then
        echo "Running apt-get update..."
        apt-get update -y
    fi
}

check_packages() {
    if ! dpkg -s "$@" > /dev/null 2>&1; then
        apt_get_update
        apt-get -y install --no-install-recommends "$@"
    fi
}

find_version_from_git_tags() {
    local variable_name=$1
    local requested_version=${!variable_name}
    if [ "${requested_version}" = "none" ]; then
        return
    fi
    local repository=$2
    if [ -z "${repository}" ]; then
        err "Repository parameter missing for find_version_from_git_tags"
        exit 1
    fi
    local version_list
    version_list=$(git ls-remote --tags "${repository}" \
        | awk -F'/' '/refs\/tags\/[0-9]/{print $NF}' \
        | sed 's/\^{}//' \
        | sort -rV \
        | awk '!seen[$0]++')
    if [ -z "${version_list}" ]; then
        err "Unable to fetch version list from ${repository}"
        exit 1
    fi
    local stable_versions
    stable_versions=$(echo "${version_list}" | grep -Ev '[-](alpha|beta|rc)[0-9]*$' || true)
    if [ "${requested_version}" = "latest" ] || [ "${requested_version}" = "stable" ] || [ "${requested_version}" = "lts" ]; then
        if [ -n "${stable_versions}" ]; then
            declare -g ${variable_name}="$(echo "${stable_versions}" | head -n 1)"
        else
            declare -g ${variable_name}="$(echo "${version_list}" | head -n 1)"
        fi
        return
    fi
    local version_regex
    if echo "${requested_version}" | grep -E "^[0-9]+$" > /dev/null 2>&1; then
        version_regex="^${requested_version}\\."
    else
        version_regex="^${requested_version//./\\.}([\\.-]|$)"
    fi
    set +e
    declare -g ${variable_name}="$(echo "${version_list}" | grep -E -m 1 "${version_regex}")"
    set -e
    if [ -z "${!variable_name}" ]; then
        err "Invalid ${variable_name} value: ${requested_version}"
        err "Valid values include:"
        echo "${version_list}" >&2
        exit 1
    fi
}

export DEBIAN_FRONTEND=noninteractive

check_packages build-essential ca-certificates curl git libssl-dev pkg-config tar tcl

find_version_from_git_tags VALKEY_VERSION https://github.com/valkey-io/valkey
VALKEY_VERSION="${VALKEY_VERSION#v}"
echo "(*) Installing Valkey ${VALKEY_VERSION} from source..."
TMP_DIR=$(mktemp -d -t valkey-XXXXXX)

curl -fsSL "https://github.com/valkey-io/valkey/archive/refs/tags/${VALKEY_VERSION}.tar.gz" -o "${TMP_DIR}/valkey.tar.gz"
tar -xzf "${TMP_DIR}/valkey.tar.gz" -C "${TMP_DIR}"
SOURCE_DIR="${TMP_DIR}/valkey-${VALKEY_VERSION}"

make -C "${SOURCE_DIR}" -j"$(nproc)" BUILD_TLS=yes
make -C "${SOURCE_DIR}" BUILD_TLS=yes install PREFIX=/usr/local

if ! id -u valkey > /dev/null 2>&1; then
    if ! getent group valkey > /dev/null 2>&1; then
        groupadd --system valkey
    fi
    useradd --system --gid valkey --create-home --home-dir /var/lib/valkey --shell /usr/sbin/nologin valkey
fi

mkdir -p /etc/valkey
cp "${SOURCE_DIR}/valkey.conf" /etc/valkey/valkey.conf
cp "${SOURCE_DIR}/sentinel.conf" /etc/valkey/sentinel.conf
sed -i 's|^dir .*|dir /var/lib/valkey/data|' /etc/valkey/valkey.conf

mkdir -p /var/lib/valkey/data
chown -R valkey:valkey /var/lib/valkey
chmod 0750 /var/lib/valkey
chmod 0750 /var/lib/valkey/data

cat <<'EOS' > /usr/local/share/valkey-init.sh
#!/bin/sh
set -e

DATA_DIR="/var/lib/valkey/data"
CONFIG_FILE="/etc/valkey/valkey.conf"

if [ -d "${DATA_DIR}" ]; then
    chown -R valkey:valkey "${DATA_DIR}"
    chmod 0750 "${DATA_DIR}"
fi

if command -v su >/dev/null 2>&1 && id valkey >/dev/null 2>&1; then
    su -s /bin/sh valkey -c "valkey-server \"${CONFIG_FILE}\" --daemonize yes"
else
    valkey-server "${CONFIG_FILE}" --daemonize yes
fi

set +e
exec "$@"
EOS
chmod +x /usr/local/share/valkey-init.sh
chown ${USERNAME}:root /usr/local/share/valkey-init.sh

rm -rf /var/lib/apt/lists/* "${TMP_DIR}"

echo "Done!"
