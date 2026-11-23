#!/bin/sh
# Servizi: firewall attivo dal boot, directory per le regole dei profili
set -eu
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
ROOT="$1"
install -d -m 0755 "${ROOT}/etc/nftables.d"
chroot "${ROOT}" systemctl enable nftables.service auditd.service
