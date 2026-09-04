#!/usr/bin/bash
set -ouex pipefail

source /ctx/build_files/software.env
: "${HOME_SERVER_PACKAGES:?HOME_SERVER_PACKAGES must be set}"
: "${TAILSCALE_PACKAGE:?TAILSCALE_PACKAGE must be set}"
: "${NETBIRD_PACKAGE:?NETBIRD_PACKAGE must be set}"
: "${INTEL_MEDIA_PACKAGE:?INTEL_MEDIA_PACKAGE must be set}"
: "${MERGERFS_VERSION:?MERGERFS_VERSION must be set}"
: "${MERGERFS_SHA256:?MERGERFS_SHA256 must be set}"

# Declarative host configuration.
cp -avf /ctx/system_files/. /

# AlmaLinux 10.1+ enables CRB by default. EPEL software on EL10 expects the
# CRB SELinux policy split to be available, so fail clearly if that changes.
if ! dnf repolist --enabled | grep -Eiq '(^|[[:space:]])crb([[:space:]]|$)'; then
    echo "ERROR: AlmaLinux CRB repository is not enabled."
    exit 1
fi

# EPEL provides several lightweight host-side administration and storage tools.
dnf install -y epel-release curl

# Official third-party repositories used by the generic image.
curl -fsSL \
    https://pkgs.tailscale.com/stable/rhel/10/tailscale.repo \
    -o /etc/yum.repos.d/tailscale.repo

cat > /etc/yum.repos.d/netbird.repo <<'REPO'
[netbird]
name=NetBird
baseurl=https://pkgs.netbird.io/yum/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.netbird.io/yum/repodata/repomd.xml.key
repo_gpgcheck=1
REPO

read -r -a native_packages <<< "${HOME_SERVER_PACKAGES}"
dnf install -y "${native_packages[@]}"

# Intel Quick Sync / VA-API. RPM Fusion is accepted only for the media package
# path; disable its repositories immediately after the required package is installed.
dnf install -y \
    "${RPMFUSION_FREE_RELEASE_URL}" \
    "${RPMFUSION_NONFREE_RELEASE_URL}"
dnf install -y "${INTEL_MEDIA_PACKAGE}"
for repo in /etc/yum.repos.d/rpmfusion*.repo; do
    [[ -f "${repo}" ]] || continue
    sed -ri 's/^enabled=1/enabled=0/' "${repo}"
done

# mergerfs ships an upstream EL10 RPM. Pin both version and checksum.
mergerfs_rpm="/tmp/mergerfs-${MERGERFS_VERSION}.rpm"
mergerfs_url="https://github.com/trapexit/mergerfs/releases/download/${MERGERFS_VERSION}/mergerfs-${MERGERFS_VERSION}-1.el10.x86_64.rpm"
curl -fL "${mergerfs_url}" -o "${mergerfs_rpm}"
printf '%s  %s\n' "${MERGERFS_SHA256}" "${mergerfs_rpm}" | sha256sum -c -
dnf install -y "${mergerfs_rpm}"
rm -f "${mergerfs_rpm}"

# Mesh VPN clients are present but generic images never self-enroll.
dnf install -y "${TAILSCALE_PACKAGE}"
systemctl disable tailscaled.service 2>/dev/null || true

dnf --setopt=tsflags=noscripts install -y "${NETBIRD_PACKAGE}"
systemctl disable netbird.service 2>/dev/null || true

# NUT is host-native, but UPS hardware/configuration is site-specific.
for unit in nut-server.service nut-monitor.service nut-driver@.service; do
    systemctl disable "${unit}" 2>/dev/null || true
done

# Native cockpit-ws is not used. The project ships a system Quadlet for
# quay.io/cockpit/ws and keeps the native bridge/pages on the host.
systemctl disable cockpit.socket cockpit.service 2>/dev/null || true

# Ship project documentation and the Cockpit Quadlet template as reference too.
install -d -m0755 /usr/share/doc/home-server-alma
cp -avf /ctx/docs/. /usr/share/doc/home-server-alma/

install -d -m0755 /usr/share/home-server-alma/quadlets
cp -avf /ctx/quadlets/. /usr/share/home-server-alma/quadlets/

# Services defining the host itself are enabled. Application services remain local policy.
systemctl enable NetworkManager.service 2>/dev/null || true
systemctl enable firewalld.service 2>/dev/null || true
systemctl enable sshd.service 2>/dev/null || true

# Build-time capability checks. If one of these disappears, fail the image.
for cmd in \
    bootc podman nmcli nmtui firewall-cmd sshd \
    upsc nut-scanner tailscale netbird \
    fwupdmgr smartctl sensors nvme lsusb lspci ethtool powertop \
    btop micro tmux jq rsync pv tcpdump dig traceroute nc iperf3 \
    btrfs mergerfs rclone semanage cockpit-bridge spf; do
    command -v "${cmd}"
done

rpm -q \
    zram-generator \
    btrfs-progs \
    nfs-utils \
    samba \
    samba-usershares \
    duperemove \
    mesa-va-drivers \
    libva \
    intel-media-driver \
    cockpit-system \
    cockpit-files \
    cockpit-podman \
    cockpit-storaged \
    nut \
    nut-client \
    smartmontools-selinux

# Fixed zram policy: 4 GiB compressed swap, no disk swap partition required.
test -f /etc/systemd/zram-generator.conf
grep -Eq '^zram-size[[:space:]]*=[[:space:]]*4096$' /etc/systemd/zram-generator.conf

# Validate the Cockpit extension and system Quadlet.
test -f /usr/share/cockpit/upside/manifest.json
test -f /usr/share/containers/systemd/cockpit.container
test -f /usr/share/licenses/superfile/LICENSE

# NUT packages can emit harmless ownership warnings during composition; require
# the completed image to contain the intended account.
getent passwd nut >/dev/null
getent group nut >/dev/null

# Require a readable SELinux policy store after all package transactions.
semodule -l >/dev/null
