# Home Server Alma — Architecture and Feature Roadmap

**Status:** Implementation in development  
**Date:** 2026-09-04  
**Repository:** https://github.com/home-server-project/home-server-alma  
**Images:** `home-server-alma` and `home-server-alma-hci`

> This is the durable implementation reference for the project. Scope changes continue to follow the normal proposal -> greenlight -> execute workflow.

## 1. Goal

Build a boring, understandable AlmaLinux 10 bootc home-server operating system from AlmaLinux's **minimal-plus** content tier.

The repository builds two images from the same shared Home Server layer:

```text
AlmaLinux 10 minimal-plus
          |
          v
 Home Server Alma
          |
          | + KVM/QEMU/libvirt
          | + cockpit-machines
          | + virsh / virt-install
          | + VirtUI Manager
          | + direct VM dependencies
          v
 Home Server Alma HCI
```

The HCI image is **not** a fuller general server edition. It is exactly **Home Server Alma + virtualization**.

Everything useful to a normal home server belongs on **both** images. Only virtualization and tools that directly manage virtual machines belong only on HCI.

## 2. Foundation

Use AlmaLinux 10 **minimal-plus**, not Alma's broad standard bootc image.

The custom manifest follows the Alma Black Box testing pattern and retains selected standard behavior:

- `minimal-plus/manifest.yaml`
- `standard/autoupdates.yaml`
- `standard/system-configuration.yaml`
- `standard/persistent-journal.yaml`
- `standard/generic-growfs.yaml`

Initial root filesystem for bootc installation: **XFS**.

Btrfs is supported as a normal data filesystem through `btrfs-progs`.

Initial CPU architecture: normal AlmaLinux 10 **x86-64-v3**. An x86-64-v2 image is a separate future investigation and is not part of the first build.

## 3. Container model

The application deployment model is:

**Podman + systemd Quadlets**.

Both images include Podman, SELinux/container support and Cockpit Podman integration.

Do not include by default:

- Docker/Moby
- `docker-compose`
- `docker-buildx`
- `podman-compose`

Large replaceable applications such as Jellyfin, Vaultwarden, databases, media automation, download stacks, monitoring stacks and reverse proxies belong in Quadlets rather than the OS image.

No rpm-ostree layering workflow is part of this project. Host changes belong in rebuilt bootc images.

## 4. Features on both images

### Core host

- bootc
- NetworkManager
- NetworkManager TUI
- Wi-Fi support
- firewalld
- OpenSSH
- Podman / Quadlets
- SELinux tooling
- persistent journal
- generic filesystem growth
- image signing and image trust

### Cockpit

Native host pages/bridge:

- `cockpit-system`
- `cockpit-files`
- `cockpit-podman`
- `cockpit-storaged`
- UPSide

The web-facing `cockpit-ws` service is provided as a Podman Quadlet using `quay.io/cockpit/ws:latest`, following the immutable-host pattern already used by uCore/Alma Black Box.

### UPS and power

- NUT
- NUT client
- UPSide
- PowerTOP

NUT is included but never preconfigured. UPS model, USB identifiers, users/passwords and shutdown policy are local machine configuration. A server without a UPS should simply leave NUT unconfigured.

PowerTOP is diagnostic only; the image does not automatically run `powertop --auto-tune`.

### Networking and remote access

- Tailscale
- NetBird
- WireGuard tools
- `ethtool`
- `tcpdump`
- DNS tools
- traceroute
- ncat/netcat
- iperf3

Tailscale and NetBird are installed but not enrolled or configured by the generic image.

### Storage/NAS

- XFS support for system/root
- `btrfs-progs`
- mergerfs
- NFS tools
- Samba
- Samba usershares
- rclone
- duperemove
- SMART tools
- NVMe CLI
- hdparm
- USB/PCI utilities

mergerfs uses its official EL10 RPM, pinned to a release and SHA-256 checksum.

SnapRAID is intentionally deferred for now. ZFS is deliberately excluded.

### Hardware and firmware

Both images should have good physical-server coverage, including:

- AMD CPU microcode/firmware
- Intel CPU microcode
- AMD GPU firmware
- Intel GPU firmware
- Atheros/Qualcomm Wi-Fi firmware
- Broadcom brcmfmac firmware
- Intel Wi-Fi firmware
- Realtek firmware
- MediaTek/NXP/TI wireless firmware where packaged for Alma 10
- `fwupd` / `fwupd-efi`
- lm_sensors
- Realtek USB Ethernet udev rule adapted from upstream uCore

### Intel and AMD media acceleration

GPU/media support belongs on **both** images, not only HCI.

Intel:

- Alma kernel i915/Intel DRM support
- Intel GPU firmware
- `intel-media-driver` for modern Intel Quick Sync / VA-API
- RPM Fusion EL10 is allowed only as a narrowly scoped source for the Intel media stack and dependencies
- `/dev/dri` passthrough to Podman containers must be validated with a real Jellyfin hardware transcode

AMD:

- Alma kernel amdgpu support
- AMD GPU firmware
- Mesa VA-API userspace support
- `/dev/dri` passthrough must be validated with a real workload

Do not claim media support based only on package installation; real hardware testing is required later.

### Small administration tools

Carry these on both images:

- Micro
- Superfile (`spf`)
- btop
- fastfetch
- tmux
- jq
- rsync
- pv
- PowerTOP
- NUT utilities

UPSide and Superfile are built in isolated builder stages so Node/Go/build toolchains do not remain in the final operating-system image.

## 5. zram / swap policy

Use Alma's `zram-generator`.

Project policy:

- fixed **4 GiB** `/dev/zram0` swap device
- no disk swap partition required
- no additional aggressive memory tuning by default

Configuration:

```ini
[zram0]
zram-size = 4096
```

## 6. HCI-only delta

HCI gets the exact same Home Server feature layer plus virtualization.

HCI-only capability:

- `cockpit-machines` — browser VM management
- `libvirt-client` — `virsh`
- `libvirt-daemon-kvm`
- QEMU/KVM packages
- `virt-install`
- libvirt network/storage dependencies
- `swtpm` and SELinux policy
- OVMF/UEFI VM firmware
- libosinfo / osinfo database
- VirtUI Manager
- noVNC/websockify only as direct VirtUI/VM-console dependencies

VirtUI Manager should preserve the existing Home Server uCore packaging strategy: a local RPM with its compatible Textual dependency isolated under `/usr/libexec/virtui-manager`, without replacing Alma's system Python packages.

Do **not** carry the uBlue `ublue-os-libvirt-workarounds` package; it is Fedora/uCore-specific. Only add an Alma workaround if Alma testing proves a real need.

## 7. Deliberately excluded

Initial scope explicitly excludes:

- Docker/Moby
- Docker Compose / Buildx
- Podman Compose
- ZFS and ZFS akmods
- Cockpit ZFS Manager
- Sanoid/Syncoid ZFS workflow
- NVIDIA drivers/toolkit/images
- uBlue kernel/kmod/signing machinery
- uBlue COPR repositories
- custom/LTS kernel replacement
- Distrobox
- large application services
- site-specific storage/network/UPS/application configuration

A future minimal image is not part of the current design.

## 8. Package/source policy

Preferred source order:

1. AlmaLinux BaseOS/AppStream
2. AlmaLinux CRB where required
3. EPEL 10
4. official upstream EL10 release assets
5. narrowly scoped third-party repositories only when needed

Current external sources:

- Tailscale official RHEL 10 repository
- NetBird official RPM repository
- RPM Fusion EL10, narrowly scoped to Intel media acceleration
- mergerfs official EL10 release RPM
- upstream source builds for UPSide, Superfile and VirtUI Manager

External source-built projects are pinned to known versions/commits. Direct RPM downloads are pinned by SHA-256.

## 9. Supply chain and CI

The repository must build **both images in parallel from day one**.

Required build behavior:

