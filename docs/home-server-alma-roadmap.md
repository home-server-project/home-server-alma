# Home Server Alma — Architecture and Feature Roadmap

**Status:** Implementation in development  
**Date:** 2026-09-04  
**Repository:** https://github.com/home-server-project/home-server-alma  
**Images:** `home-server-alma` and `home-server-alma-hci`

> This is the durable implementation reference for the project. Scope changes continue to follow the normal proposal -> greenlight -> execute workflow.

## 1. Goal

Build a boring, understandable AlmaLinux 10 bootc home-server operating system from AlmaLinux's **minimal-plus** content tier.

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

The HCI image is exactly **Home Server Alma + virtualization**. It is not a separate fuller server edition.

Everything useful to a normal home server belongs on **both** images. Only virtualization and tools that directly manage virtual machines belong only on HCI.

## 2. Foundation

Use AlmaLinux 10 **minimal-plus**, not Alma's broad standard bootc image.

The custom manifest follows the proven Alma minimal-plus composition pattern and retains:

- `minimal-plus/manifest.yaml`
- `standard/autoupdates.yaml`
- `standard/system-configuration.yaml`
- `standard/persistent-journal.yaml`
- `standard/generic-growfs.yaml`

Initial boot/root filesystem: **XFS**.

Btrfs is normal supported data-filesystem tooling through `btrfs-progs`.

Initial CPU architecture: normal AlmaLinux 10 **x86-64-v3**. x86-64-v2 is a separate future investigation.

## 3. Container model

Applications are deployed through **Podman + systemd Quadlets**.

Do not include by default:

- Docker/Moby
- docker-compose
- docker-buildx
- podman-compose

Large replaceable services such as Jellyfin, Vaultwarden, databases, media automation, monitoring stacks and reverse proxies belong in Quadlets, not in the OS image.

No rpm-ostree host-layering workflow is part of this project. Host changes belong in rebuilt bootc images.

## 4. Features on both images

### Core host

- bootc
- NetworkManager / TUI / Wi-Fi support
- firewalld
- OpenSSH
- Podman / Quadlets
- SELinux tooling
- persistent journal
- generic filesystem growth
- image signing and image trust

### Cockpit

Native host bridge/pages:

- cockpit-system
- cockpit-files
- cockpit-podman
- cockpit-storaged
- UPSide

The web-facing Cockpit service is supplied as a Podman Quadlet using `quay.io/cockpit/ws:latest`.

### UPS and power

- NUT
- NUT client
- UPSide
- PowerTOP

NUT is included but never preconfigured. UPS identity, credentials and shutdown policy remain local configuration. PowerTOP is diagnostic only; no automatic `powertop --auto-tune` policy is baked in.

### Networking and remote access

- Tailscale
- NetBird
- WireGuard tools
- ethtool
- tcpdump
- DNS tools
- traceroute
- ncat/netcat
- iperf3

Tailscale and NetBird are installed but never enrolled by the generic image.

### Storage/NAS

- XFS root support
- btrfs-progs
- mergerfs
- NFS tools
- Samba / usershares
- rclone
- duperemove
- SMART tools
- NVMe CLI
- hdparm
- USB/PCI utilities

**mergerfs is release-critical.** The build follows the latest stable upstream EL10 x86_64 RPM by default, verifies the SHA-256 digest published for that release asset, and then runs a real FUSE mount/read/write/unmount health test before publication.

SnapRAID remains deferred. ZFS is deliberately excluded.

### Hardware and firmware

Both images target good physical-server coverage:

- AMD CPU microcode/firmware
- Intel CPU microcode
- AMD GPU firmware
- Intel GPU firmware
- Atheros/Qualcomm Wi-Fi firmware
- Broadcom brcmfmac firmware
- Intel Wi-Fi firmware
- Realtek firmware
- MediaTek/NXP/TI wireless firmware where packaged for Alma 10
- fwupd / fwupd-efi
- lm_sensors
- Realtek USB Ethernet udev rule adapted from upstream uCore

### Intel and AMD media acceleration

GPU/media support follows the project's **container-first** application model.

Host responsibilities on both images:

- Alma kernel Intel DRM/i915 and AMD amdgpu support
- Intel and AMD GPU firmware
- `/dev/dri` device availability on supported hardware
- `intel-compute-runtime` for Intel compute/OpenCL support, following the uCore reference model

