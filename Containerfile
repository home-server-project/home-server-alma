ARG ALMA_REPOS_IMAGE=quay.io/almalinuxorg/10-base:10
ARG BOOTC_IMAGECTL_IMAGE=quay.io/centos-bootc/centos-bootc:stream10
ARG ALMA_BUILDER_IMAGE=quay.io/almalinuxorg/10-kitten-base:10-kitten
ARG FEDORA_BUILDER_IMAGE=registry.fedoraproject.org/fedora:44
ARG HOME_SERVER_ALMA_REPOSITORY=ghcr.io/home-server-project/home-server-alma
ARG HOME_SERVER_ALMA_HCI_REPOSITORY=ghcr.io/home-server-project/home-server-alma-hci

# -----------------------------------------------------------------------------
# AlmaLinux 10 minimal-plus bootc rootfs
# -----------------------------------------------------------------------------
FROM ${ALMA_REPOS_IMAGE} AS repos
FROM ${BOOTC_IMAGECTL_IMAGE} AS imagectl
FROM ${ALMA_BUILDER_IMAGE} AS rootfs-builder

RUN dnf install -y podman bootc ostree rpm-ostree \
    && dnf clean all

COPY --from=imagectl /usr/share/doc/bootc-base-imagectl/ /usr/share/doc/bootc-base-imagectl/
COPY --from=imagectl /usr/libexec/bootc-base-imagectl /usr/libexec/bootc-base-imagectl
RUN chmod +x /usr/libexec/bootc-base-imagectl

