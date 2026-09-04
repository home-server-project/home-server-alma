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

# bootc images must not carry build-time package-manager/runtime state in /var.
dnf clean all
rm -rf /var
install -d -m0755 /var

jq empty /etc/containers/policy.json
test -f /usr/lib/pki/containers/home-server-project.pub
test -f /etc/containers/registries.d/ghcr.io-home-server-project.yaml
grep -Fq "${IMAGE_REPOSITORY}:" /etc/containers/registries.d/ghcr.io-home-server-project.yaml
grep -Fq "use-sigstore-attachments: true" /etc/containers/registries.d/ghcr.io-home-server-project.yaml