The host does **not** install a dedicated VA-API media userspace stack such as `intel-media-driver`, host `libva`, or Mesa VA-API packages solely for container workloads. Media applications such as Jellyfin, Plex or HandBrake are expected to run as containers and carry the compatible VA-API/Quick Sync or Mesa userspace libraries they require while receiving the relevant `/dev/dri` devices.

CI verifies the host package/firmware contract. Real Intel/AMD hardware acceleration claims require bare-metal testing with actual application containers and `/dev/dri` passthrough.

### Administration tools

Intended on both images:

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

UPSide and Superfile use isolated builders so Node/Go build toolchains do not remain in the OS image.

## 5. zram / swap policy

Use Alma's `zram-generator` with a fixed **4 GiB** `/dev/zram0` swap device.

No disk swap partition is required by the project.

```ini
[zram0]
zram-size = 4096
```

## 6. HCI-only delta

HCI receives the exact same Home Server layer plus:

- cockpit-machines
- libvirt-client (`virsh`)
- libvirt-daemon-kvm
- QEMU/KVM
- virt-install
- required libvirt network/storage dependencies
- swtpm + policy
- OVMF/UEFI VM firmware
- libosinfo / osinfo-db
- VirtUI Manager
- direct noVNC/websockify/console dependencies where required

VirtUI Manager is packaged as a local RPM with its Python/Textual runtime isolated under `/usr/libexec/virtui-manager`; it must not replace Alma system Python packages.

The builder follows the current stable VirtUI tag and the Textual requirement declared by that VirtUI release. Build-only Setuptools is upgraded to a compatible `>=77` so current SPDX metadata can be parsed; that builder tool does not enter the final image.

Do not carry uBlue's Fedora-specific `ublue-os-libvirt-workarounds` package unless Alma testing proves an equivalent workaround is genuinely required. Alma's current libvirt packaging does require the equivalent sysusers declarations for `libvirt` and `libvirtdbus`; Home Server Alma HCI carries those declarations directly rather than importing the uBlue package.

## 7. Deliberately excluded

- Docker/Moby and Docker Compose/Buildx
- Podman Compose
- ZFS / ZFS akmods / Cockpit ZFS Manager
- Sanoid/Syncoid ZFS workflow
- NVIDIA drivers/toolkit/images
- RPM Fusion
- host VA-API media userspace packages installed only for container workloads
- uBlue kernel/kmod/signing machinery
- uBlue COPR repositories
- custom/LTS kernel replacement
- Distrobox
- large application services
- site-specific storage/network/UPS/application configuration

A future minimal image is not part of the current project.

## 8. Package and update policy

Preferred source order:

1. AlmaLinux BaseOS/AppStream
2. AlmaLinux CRB where required
3. EPEL 10
4. official upstream EL10 release assets
5. narrowly scoped third-party repositories only when needed

Current external sources include Tailscale, NetBird, mergerfs upstream releases, and upstream source builds for UPSide, Superfile and VirtUI Manager. RPM Fusion is not part of the image dependency chain.

### Latest by default

The normal maintenance model is:

```text
latest stable upstream
        -> build
        -> health validation
        -> publish if critical health passes
```

Alma/EPEL packages update naturally with each rebuild. mergerfs, UPSide, Superfile and VirtUI Manager also resolve current stable upstream releases on each rebuild.

Repository version pins are **not** routine maintenance. `software.env` contains empty emergency override variables. A specific version is pinned only after a demonstrated upstream regression and removed when the regression is resolved.

## 9. Health contract and release gates

Detailed policy: [`health-and-update-policy.md`](health-and-update-policy.md).

### Critical on both images

A failure blocks publication:

- bootc lint
- Podman / Quadlet integration
- NetworkManager / firewalld / SSH tooling
- SELinux and image-trust integrity
- 4 GiB zram configuration
- Btrfs userspace smoke test
- NFS/Samba core tooling
- Intel compute runtime and Intel/AMD GPU firmware host contract
- **mergerfs real FUSE mount/read/write/unmount test**
- required Cockpit host components

The host media contract deliberately stops at kernel/device/firmware capability. Container-specific VA-API or Quick Sync userspace is validated later with real workloads rather than being required in the host image.

