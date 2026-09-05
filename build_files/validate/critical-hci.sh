#!/usr/bin/bash
set -euo pipefail

pass() { printf 'PASS  %s\n' "$*"; }

rpm -q \
    cockpit-machines libvirt-client libvirt-daemon-kvm qemu-kvm \
    virt-install swtpm edk2-ovmf libosinfo osinfo-db virtui-manager >/dev/null
pass 'HCI critical package contract'

for cmd in virsh virt-install swtpm virtui-manager vmc; do
    command -v "${cmd}" >/dev/null
    pass "command ${cmd}"
done

test -x /usr/libexec/qemu-kvm
pass 'RHEL QEMU KVM binary'

virsh --version >/dev/null
virt-install --version >/dev/null
/usr/libexec/qemu-kvm --version >/dev/null
swtpm --version >/dev/null
pass 'libvirt/QEMU/TPM binaries initialize'

if ! command -v libvirtd >/dev/null && ! command -v virtqemud >/dev/null; then
    echo 'ERROR: neither libvirtd nor virtqemud is installed.' >&2
    exit 1
fi
pass 'libvirt daemon implementation present'

test -f /usr/share/cockpit/machines/manifest.json
pass 'Cockpit Machines plugin'

PYTHONPATH=/usr/libexec/virtui-manager/python \
    python3 -c 'import textual, libvirt, yaml, requests, netifaces, gi, packaging, markdown_it; from vmanager import wrapper; assert callable(wrapper.main); assert callable(wrapper.cmd_main)'
pass 'VirtUI Manager imports and CLI entry points'

printf 'CRITICAL HCI HEALTH: PASS\n'
