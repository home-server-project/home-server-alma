# Third-party notices

Home Server Alma is licensed under Apache-2.0. Software installed into the image retains its own
upstream license.

## Universal Blue uCore

The Realtek USB Ethernet udev rule in
`system_files/etc/udev/rules.d/50-usb-realtek-net.rules` is adapted from the Universal Blue uCore
project:

https://github.com/ublue-os/ucore

uCore is distributed under Apache-2.0. The rule has been carried over because it is useful generic
home-server hardware enablement; comments were adjusted for this project.

## UPSide

https://github.com/deviationist/cockpit-upside

Built in an isolated builder stage. Build dependencies do not remain in the final image.

## Superfile

https://github.com/yorukot/superfile

Built in an isolated builder stage. The upstream license is copied into the image.

## VirtUI Manager

https://github.com/aginies/virtui-manager

Home Server Alma HCI packages VirtUI Manager locally while preserving its upstream GPL-3.0-or-later
license. Its private Python dependency directory avoids replacing AlmaLinux system Python packages.

## mergerfs

https://github.com/trapexit/mergerfs

The image installs the upstream EL10 RPM using a pinned release and SHA-256 checksum.
