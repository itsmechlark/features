#!/usr/bin/env bash

set -e

# Clean up
rm -rf /var/lib/apt/lists/*

CLOUDFLARED_VERSION=${VERSION:-"latest"}

if [ "$(id -u)" -ne 0 ]; then
    echo -e 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
    exit 1
fi

if [ "${CLOUDFLARED_VERSION}" = "none" ]; then
    echo "Version set to 'none'; skipping cloudflared installation."
    exit 0
fi

apt_get_update() {
    echo "Running apt-get update..."
    apt-get update -y
}

check_packages() {
    if ! dpkg -s "$@" > /dev/null 2>&1; then
        if [ "$(find /var/lib/apt/lists -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)" = "0" ]; then
            apt_get_update
        fi
        apt-get -y install --no-install-recommends "$@"
    fi
}

export DEBIAN_FRONTEND=noninteractive
check_packages apt-transport-https ca-certificates curl gnupg lsb-release

. /etc/os-release

architecture="$(dpkg --print-architecture)"
case "${architecture}" in
    amd64|arm64) ;;
    *)
        echo "(!) Architecture ${architecture} is not supported by the cloudflared APT repository." >&2
        exit 1
        ;;
esac

resolve_repo_codename() {
    local codename="$1"
    case "${codename}" in
        bookworm|bullseye|buster|focal|jammy|bionic)
            echo "${codename}"
            ;;
        noble|lunar|mantic)
            echo "jammy"
            ;;
        trixie)
            echo "bookworm"
            ;;
        *)
            echo "bullseye"
            ;;
    esac
}

requested_codename="${VERSION_CODENAME:-}";
if [ -z "${requested_codename}" ]; then
    requested_codename="$(lsb_release -cs 2>/dev/null || true)"
fi
repo_codename="$(resolve_repo_codename "${requested_codename}")"

keyring_path="/usr/share/keyrings/cloudflare-archive-keyring.gpg"
if [ ! -f "${keyring_path}" ]; then
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | gpg --dearmor | tee "${keyring_path}" > /dev/null
    chmod 0644 "${keyring_path}"
fi

cat <<EOF_SOURCE | tee /etc/apt/sources.list.d/cloudflared.list > /dev/null
deb [arch=${architecture} signed-by=${keyring_path}] https://pkg.cloudflare.com/cloudflared ${repo_codename} main
EOF_SOURCE

apt-get update -y

echo "(*) Installing cloudflared (${CLOUDFLARED_VERSION})..."

resolved_version="${CLOUDFLARED_VERSION}"
case "${CLOUDFLARED_VERSION}" in
    latest|stable|current|lts)
        apt-get install -y cloudflared
        ;;
    *)
        package_version="$(apt-cache madison cloudflared | awk '{print $3}' | grep -E -m 1 "^${CLOUDFLARED_VERSION//./\\.}([\\.\\+~-]|$)")"
        if [ -z "${package_version}" ]; then
            echo "Unable to find cloudflared version matching '${CLOUDFLARED_VERSION}'." >&2
            exit 1
        fi
        resolved_version="${package_version}"
        apt-get install -y cloudflared="${package_version}"
        ;;
esac

if command -v cloudflared > /dev/null 2>&1; then
    installed_version="$(cloudflared --version 2>/dev/null | head -n 1 | awk '{print $3}')"
    if [ -n "${installed_version}" ]; then
        resolved_version="${installed_version}"
    fi
fi

echo "cloudflared ${resolved_version} installed."

# Clean up
rm -rf /var/lib/apt/lists/*

echo "Done!"
