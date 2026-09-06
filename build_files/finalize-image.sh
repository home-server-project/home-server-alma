#!/usr/bin/bash
set -ouex pipefail

: "${IMAGE_REPOSITORY:?IMAGE_REPOSITORY must be set}"
: "${IMAGE_PRETTY_NAME:?IMAGE_PRETTY_NAME must be set}"
: "${IMAGE_VARIANT:?IMAGE_VARIANT must be set}"

/ctx/build_files/install-image-trust.sh "${IMAGE_REPOSITORY}"

# Preserve AlmaLinux identity while clearly naming this derivative image.
sed -i "s|^PRETTY_NAME=.*|PRETTY_NAME=\"${IMAGE_PRETTY_NAME}\"|" /usr/lib/os-release
if grep -q '^VARIANT=' /usr/lib/os-release; then
    sed -i "s|^VARIANT=.*|VARIANT=\"${IMAGE_VARIANT}\"|" /usr/lib/os-release
else
    printf 'VARIANT="%s"\n' "${IMAGE_VARIANT}" >> /usr/lib/os-release
fi

# External package repositories are build-time inputs only. Keep their files for
# provenance and future image composition, but do not leave them enabled on the
# deployed immutable host.
for repo_file in \
    /etc/yum.repos.d/epel*.repo \
    /etc/yum.repos.d/tailscale.repo \
    /etc/yum.repos.d/netbird.repo; do
    [[ -e "${repo_file}" ]] || continue
    sed -Ei 's/^[[:space:]]*enabled[[:space:]]*=[[:space:]]*1[[:space:]]*$/enabled=0/' "${repo_file}"
done

if dnf repolist --enabled | grep -Eiq 'epel|tailscale|netbird'; then
    echo "ERROR: an external package repository remains enabled in the final image."
    dnf repolist --enabled
    exit 1
fi

# bootc images must not carry build-time package-manager/runtime state in /var.
# Keep /var/tmp in the image skeleton because early services such as
# systemd-resolved can require PrivateTmp before systemd-tmpfiles-setup runs.
dnf clean all
rm -rf /var
install -d -m0755 /var
install -d -m1777 /var/tmp
test "$(stat -c '%a %U %G' /var/tmp)" = "1777 root root"

jq empty /etc/containers/policy.json
test -f /usr/lib/pki/containers/home-server-project.pub
test -f /etc/containers/registries.d/ghcr.io-home-server-project.yaml
grep -Fq "${IMAGE_REPOSITORY}:" /etc/containers/registries.d/ghcr.io-home-server-project.yaml
grep -Fq "use-sigstore-attachments: true" /etc/containers/registries.d/ghcr.io-home-server-project.yaml
