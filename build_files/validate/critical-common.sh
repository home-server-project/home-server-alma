#!/usr/bin/bash
set -euo pipefail

pass() { printf 'PASS  %s\n' "$*"; }

bootc container lint --fatal-warnings
pass 'bootc container lint'

jq empty /etc/containers/policy.json
semodule -l >/dev/null
pass 'container trust JSON and SELinux policy'

test -f /usr/lib/pki/containers/home-server-project.pub
test -f /etc/containers/registries.d/ghcr.io-home-server-project.yaml
test -f /usr/share/containers/systemd/cockpit.container
pass 'image trust and Cockpit Quadlet files'

test -f /etc/sudoers.d/90-home-server-alma-passwordless-wheel
test "$(stat -c '%a %U %G' /etc/sudoers.d/90-home-server-alma-passwordless-wheel)" = "440 root root"
grep -Fqx '%wheel ALL=(ALL) NOPASSWD: ALL' /etc/sudoers.d/90-home-server-alma-passwordless-wheel
visudo -cf /etc/sudoers >/dev/null
pass 'passwordless wheel administration'

test -f /etc/systemd/zram-generator.conf
grep -Eq '^zram-size[[:space:]]*=[[:space:]]*4096$' /etc/systemd/zram-generator.conf
pass '4 GiB zram policy'

test -f /etc/NetworkManager/conf.d/90-systemd-resolved.conf
grep -Fqx 'dns=systemd-resolved' /etc/NetworkManager/conf.d/90-systemd-resolved.conf
test -f /usr/lib/tmpfiles.d/home-server-alma-resolved.conf
grep -Fqx 'L+ /etc/resolv.conf - - - - /run/systemd/resolve/stub-resolv.conf' \
    /usr/lib/tmpfiles.d/home-server-alma-resolved.conf
test "$(systemctl is-enabled systemd-resolved.service)" = "enabled"
pass 'systemd-resolved split-DNS integration'

test -f /usr/lib/systemd/system/home-server-alma-update.service
test -f /usr/lib/systemd/system/home-server-alma-update.timer
test "$(systemctl is-enabled bootc-fetch-apply-updates.timer)" = "masked"
test "$(systemctl is-enabled bootc-fetch-apply-updates.service)" = "masked"
test "$(systemctl is-enabled home-server-alma-update.timer)" = "enabled"
pass 'staged bootc update policy without automatic reboot'

test "$(stat -c '%a %U %G' /var/tmp)" = "1777 root root"
pass '/var/tmp early-boot mountpoint'

for cmd in \
    sudo visudo podman nmcli resolvectl firewall-cmd sshd cockpit-bridge \
    mergerfs btrfs mkfs.btrfs exportfs smbd testparm; do
    command -v "${cmd}" >/dev/null
    pass "command ${cmd}"
done

rpm -q \
    sudo systemd-resolved \
    btrfs-progs nfs-utils samba \
    intel-compute-runtime \
    cockpit-system cockpit-files cockpit-podman cockpit-storaged >/dev/null
pass 'critical package contract'

# Functional Btrfs userspace smoke test on a disposable regular file.
tmp="$(mktemp -d)"
cleanup() {
    if mountpoint -q "${tmp}/merged" 2>/dev/null; then
        umount "${tmp}/merged" || true
    fi
    rm -rf "${tmp}"
}
trap cleanup EXIT

truncate -s 256M "${tmp}/btrfs.img"
mkfs.btrfs -f "${tmp}/btrfs.img" >/dev/null
btrfs inspect-internal dump-super "${tmp}/btrfs.img" >/dev/null
pass 'Btrfs userspace functional smoke test'

# mergerfs is a release-critical storage dependency: prove an actual FUSE pool works.
mkdir -p "${tmp}/disk-a" "${tmp}/disk-b" "${tmp}/merged"
printf 'disk-a\n' > "${tmp}/disk-a/from-a"
printf 'disk-b\n' > "${tmp}/disk-b/from-b"
mergerfs -o cache.files=off,category.create=ff \
    "${tmp}/disk-a:${tmp}/disk-b" "${tmp}/merged"

test "$(cat "${tmp}/merged/from-a")" = 'disk-a'
test "$(cat "${tmp}/merged/from-b")" = 'disk-b'
printf 'through-pool\n' > "${tmp}/merged/write-test"
if [[ ! -f "${tmp}/disk-a/write-test" && ! -f "${tmp}/disk-b/write-test" ]]; then
    echo 'ERROR: mergerfs write did not reach either backing directory.' >&2
    exit 1
fi
umount "${tmp}/merged"
pass 'mergerfs functional FUSE mount/read/write/unmount'

printf 'CRITICAL COMMON HEALTH: PASS\n'
