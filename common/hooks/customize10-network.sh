#!/bin/sh
# Rete: systemd-networkd + systemd-resolved, resolv.conf verso lo stub locale
set -eu
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
ROOT="$1"
ln -sf ../run/systemd/resolve/stub-resolv.conf "${ROOT}/etc/resolv.conf"
chroot "${ROOT}" systemctl enable systemd-networkd.service systemd-resolved.service systemd-timesyncd.service