RUN rm -rf /etc/yum.repos.d/*
COPY --from=repos /etc/yum.repos.d/*.repo /etc/yum.repos.d/
COPY --from=repos /etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux-10 /etc/pki/rpm-gpg/

COPY build_files/almalinux-10-minimal-plus.yaml \
    /usr/share/doc/bootc-base-imagectl/manifests/almalinux-10-minimal-plus.yaml

RUN /usr/libexec/bootc-base-imagectl build-rootfs \
    --reinject \
    --manifest=almalinux-10-minimal-plus \
    /target-rootfs

FROM scratch AS alma-minimal-plus
COPY --from=rootfs-builder /target-rootfs/ /
LABEL containers.bootc=1 \
      ostree.bootable=1 \
      org.opencontainers.image.vendor="Home Server Project" \
      io.home-server-project.base-profile="almalinux-10-minimal-plus" \
      io.home-server-project.status="development"
RUN bootc container lint --fatal-warnings
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]

# -----------------------------------------------------------------------------
# Build context exposed to bind mounts
# -----------------------------------------------------------------------------
FROM scratch AS ctx
COPY build_files /build_files
COPY system_files /system_files
COPY quadlets /quadlets
COPY docs /docs
COPY cosign.pub /cosign.pub

# -----------------------------------------------------------------------------
# UPSide builder
# -----------------------------------------------------------------------------
FROM ${FEDORA_BUILDER_IMAGE} AS upside-builder
COPY build_files/software.env /tmp/software.env
RUN dnf install -y git make nodejs npm tar \
    && . /tmp/software.env \
    && git clone https://github.com/deviationist/cockpit-upside.git /src/upside \
    && cd /src/upside \
    && test "$(git rev-parse "refs/tags/${UPSIDE_VERSION}^{commit}")" = "${UPSIDE_COMMIT}" \
    && git checkout --detach "${UPSIDE_COMMIT}" \
    && make \
    && mkdir -p /out/usr/share/cockpit/upside \
    && cp -a dist/. /out/usr/share/cockpit/upside/ \
    && test -f /out/usr/share/cockpit/upside/manifest.json \
    && dnf clean all

# -----------------------------------------------------------------------------
# Superfile builder
# -----------------------------------------------------------------------------
FROM ${FEDORA_BUILDER_IMAGE} AS superfile-builder
COPY build_files/software.env /tmp/software.env
RUN dnf install -y git golang \
    && . /tmp/software.env \
    && git clone https://github.com/yorukot/superfile.git /src/superfile \
    && cd /src/superfile \
    && test "$(git rev-parse "refs/tags/v${SUPERFILE_VERSION}^{commit}")" = "${SUPERFILE_COMMIT}" \
    && git checkout --detach "${SUPERFILE_COMMIT}" \
    && bash ./build.sh \
    && install -Dm0755 ./bin/spf /out/usr/bin/spf \
    && install -Dm0644 ./LICENSE /out/usr/share/licenses/superfile/LICENSE \
    && dnf clean all

# -----------------------------------------------------------------------------
# VirtUI Manager RPM builder - output is consumed only by HCI
# -----------------------------------------------------------------------------
FROM ${ALMA_REPOS_IMAGE} AS virtui-manager-builder
COPY build_files/software.env /tmp/software.env
COPY build_files/virtui-manager.spec /tmp/virtui-manager.spec

RUN dnf install -y git python3 python3-pip python3-setuptools python3-wheel rpm-build tar gzip \
    && . /tmp/software.env \
    && git clone https://github.com/aginies/virtui-manager.git /src/virtui-manager \
    && cd /src/virtui-manager \
    && test "$(git rev-parse "refs/tags/v${VIRTUI_MANAGER_VERSION}^{commit}")" = "${VIRTUI_MANAGER_COMMIT}" \
    && git checkout --detach "${VIRTUI_MANAGER_COMMIT}" \
    && mkdir -p /tmp/payload/usr/libexec/virtui-manager/python \
                 /tmp/payload/usr/share/licenses/virtui-manager \
    && python3 -m pip install \
        --no-deps --no-build-isolation --no-compile \
        --target /tmp/payload/usr/libexec/virtui-manager/python . \
    && python3 -m pip install \
        --no-compile \
        --target /tmp/payload/usr/libexec/virtui-manager/python \
        "textual==${VIRTUI_TEXTUAL_VERSION}" \
    && install -Dm0644 LICENSE /tmp/payload/usr/share/licenses/virtui-manager/LICENSE \
    && mkdir -p /root/rpmbuild/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS} \
    && tar -C /tmp/payload -czf /root/rpmbuild/SOURCES/virtui-manager-payload.tar.gz . \
    && cp /tmp/virtui-manager.spec /root/rpmbuild/SPECS/virtui-manager.spec \
    && rpmbuild -bb \
        --define "virtui_version ${VIRTUI_MANAGER_VERSION}" \
        /root/rpmbuild/SPECS/virtui-manager.spec \
    && mkdir -p /out \
    && cp /root/rpmbuild/RPMS/noarch/virtui-manager-*.noarch.rpm /out/ \
    && dnf clean all

# -----------------------------------------------------------------------------
# Shared full Home Server feature layer
# -----------------------------------------------------------------------------
FROM alma-minimal-plus AS home-server-common

COPY --from=upside-builder /out/usr/share/cockpit/upside/ /usr/share/cockpit/upside/
COPY --from=superfile-builder /out/usr/bin/spf /usr/bin/spf
COPY --from=superfile-builder /out/usr/share/licenses/superfile/ /usr/share/licenses/superfile/

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/run \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build_files/build-common.sh

# -----------------------------------------------------------------------------
# Standard Home Server Alma image
# -----------------------------------------------------------------------------
FROM home-server-common AS home-server-alma
ARG HOME_SERVER_ALMA_REPOSITORY

LABEL org.opencontainers.image.title="Home Server Alma" \
      org.opencontainers.image.description="AlmaLinux 10 minimal-plus bootc home-server image" \
      org.opencontainers.image.source="https://github.com/home-server-project/home-server-alma" \
      io.home-server-project.variant="home-server-alma"

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    IMAGE_REPOSITORY="${HOME_SERVER_ALMA_REPOSITORY}" \
    IMAGE_PRETTY_NAME="Home Server Alma 10" \
    IMAGE_VARIANT="Home Server Alma" \
    /ctx/build_files/finalize-image.sh

RUN bootc container lint --fatal-warnings

# -----------------------------------------------------------------------------
# HCI: exact same common layer plus virtualization
# -----------------------------------------------------------------------------
FROM home-server-common AS home-server-alma-hci
ARG HOME_SERVER_ALMA_HCI_REPOSITORY

LABEL org.opencontainers.image.title="Home Server Alma HCI" \
      org.opencontainers.image.description="Home Server Alma plus KVM/QEMU/libvirt virtualization" \
      org.opencontainers.image.source="https://github.com/home-server-project/home-server-alma" \
      io.home-server-project.variant="home-server-alma-hci"

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=virtui-manager-builder,source=/out,target=/virtui-manager-rpm \
    --mount=type=tmpfs,dst=/run \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build_files/build-hci.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    IMAGE_REPOSITORY="${HOME_SERVER_ALMA_HCI_REPOSITORY}" \
    IMAGE_PRETTY_NAME="Home Server Alma HCI 10" \
    IMAGE_VARIANT="Home Server Alma HCI" \
    /ctx/build_files/finalize-image.sh

RUN bootc container lint --fatal-warnings