The mergerfs check is intentionally release-critical because storage-pool failure can remove application access to media/data even when the OS itself still boots.

### Critical HCI-only

- KVM/QEMU/libvirt packages and binaries
- cockpit-machines
- virsh / virt-install
- swtpm / VM firmware
- VirtUI Manager imports and entry points

### Optional/degraded

Failures in non-runtime tools such as UPSide, Superfile, Micro, btop, PowerTOP, NUT UI/tooling, Tailscale/NetBird and similar helpers are clearly reported as degraded but do not automatically block an otherwise healthy OS/security rebuild.

The normal image must explicitly fail if the KVM/libvirt HCI host stack leaks into it.

## 10. Supply chain and CI

The repository builds **both images in parallel**.

Required behavior:

- resolve current external software once per workflow so both images use the same dependency snapshot
- resolve base/builder container references to digests
- shared minimal-plus/common feature layer
- HCI-only virtualization delta
- functional critical health checks before push
- optional health summary after critical checks
- Cosign sign exact published image digests
- verify signatures after publication
- repository-specific image trust for bootc updates
- no credentials or site-specific data in layers
- no build toolchains in final images when isolated builders can avoid them

Published tags:

- moving `:10`
- immutable `10-YYYYMMDD-<git-sha>`

A GitHub Release is created only after **both** images succeed.

## 11. Development/readiness policy

Current status: **development / VM-testing only**.

Do not deploy on a production or real home server yet.

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

## 12. Testing plan

### CI — both images

- build and bootc lint
- critical health contract
- real mergerfs FUSE smoke test
- Btrfs userspace smoke test
- optional/degraded report
- base/HCI separation check

### VM validation — both images

- first boot / reboot / shutdown
- networking, SSH and firewalld
- Cockpit
- Podman and a persistent Quadlet
- SELinux enforcing
- storage tooling
- 4 GiB zram
- bootc update/rollback
- NUT/Tailscale/NetBird remain unconfigured until explicitly enabled

### HCI VM validation

- Cockpit Machines
- virsh / virt-install / VirtUI Manager
- create and boot a VM
- storage pool and networking
- bridge networking
- UEFI guest
- virtual TPM
- graceful VM shutdown

### Bare-metal validation

- UEFI install/boot
- Ethernet/Wi-Fi firmware
- USB/NVMe/SATA
- SMART/sensors/fwupd
- CPU microcode
- Intel/AMD GPU firmware and `/dev/dri`
- Btrfs data volumes
- mergerfs
- bootc update/rollback

### Real workloads

Deploy actual Quadlets including Jellyfin and validate permissions, SELinux, bind mounts, networking, mergerfs-backed media paths, `/dev/dri` device passthrough, and real Intel/AMD hardware transcoding using the container-provided media userspace stack.

## 13. Installer direction

Installer/builder work belongs under the Home Server Project as a separate reusable repository/template, not coupled to Alma Black Box.

Expected later workflow:

1. choose Home Server Alma or HCI
2. build installer ISO
3. write USB
4. disconnect disks that must not be touched
5. install to the target OS drive
6. boot and configure local storage/network
7. deploy Quadlets

## 14. Production trial safety

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

## 15. References

- Universal Blue uCore: https://github.com/ublue-os/ucore
- Home Server uCore: https://github.com/home-server-project/home-server-ucore
- Alma Black Box reference: https://github.com/highwaytoit/alma-black-box
- AlmaLinux bootc images: https://github.com/AlmaLinux/bootc-images

Alma Black Box is a reference implementation only. Home Server Alma does not derive from it.

## 16. Short definition

**Home Server Alma** is an AlmaLinux 10 minimal-plus bootc image for self-hosted servers with Podman Quadlets, Cockpit, storage/NAS tooling, broad hardware support, container-first Intel/AMD media acceleration, UPS integration, VPN tooling and practical terminal administration tools.

**Home Server Alma HCI** is that exact same image plus KVM/QEMU/libvirt, Cockpit Machines, virsh, virt-install, VirtUI Manager and direct virtualization dependencies.

The objective is a **boring, understandable and recoverable home-server host** on a slower-moving enterprise-Linux base, with applications deployed reproducibly as Podman Quadlets.
