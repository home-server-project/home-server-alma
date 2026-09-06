#!/usr/bin/bash
set -ouex pipefail

source /ctx/build_files/software.env
: "${HOME_SERVER_CRITICAL_PACKAGES:?HOME_SERVER_CRITICAL_PACKAGES must be set}"
: "${HOME_SERVER_OPTIONAL_PACKAGES:?HOME_SERVER_OPTIONAL_PACKAGES must be set}"
: "${TAILSCALE_PACKAGE:?TAILSCALE_PACKAGE must be set}"
: "${NETBIRD_PACKAGE:?NETBIRD_PACKAGE must be set}"
: "${MERGERFS_URL:?MERGERFS_URL must be set}"
: "${MERGERFS_SHA256:?MERGERFS_SHA256 must be set}"

cp -avf /ctx/system_files/. /
chmod 0440 /etc/sudoers.d/90-home-server-alma-passwordless-wheel

if ! dnf repolist --enabled | grep -Eiq '(^|[[:space:]])crb([[:space:]]|$)'; then
    echo "ERROR: AlmaLinux CRB repository is not enabled."
    exit 1
fi

dnf install -y epel-release curl

read -r -a critical_packages <<< "${HOME_SERVER_CRITICAL_PACKAGES}"
dnf install -y "${critical_packages[@]}"

install -d -m0755 /usr/share/home-server-alma/build-health
install_optional_package() {
    local package="$1"
    local marker="/usr/share/home-server-alma/build-health/${package}.failed"
    if dnf install -y "${package}"; then
        rm -f "${marker}"
    else
        printf 'Optional package failed to install during image build: %s\n' "${package}" > "${marker}"
        echo "WARNING: optional package ${package} failed to install; image will be marked degraded."
    fi
}

read -r -a optional_packages <<< "${HOME_SERVER_OPTIONAL_PACKAGES}"
for package in "${optional_packages[@]}"; do
    install_optional_package "${package}"
done

# mergerfs always follows the latest stable upstream EL10 RPM unless an emergency pin
# is configured. The workflow resolves the exact asset and its upstream-published digest.
mergerfs_rpm="/tmp/mergerfs.rpm"
curl -fL "${MERGERFS_URL}" -o "${mergerfs_rpm}"
printf '%s  %s\n' "${MERGERFS_SHA256}" "${mergerfs_rpm}" | sha256sum -c -
dnf install -y "${mergerfs_rpm}"
rm -f "${mergerfs_rpm}"

if curl -fsSL \
    https://pkgs.tailscale.com/stable/rhel/10/tailscale.repo \
    -o /etc/yum.repos.d/tailscale.repo; then
    sed -ri 's/^enabled=1/enabled=0/' /etc/yum.repos.d/tailscale.repo || true
    if dnf --enablerepo=tailscale-stable install -y "${TAILSCALE_PACKAGE}"; then
        systemctl disable tailscaled.service 2>/dev/null || true
    else
        echo 'Optional Tailscale package failed to install.' > /usr/share/home-server-alma/build-health/tailscale.failed
    fi
else
    echo 'Optional Tailscale repository failed to resolve.' > /usr/share/home-server-alma/build-health/tailscale.failed
fi

cat > /etc/yum.repos.d/netbird.repo <<'REPO'
[netbird]
name=NetBird
baseurl=https://pkgs.netbird.io/yum/
enabled=0
gpgcheck=1
gpgkey=https://pkgs.netbird.io/yum/repodata/repomd.xml.key
repo_gpgcheck=1
REPO
if dnf --setopt=tsflags=noscripts --enablerepo=netbird install -y "${NETBIRD_PACKAGE}"; then
    systemctl disable netbird.service 2>/dev/null || true
else
    echo 'Optional NetBird package failed to install.' > /usr/share/home-server-alma/build-health/netbird.failed
fi

for unit in nut-server.service nut-monitor.service nut-driver@.service; do
    systemctl disable "${unit}" 2>/dev/null || true
done

systemctl disable cockpit.socket cockpit.service 2>/dev/null || true

# Stage bootc updates automatically but never let the generic upstream update
# units reboot a home server without administrator control.
systemctl mask bootc-fetch-apply-updates.timer bootc-fetch-apply-updates.service
systemctl enable home-server-alma-update.timer

install -d -m0755 /usr/share/doc/home-server-alma
cp -avf /ctx/docs/. /usr/share/doc/home-server-alma/

install -d -m0755 /usr/share/home-server-alma/quadlets
cp -avf /ctx/quadlets/. /usr/share/home-server-alma/quadlets/

install -d -m0755 /usr/libexec/home-server-alma/health
install -m0755 /ctx/build_files/validate/critical-common.sh \
    /usr/libexec/home-server-alma/health/critical-common
install -m0755 /ctx/build_files/validate/critical-hci.sh \
    /usr/libexec/home-server-alma/health/critical-hci
install -m0755 /ctx/build_files/validate/optional.sh \
    /usr/libexec/home-server-alma/health/optional

systemctl enable NetworkManager.service 2>/dev/null || true
systemctl enable systemd-resolved.service
systemctl enable firewalld.service 2>/dev/null || true
systemctl enable sshd.service 2>/dev/null || true

# Cheap build-time checks. Functional release gates run against the completed image in CI.
for cmd in bootc podman nmcli nmtui firewall-cmd sshd resolvectl sudo visudo btrfs mergerfs cockpit-bridge; do
    command -v "${cmd}"
done

rpm -q \
    sudo \
    systemd-resolved \
    zram-generator \
    btrfs-progs \
    nfs-utils \
    samba \
    intel-compute-runtime \
    cockpit-system \
    cockpit-files \
    cockpit-podman \
    cockpit-storaged

test -f /etc/sudoers.d/90-home-server-alma-passwordless-wheel
test "$(stat -c '%a %U %G' /etc/sudoers.d/90-home-server-alma-passwordless-wheel)" = "440 root root"
grep -Fqx '%wheel ALL=(ALL) NOPASSWD: ALL' /etc/sudoers.d/90-home-server-alma-passwordless-wheel
visudo -cf /etc/sudoers

test -f /etc/systemd/zram-generator.conf
grep -Eq '^zram-size[[:space:]]*=[[:space:]]*4096$' /etc/systemd/zram-generator.conf

test -f /etc/NetworkManager/conf.d/90-systemd-resolved.conf
grep -Fqx '[main]' /etc/NetworkManager/conf.d/90-systemd-resolved.conf
grep -Fqx 'dns=systemd-resolved' /etc/NetworkManager/conf.d/90-systemd-resolved.conf

test -f /usr/lib/tmpfiles.d/home-server-alma-resolved.conf
grep -Fqx 'L+ /etc/resolv.conf - - - - /run/systemd/resolve/stub-resolv.conf' \
    /usr/lib/tmpfiles.d/home-server-alma-resolved.conf

test -f /usr/lib/systemd/system/home-server-alma-update.service
test -f /usr/lib/systemd/system/home-server-alma-update.timer
test "$(systemctl is-enabled bootc-fetch-apply-updates.timer)" = "masked"
test "$(systemctl is-enabled bootc-fetch-apply-updates.service)" = "masked"
test "$(systemctl is-enabled home-server-alma-update.timer)" = "enabled"
test "$(systemctl is-enabled systemd-resolved.service)" = "enabled"

semodule -l >/dev/null
