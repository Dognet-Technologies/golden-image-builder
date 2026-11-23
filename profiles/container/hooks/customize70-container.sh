#!/bin/sh
# Profilo container: utente dedicato non privilegiato con i suoi intervalli di
# subuid/subgid e quadlet (il lingering è in /usr/lib/tmpfiles.d/golden-podman.conf)
set -eu
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
ROOT="$1"
chroot "${ROOT}" useradd --system --create-home --home-dir /var/lib/podman \
  --shell /usr/sbin/nologin --comment "Container rootless" podman
chroot "${ROOT}" usermod --add-subuids 524288-589823 --add-subgids 524288-589823 podman
uid="$(chroot "${ROOT}" id -u podman)"
install -d -m 0755 "${ROOT}/etc/containers/systemd/users/${uid}"
install -m 0644 "${ROOT}/usr/share/golden/quadlet/hello.container" \
  "${ROOT}/etc/containers/systemd/users/${uid}/hello.container"
