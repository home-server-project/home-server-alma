# Image Health and Update Policy

This document defines what may block a Home Server Alma image release and how external software is updated.

## Latest by default

Home Server Alma follows current stable upstream software on every rebuild.

For external projects that are not installed directly from Alma/EPEL repositories:

- mergerfs: resolve the latest stable GitHub release and its EL10 x86_64 RPM
- UPSide: resolve the latest stable tag
- Superfile: resolve the latest stable tag
- VirtUI Manager: resolve the latest stable tag
- VirtUI's private Textual dependency: follow the requirement declared by the selected VirtUI release

Normal operation does **not** pin these versions in the repository.

`build_files/software.env` contains empty emergency pin variables. A pin is used only after an upstream regression is demonstrated and should be removed when the upstream issue is resolved.

For mergerfs, the release is dynamic but integrity verification remains strict: CI reads the SHA-256 digest published with the selected GitHub release asset and verifies the downloaded EL10 RPM before installation.

## Critical health contract

A critical failure blocks the affected image before GHCR push, signing or GitHub Release creation.

Both images require:

- bootc container lint
- valid image trust configuration and readable SELinux policy
- Podman and Quadlet integration
- NetworkManager, firewalld and SSH tooling
- Cockpit host bridge/pages required by the base design
- fixed 4 GiB zram configuration
- Btrfs userspace tools with a disposable filesystem smoke test
- NFS and Samba core tooling
- Intel/AMD media userspace package contract
- mergerfs package plus a real FUSE mount/read/write/unmount smoke test

The mergerfs functional test is intentionally strict because a broken mergerfs layer can make application storage unavailable to services such as Jellyfin.

HCI additionally requires:

- cockpit-machines
- libvirt client and KVM daemon packages
- QEMU/KVM
- virt-install
- swtpm and VM firmware
- VirtUI Manager
- working VirtUI Python imports and CLI entry points

CI does not claim that nested KVM itself works merely because GitHub Actions passes. Real VM creation/boot, bridge networking, UEFI and TPM remain VM/bare-metal acceptance tests.

## Optional/degraded health

The following capabilities are intended to be present on both images but do not justify blocking an otherwise healthy OS/security rebuild by themselves:

- NUT / UPS utilities
- UPSide
- Tailscale
- NetBird
- WireGuard tooling
- fwupd and hardware diagnostic tools
- PowerTOP
- btop
- Micro
- Superfile
- fastfetch
- tmux
- jq/rsync/pv and similar administration utilities
- rclone/duperemove and other non-runtime storage helpers

Optional failures are reported as `WARN` / `OPTIONAL HEALTH: DEGRADED` in the GitHub Actions summary.

Degraded does not mean ignored. It means the image remains operational and may still receive important OS updates while the optional regression is investigated.

## Release gate

The pipeline is:

```text
resolve current dependencies
        |
        v
build both images in parallel
        |
        v
critical common health
        |
        +---- base: confirm HCI stack absent
        |
        +---- HCI: critical virtualization health
        |
        v
optional health report
        |
        v
push -> sign -> verify
        |
        v
GitHub Release only after both matrix images succeed
```

A failed critical check means no new moving `:10` image for that target and therefore no paired GitHub Release.
