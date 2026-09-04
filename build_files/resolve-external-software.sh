#!/usr/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/build_files/software.env"

output="${1:-/tmp/home-server-alma-external.env}"

latest_stable_tag() {
    local repository="$1"
    git ls-remote --tags --refs "${repository}" \
        | awk '{sub("refs/tags/", "", $2); print $2}' \
        | grep -E '^v?[0-9]+([.][0-9]+){1,2}$' \
        | sort -V \
        | tail -n 1
}

resolve_tag() {
    local name="$1"
    local repository="$2"
    local pin="$3"
    local required="$4"
    local tag=""

    if [[ -n "${pin}" ]]; then
        if git ls-remote --exit-code --tags --refs "${repository}" "refs/tags/${pin}" >/dev/null 2>&1; then
            tag="${pin}"
        elif [[ "${required}" == "required" ]]; then
            echo "ERROR: ${name} pin ${pin} does not exist." >&2
            return 1
        else
            echo "WARNING: ${name} pin ${pin} does not exist; feature will be degraded." >&2
        fi
    else
        tag="$(latest_stable_tag "${repository}" || true)"
        if [[ -z "${tag}" ]]; then
            if [[ "${required}" == "required" ]]; then
                echo "ERROR: could not resolve a stable ${name} tag." >&2
                return 1
            fi
            echo "WARNING: could not resolve a stable ${name} tag; feature will be degraded." >&2
        fi
    fi

    printf '%s' "${tag}"
}

curl_args=(-fsSL -H 'Accept: application/vnd.github+json')
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

if [[ -n "${MERGERFS_PIN}" ]]; then
    mergerfs_endpoint="${MERGERFS_RELEASE_API}/tags/${MERGERFS_PIN}"
else
    mergerfs_endpoint="${MERGERFS_RELEASE_API}/latest"
fi

mergerfs_json="$(curl "${curl_args[@]}" "${mergerfs_endpoint}")"
mergerfs_tag="$(jq -er '.tag_name' <<<"${mergerfs_json}")"
mergerfs_asset="$(
    jq -er '
        .assets[]
        | select(.name | test("^mergerfs-.*[.]el10[.]x86_64[.]rpm$"))
        | [.browser_download_url, .digest]
        | @tsv
    ' <<<"${mergerfs_json}" | head -n 1
)"

IFS=$'\t' read -r mergerfs_url mergerfs_digest <<<"${mergerfs_asset}"
if [[ ! "${mergerfs_digest}" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    echo "ERROR: mergerfs release ${mergerfs_tag} has no usable upstream SHA-256 digest." >&2
    exit 1
fi
mergerfs_sha256="${mergerfs_digest#sha256:}"

upside_tag="$(resolve_tag UPSide "${UPSIDE_REPOSITORY}" "${UPSIDE_PIN}" optional)"
superfile_tag="$(resolve_tag Superfile "${SUPERFILE_REPOSITORY}" "${SUPERFILE_PIN}" optional)"
virtui_tag="$(resolve_tag 'VirtUI Manager' "${VIRTUI_MANAGER_REPOSITORY}" "${VIRTUI_MANAGER_PIN}" optional)"

cat > "${output}" <<EOF_OUT
mergerfs_tag=${mergerfs_tag}
mergerfs_url=${mergerfs_url}
mergerfs_sha256=${mergerfs_sha256}
upside_tag=${upside_tag}
superfile_tag=${superfile_tag}
virtui_tag=${virtui_tag}
EOF_OUT

cat "${output}"
