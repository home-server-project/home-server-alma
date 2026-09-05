ARG ALMA_REPOS_IMAGE=quay.io/almalinuxorg/10-base:10
ARG BOOTC_IMAGECTL_IMAGE=quay.io/centos-bootc/centos-bootc:stream10
ARG ALMA_BUILDER_IMAGE=quay.io/almalinuxorg/10-kitten-base:10-kitten
ARG FEDORA_BUILDER_IMAGE=registry.fedoraproject.org/fedora:44
ARG HOME_SERVER_ALMA_REPOSITORY=ghcr.io/home-server-project/home-server-alma
ARG HOME_SERVER_ALMA_HCI_REPOSITORY=ghcr.io/home-server-project/home-server-alma-hci

# -----------------------------------------------------------------------------
# Optional shared-tool builders first, so the bootc rootfs is composed immediately
# before the shared Home Server layer consumes it.
# -----------------------------------------------------------------------------
FROM ${FEDORA_BUILDER_IMAGE} AS upside-builder
ARG UPSIDE_TAG
RUN mkdir -p /out/usr/share/home-server-alma/build-health \
    && if [ -n "${UPSIDE_TAG}" ] \
       && dnf install -y git make nodejs npm tar \
       && git clone --depth 1 --branch "${UPSIDE_TAG}" https://github.com/deviationist/cockpit-upside.git /src/upside \
       && cd /src/upside \
       && make \
       && mkdir -p /out/usr/share/cockpit/upside \
       && cp -a dist/. /out/usr/share/cockpit/upside/ \
       && test -f /out/usr/share/cockpit/upside/manifest.json; then \
           printf '%s\n' "${UPSIDE_TAG}" > /out/usr/share/home-server-alma/build-health/upside.version; \
       else \
           echo 'UPSide failed to resolve or build; image is degraded but still operational.' \
               > /out/usr/share/home-server-alma/build-health/upside.failed; \
       fi \
    && dnf clean all

FROM ${FEDORA_BUILDER_IMAGE} AS superfile-builder
ARG SUPERFILE_TAG
RUN mkdir -p /out/usr/share/home-server-alma/build-health \
    && if [ -n "${SUPERFILE_TAG}" ] \
       && dnf install -y git golang \
       && git clone --depth 1 --branch "${SUPERFILE_TAG}" https://github.com/yorukot/superfile.git /src/superfile \
       && cd /src/superfile \
       && bash ./build.sh \
       && install -Dm0755 ./bin/spf /out/usr/bin/spf \
       && install -Dm0644 ./LICENSE /out/usr/share/licenses/superfile/LICENSE; then \
           printf '%s\n' "${SUPERFILE_TAG}" > /out/usr/share/home-server-alma/build-health/superfile.version; \
       else \
           echo 'Superfile failed to resolve or build; image is degraded but still operational.' \
               > /out/usr/share/home-server-alma/build-health/superfile.failed; \
       fi \
    && dnf clean all

# VirtUI Manager is HCI-critical, so this builder must fail if it cannot be built.
FROM ${ALMA_REPOS_IMAGE} AS virtui-manager-builder
ARG VIRTUI_MANAGER_TAG
COPY build_files/virtui-manager.spec /tmp/virtui-manager.spec
RUN test -n "${VIRTUI_MANAGER_TAG}" \
    && dnf install -y git python3 python3-pip python3-setuptools python3-wheel rpm-build tar gzip \
    && python3 -m pip install --upgrade 'setuptools>=77' wheel \
    && git clone --depth 1 --branch "${VIRTUI_MANAGER_TAG}" https://github.com/aginies/virtui-manager.git /src/virtui-manager \
    && cd /src/virtui-manager \
    && VIRTUI_VERSION="${VIRTUI_MANAGER_TAG#v}" \
    && mkdir -p /tmp/payload/usr/libexec/virtui-manager/python \
                 /tmp/payload/usr/share/licenses/virtui-manager \
    && python3 -m pip install \
        --no-deps --no-build-isolation --no-compile \
        --target /tmp/payload/usr/libexec/virtui-manager/python . \
    && TEXTUAL_SPEC="$(python3 -c 'import tomllib; d=tomllib.load(open("pyproject.toml", "rb")); print(next(x for x in d["project"]["dependencies"] if x.lower().startswith("textual")))')" \
    && test -n "${TEXTUAL_SPEC}" \
    && python3 -m pip install \
        --no-compile \
        --target /tmp/payload/usr/libexec/virtui-manager/python \
        "${TEXTUAL_SPEC}" \
    && install -Dm0644 LICENSE /tmp/payload/usr/share/licenses/virtui-manager/LICENSE \
    && mkdir -p /root/rpmbuild/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS} \
    && tar -C /tmp/payload -czf /root/rpmbuild/SOURCES/virtui-manager-payload.tar.gz . \
    && cp /tmp/virtui-manager.spec /root/rpmbuild/SPECS/virtui-manager.spec \
    && rpmbuild -bb \
        --define "virtui_version ${VIRTUI_VERSION}" \
        /root/rpmbuild/SPECS/virtui-manager.spec \
    && mkdir -p /out \
    && cp /root/rpmbuild/RPMS/noarch/virtui-manager-*.noarch.rpm /out/ \
    && dnf clean all

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
# Shared full Home Server feature layer
# -----------------------------------------------------------------------------
FROM scratch AS home-server-common
ARG MERGERFS_URL
ARG MERGERFS_SHA256
COPY --from=rootfs-builder /target-rootfs/ /
COPY --from=upside-builder /out/ /
COPY --from=superfile-builder /out/ /

LABEL containers.bootc=1 \
      ostree.bootable=1 \
      org.opencontainers.image.vendor="Home Server Project" \
      io.home-server-project.base-profile="almalinux-10-minimal-plus" \
      io.home-server-project.status="development"

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/run \
    --mount=type=tmpfs,dst=/tmp \
    MERGERFS_URL="${MERGERFS_URL}" \
    MERGERFS_SHA256="${MERGERFS_SHA256}" \
    /ctx/build_files/build-common.sh

# This shared stage still contains transient package-manager/runtime state that is
# cleaned by finalize-image.sh. Check structural bootc validity here, and reserve
# fatal warnings for the completed variants after finalization.
RUN bootc container lint
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]

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
