#!/bin/sh
# Punti di montaggio che devono esistere nell'immagine (git non versiona directory vuote)
set -eu
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
ROOT="$1"
install -d -m 0755 "${ROOT}/efi"          # ESP, vedi /etc/fstab
