#!/bin/sh
# Rigenera l'initrd con la configurazione dell'overlay (/etc/dracut.conf.d):
# quello creato all'installazione del kernel usa la configurazione di default
set -eu
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
ROOT="$1"
for vmlinuz in "${ROOT}"/boot/vmlinuz-*; do
  kver="${vmlinuz##*/vmlinuz-}"
  chroot "${ROOT}" dracut --force --kver "${kver}" "/boot/initrd.img-${kver}"
done
