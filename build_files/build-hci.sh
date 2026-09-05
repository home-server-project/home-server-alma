#!/usr/bin/bash
set -ouex pipefail

source /ctx/build_files/software.env
: "${HOME_SERVER_HCI_PACKAGES:?HOME_SERVER_HCI_PACKAGES must be set}"

read -r -a hci_packages <<< "${HOME_SERVER_HCI_PACKAGES}"
dnf install -y "${hci_packages[@]}"
dnf install -y /virtui-manager-rpm/virtui-manager-*.noarch.rpm

# AlmaLinux 10 libvirt packages still create these accounts via RPM scriptlets.
# Declare them for bootc using the same sysusers model as uCore HCI.
install -Dm0644 \
    /ctx/build_files/libvirt-workarounds.sysusers.conf \
    /usr/lib/sysusers.d/home-server-alma-libvirt-workarounds.conf

for unit in libvirtd.socket virtqemud.socket; do
    if systemctl cat "${unit}" >/dev/null 2>&1; then
        systemctl enable "${unit}" 2>/dev/null || true
    fi
done

for cmd in virsh virt-install swtpm virtui-manager vmc; do
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
    virtui-manager

PYTHONPATH=/usr/libexec/virtui-manager/python \
    python3 -c 'import textual, libvirt, yaml, requests, netifaces, gi, packaging, markdown_it, vmanager.wrapper'

semodule -l >/dev/null
