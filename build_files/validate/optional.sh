#!/usr/bin/bash
set -u

degraded=0
pass() { printf 'PASS  %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; degraded=1; }

check_cmd() {
    local cmd="$1"
    if command -v "${cmd}" >/dev/null 2>&1; then
        pass "${cmd}"
    else
        warn "${cmd} missing"
    fi
}

check_file() {
    local path="$1"
    if [[ -f "${path}" ]]; then
        pass "file ${path}"
    else
        warn "file ${path} missing"
    fi
}

check_exec() {
    local path="$1"
    if [[ -x "${path}" ]]; then
        pass "executable ${path}"
    else
        warn "executable ${path} missing"
    fi
}

check_enabled() {
    local unit="$1"
    if [[ "$(systemctl is-enabled "${unit}" 2>/dev/null || true)" == "enabled" ]]; then
        pass "${unit} enabled"
    else
        warn "${unit} not enabled"
    fi
}

for cmd in upsc nut-scanner pmlogger pminfo snmpget tailscale netbird fwupdmgr smartctl sensors nvme \
           lsusb lspci ethtool powertop btop micro nano vim openssl lsof file unzip \
           tmux jq rsync pv tcpdump dig traceroute nc iperf3 rclone; do
    check_cmd "${cmd}"
done

if [[ -e /usr/lib64/libusb-1.0.so ]]; then
    pass 'NUT USB libusb development link'
else
    warn '/usr/lib64/libusb-1.0.so missing'
fi

if getent passwd nut >/dev/null 2>&1; then
    for group_name in tty dialout; do
        if id -nG nut 2>/dev/null | tr ' ' '\n' | grep -Fxq "${group_name}"; then
            pass "nut membership in ${group_name}"
        else
            warn "nut missing ${group_name} membership"
        fi
    done
else
    warn 'nut service account missing'
fi

for nut_file in /etc/ups/upsd.conf /etc/ups/upsd.users; do
    if [[ -f "${nut_file}" ]]; then
        if [[ "$(stat -c '%a %U %G' "${nut_file}" 2>/dev/null || true)" == "640 root nut" ]]; then
            pass "${nut_file} permissions"
        else
            warn "${nut_file} permissions are not 640 root nut"
        fi
    else
        warn "${nut_file} missing"
    fi
done

check_exec /usr/libexec/pcp/bin/pmcd
check_exec /usr/libexec/pcp/pmdas/openmetrics/Install
check_file /usr/lib/tmpfiles.d/pcp-pmda-openmetrics.conf
check_enabled pmcd.service
check_enabled pmlogger.service

if [[ -d /usr/share/home-server-rose/build-health ]]; then
    while IFS= read -r marker; do
        [[ -n "${marker}" ]] || continue
        warn "build marker: $(basename "${marker}")"
    done < <(find /usr/share/home-server-rose/build-health -maxdepth 1 -type f -name '*.failed' -print | sort)
fi

if (( degraded )); then
    printf 'OPTIONAL HEALTH: DEGRADED\n'
else
    printf 'OPTIONAL HEALTH: PASS\n'
fi

# Optional health never blocks publishing by itself.
exit 0
