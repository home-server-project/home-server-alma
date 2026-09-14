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
chmod 0440 /etc/sudoers.d/90-home-server-rose-passwordless-wheel

if ! dnf repolist --enabled | grep -Eiq '(^|[[:space:]])crb([[:space:]]|$)'; then
    echo "ERROR: AlmaLinux CRB repository is not enabled."
    exit 1
fi

dnf install -y epel-release curl

read -r -a critical_packages <<< "${HOME_SERVER_CRITICAL_PACKAGES}"
dnf install -y "${critical_packages[@]}"

install -d -m0755 /usr/share/home-server-rose/build-health
install_optional_package() {
    local package="$1"
    local marker="/usr/share/home-server-rose/build-health/${package}.failed"
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

# EL10 bootc keeps vendor groups in /usr/lib/group while systemd-sysusers can
# place supplementary memberships in /etc/gshadow. NUT runtime access expects
# its service account to carry tty and dialout membership in the image-managed
# group database itself.
if rpm -q nut >/dev/null 2>&1 && getent passwd nut >/dev/null 2>&1; then
    for group_name in tty dialout; do
        if ! grep -q "^${group_name}:" /usr/lib/group; then
            printf 'Required NUT group is missing from /usr/lib/group: %s\n' "${group_name}" \
                > /usr/share/home-server-rose/build-health/nut-groups.failed
            continue
        fi
    done

    if [[ ! -f /usr/share/home-server-rose/build-health/nut-groups.failed ]]; then
        awk -F: -v OFS=: '
        $1 == "tty" || $1 == "dialout" {
            count = split($4, members, ",")
            found = 0
            for (i = 1; i <= count; i++) {
                if (members[i] == "nut")
                    found = 1
            }
            if (!found)
                $4 = ($4 == "" ? "nut" : $4 ",nut")
        }
        { print }
        ' /usr/lib/group > /tmp/home-server-rose-group
        install -o root -g root -m0644 /tmp/home-server-rose-group /usr/lib/group
        rm -f /tmp/home-server-rose-group
    fi

    # Preserve the package-declared secure ownership and permissions for NUT
    # server configuration in the vendor /etc payload.
    for nut_file in /etc/ups/upsd.conf /etc/ups/upsd.users; do
        if [[ -f "${nut_file}" ]]; then
            chown root:nut "${nut_file}"
            chmod 0640 "${nut_file}"
        else
            printf 'Expected NUT configuration file is missing: %s\n' "${nut_file}" \
                >> /usr/share/home-server-rose/build-health/nut-config.failed
        fi
    done
fi

# PCP provides UPSide historical trends. Keep the focused PCP + OpenMetrics set
# and enable the two host-native collection services only when PCP installed.
if rpm -q pcp >/dev/null 2>&1; then
    if ! systemctl enable pmcd.service pmlogger.service; then
        printf 'PCP installed but pmcd/pmlogger could not be enabled.\n' \
            > /usr/share/home-server-rose/build-health/pcp-services.failed
    fi
fi

# Home Server Packages owns source tracking, package builds, and cross-distro
# validation for these utilities. Rose consumes the exact RPM artifacts selected
# by the workflow for this image build.
dnf install -y \
    /upside-rpm/cockpit-upside-*.noarch.rpm \
    /superfile-rpm/superfile-*.x86_64.rpm

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
        echo 'Optional Tailscale package failed to install.' > /usr/share/home-server-rose/build-health/tailscale.failed
    fi
else
    echo 'Optional Tailscale repository failed to resolve.' > /usr/share/home-server-rose/build-health/tailscale.failed
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
    echo 'Optional NetBird package failed to install.' > /usr/share/home-server-rose/build-health/netbird.failed
fi

for unit in nut-server.service nut-monitor.service nut-driver@.service; do
    systemctl disable "${unit}" 2>/dev/null || true
done

systemctl disable cockpit.socket cockpit.service 2>/dev/null || true

# Stage bootc updates automatically but never let the generic upstream update
# units reboot a home server without administrator control.
systemctl mask bootc-fetch-apply-updates.timer bootc-fetch-apply-updates.service
systemctl enable home-server-rose-update.timer

install -d -m0755 /usr/share/doc/home-server-rose
cp -avf /ctx/docs/. /usr/share/doc/home-server-rose/

install -d -m0755 /usr/share/home-server-rose/quadlets
cp -avf /ctx/quadlets/. /usr/share/home-server-rose/quadlets/

install -d -m0755 /usr/libexec/home-server-rose/health
install -m0755 /ctx/build_files/validate/critical-common.sh \
    /usr/libexec/home-server-rose/health/critical-common
install -m0755 /ctx/build_files/validate/critical-hci.sh \
    /usr/libexec/home-server-rose/health/critical-hci
install -m0755 /ctx/build_files/validate/optional.sh \
    /usr/libexec/home-server-rose/health/optional
install -m0755 /ctx/build_files/validate/identity.sh \
    /usr/libexec/home-server-rose/health/identity

systemctl enable NetworkManager.service 2>/dev/null || true
systemctl enable systemd-resolved.service
systemctl enable firewalld.service 2>/dev/null || true
systemctl enable sshd.service 2>/dev/null || true

# Cheap build-time checks. Functional release gates run against the completed image in CI.
for cmd in bootc podman nmcli nmtui firewall-cmd sshd resolvectl sudo visudo btrfs mergerfs cockpit-bridge spf; do
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
    cockpit-storaged \
    cockpit-upside \
    superfile

test -f /usr/share/cockpit/upside/manifest.json

test -f /etc/sudoers.d/90-home-server-rose-passwordless-wheel
test "$(stat -c '%a %U %G' /etc/sudoers.d/90-home-server-rose-passwordless-wheel)" = "440 root root"
grep -Fqx '%wheel ALL=(ALL) NOPASSWD: ALL' /etc/sudoers.d/90-home-server-rose-passwordless-wheel
visudo -cf /etc/sudoers

test -f /etc/systemd/zram-generator.conf
grep -Eq '^zram-size[[:space:]]*=[[:space:]]*4096$' /etc/systemd/zram-generator.conf

test -f /etc/NetworkManager/conf.d/90-systemd-resolved.conf
grep -Fqx '[main]' /etc/NetworkManager/conf.d/90-systemd-resolved.conf
grep -Fqx 'dns=systemd-resolved' /etc/NetworkManager/conf.d/90-systemd-resolved.conf

test -f /usr/lib/tmpfiles.d/home-server-rose-resolved.conf
grep -Fqx 'L+ /etc/resolv.conf - - - - /run/systemd/resolve/stub-resolv.conf' \
    /usr/lib/tmpfiles.d/home-server-rose-resolved.conf

test -f /usr/lib/systemd/system/home-server-rose-update.service
test -f /usr/lib/systemd/system/home-server-rose-update.timer
test "$(systemctl is-enabled bootc-fetch-apply-updates.timer)" = "masked"
test "$(systemctl is-enabled bootc-fetch-apply-updates.service)" = "masked"
test "$(systemctl is-enabled home-server-rose-update.timer)" = "enabled"
test "$(systemctl is-enabled systemd-resolved.service)" = "enabled"

semodule -l >/dev/null
