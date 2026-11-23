#!/bin/sh
# Kernel e bootloader fermi: cambiano solo con una nuova immagine (UKI firmata)
set -eu
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
ROOT="$1"
KERNELS="$(chroot "${ROOT}" dpkg-query -W -f '${db:Status-Abbrev} ${Package}\n' 'linux-image-*' | awk '$1 == "ii" {print $2}')"
# shellcheck disable=SC2086
chroot "${ROOT}" apt-mark hold ${KERNELS} systemd-boot-efi dracut dracut-core
