#!/usr/bin/bash
set -ouex pipefail

source /ctx/build_files/software.env
: "${HOME_SERVER_HCI_PACKAGES:?HOME_SERVER_HCI_PACKAGES must be set}"

read -r -a hci_packages <<< "${HOME_SERVER_HCI_PACKAGES}"
dnf install -y "${hci_packages[@]}"
dnf install -y /virtui-manager-rpm/virtui-manager-*.noarch.rpm

# Make libvirt available on demand. Alma may expose either the monolithic or
# modular daemon sockets depending on package version.
for unit in libvirtd.socket virtqemud.socket; do
    if systemctl cat "${unit}" >/dev/null 2>&1; then
        systemctl enable "${unit}" 2>/dev/null || true
    fi
done

for cmd in virsh virt-install swtpm virtui-manager vmc websockify; do
    command -v "${cmd}"
done

rpm -q \
    cockpit-machines \
    libvirt-client \
    libvirt-daemon-kvm \
    qemu-kvm \
    virt-install \
    swtpm \
    edk2-ovmf \
    libosinfo \
    osinfo-db \
    novnc \
    python3-websockify \
    virtui-manager

test -d /usr/share/novnc

PYTHONPATH=/usr/libexec/virtui-manager/python \
    python3 -c 'import textual, libvirt, yaml, requests, netifaces, gi, packaging, markdown_it, vmanager.wrapper'

# Overlay-backed bootc builds can expose SELinux package-scriptlet edge cases.
# The final policy store must remain readable.
semodule -l >/dev/null