- GitHub Actions matrix for normal + HCI targets
- shared minimal-plus/common build layer
- HCI-only virtualization delta
- resolve important builder/base image references to digests
- `bootc container lint --fatal-warnings`
- build-time package/command validation
- Cosign sign exact published image digests
- verify signatures after publication
- embed repository-specific image trust for future bootc updates
- no credentials or host-specific data in layers
- no build toolchains in final images when a builder stage can avoid them
- clean build-time `/var` state

The normal-image CI must explicitly fail if the KVM/libvirt HCI host stack leaks into it.

Published tags:

- moving `:10`
- immutable `10-YYYYMMDD-<git-sha>`

A GitHub Release is created only after **both** image builds succeed and matching immutable tags exist.

## 10. Development/readiness policy

The project is currently **development / VM-testing only**.

README and releases must warn users not to deploy this to a production or real home server yet.

Maturity path:

```text
builds
  -> boots
  -> VM tested
  -> bare-metal tested
  -> storage tested
  -> GPU/media tested
  -> HCI tested
  -> bootc update/rollback tested
  -> real workloads tested
  -> extended use
  -> recommended
```

## 11. Testing plan

### VM validation — both images

- first boot
- reboot/shutdown
- networking
- SSH
- firewalld
- Cockpit
- Podman
- simple Quadlet boot persistence
- SELinux enforcing
- storage tooling
- 4 GiB zram
- bootc status/update/rollback behavior
- NUT/Tailscale/NetBird remain unconfigured unless administrator enables them

### HCI VM validation

- KVM/QEMU/libvirt packages present
- Cockpit Machines
- `virsh`
- `virt-install`
- VirtUI Manager
- VM storage pool
- libvirt network
- bridged networking
- UEFI guest
- virtual TPM
- graceful VM shutdown

### Bare-metal validation

After VM testing:

- UEFI install/boot
- Ethernet/Wi-Fi firmware
- USB/NVMe/SATA
- SMART/sensors/fwupd
- CPU microcode
- Intel/AMD GPU firmware
- `/dev/dri`
- Btrfs data volumes
- mergerfs
- bootc update/rollback

### Real workload validation

Later deploy actual Quadlets, including Jellyfin, and verify permissions, SELinux, bind mounts, networking and real Intel/AMD hardware transcoding.

## 12. Installer direction

Installer/builder work belongs under the Home Server Project as a separate reusable repository/template, not coupled to Alma Black Box.

Expected future workflow:

1. choose Home Server Alma or HCI
2. build installer ISO
3. write USB
4. disconnect disks that must not be touched
5. leave only target OS drive connected where practical
6. install
7. boot and configure local storage/network
8. deploy Quadlets

## 13. Production trial safety

Do not replace the current uCore server immediately.

Preferred future trial:

1. keep the known-good uCore OS SSD untouched
2. install Home Server Alma HCI to a second SSD
3. boot Alma from that SSD
4. leave media/family/VM data disks intact
5. restore machine-specific host config and Quadlets
6. validate workloads over time
7. fall back by booting the original uCore SSD

Clonezilla remains an additional backup option.

## 14. Reference projects

- Universal Blue uCore: https://github.com/ublue-os/ucore
- Home Server uCore: https://github.com/home-server-project/home-server-ucore
- Alma Black Box reference: https://github.com/highwaytoit/alma-black-box (`testing` branch was used during design)
- AlmaLinux bootc images: https://github.com/AlmaLinux/bootc-images

Alma Black Box is a reference implementation only. Home Server Alma does not derive from it.

## 15. Short definition

**Home Server Alma** is an AlmaLinux 10 minimal-plus bootc image for self-hosted servers with the full agreed Home Server feature set: Podman Quadlets, Cockpit, storage/NAS tools, broad hardware support, Intel/AMD media acceleration, UPS integration, VPN tooling and practical terminal administration tools.

**Home Server Alma HCI** is that exact same image plus KVM/QEMU/libvirt, Cockpit Machines, `virsh`, `virt-install`, VirtUI Manager and direct virtualization dependencies.

The objective is a **boring, understandable and recoverable home-server host** on a slower-moving enterprise-Linux base, with applications deployed reproducibly as Podman Quadlets.
