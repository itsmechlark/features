#!/usr/bin/env bash

set -e

rm -rf /var/lib/apt/lists/*

CODEQL_VERSION=${VERSION:-"latest"}

if [ "$(id -u)" -ne 0 ]; then
    echo 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
    exit 1
fi

apt_get_update() {
    echo "Running apt-get update..."
    apt-get update -y
}

check_packages() {
    if ! dpkg -s "$@" >/dev/null 2>&1; then
        if [ "$(find /var/lib/apt/lists/* | wc -l)" = "0" ]; then
            apt_get_update
        fi
        apt-get -y install --no-install-recommends "$@"
    fi
}

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
    if [ -z "${!variable_name}" ] || ! echo "${version_list}" | grep "^${!variable_name//./\\.}$" >/dev/null 2>&1; then
        echo -e "Invalid ${variable_name} value: ${requested_version}\nValid values:\n${version_list}" >&2
        exit 1
    fi
    echo "${variable_name}=${!variable_name}"
}

export DEBIAN_FRONTEND=noninteractive

check_packages curl ca-certificates unzip git

architecture="$(uname -m)"
case "${architecture}" in
    x86_64) archive_suffix="linux64" ;;
    *)
        echo "Architecture ${architecture} is not supported by the CodeQL CLI binaries." >&2
        exit 1
        ;;
esac

TMP_DIR="$(mktemp -d -t codeql-XXXXXX)"
chmod 700 "${TMP_DIR}"

find_version_from_git_tags CODEQL_VERSION https://github.com/github/codeql-cli-binaries
CODEQL_VERSION="${CODEQL_VERSION#"v"}"

CODEQL_ARCHIVE="codeql-${archive_suffix}.zip"
DOWNLOAD_URL="https://github.com/github/codeql-cli-binaries/releases/download/v${CODEQL_VERSION}/${CODEQL_ARCHIVE}"
CHECKSUM_URL="${DOWNLOAD_URL}.checksum.txt"

echo "(*) Downloading CodeQL CLI ${CODEQL_VERSION}..."
curl -sSL -o "${TMP_DIR}/${CODEQL_ARCHIVE}" "${DOWNLOAD_URL}"
curl -sSL -o "${TMP_DIR}/${CODEQL_ARCHIVE}.checksum.txt" "${CHECKSUM_URL}"

pushd "${TMP_DIR}" >/dev/null
sha256sum -c "${CODEQL_ARCHIVE}.checksum.txt"
popd >/dev/null

echo "(*) Installing CodeQL CLI..."
unzip -q "${TMP_DIR}/${CODEQL_ARCHIVE}" -d "${TMP_DIR}"
CODEQL_INSTALL_DIR="/usr/local/codeql"
rm -rf "${CODEQL_INSTALL_DIR}"
mv "${TMP_DIR}/codeql" "${CODEQL_INSTALL_DIR}"
chmod -R 0755 "${CODEQL_INSTALL_DIR}"
ln -sfn "${CODEQL_INSTALL_DIR}/codeql" /usr/local/bin/codeql

rm -rf "${TMP_DIR}"
rm -rf /var/lib/apt/lists/*

echo "Done!"
