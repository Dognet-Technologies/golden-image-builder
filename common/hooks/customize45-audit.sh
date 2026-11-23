#!/bin/sh
# Genera /etc/audit/audit.rules da rules.d in build: all'avvio augenrules lo
# confronta e lo carica, senza bisogno di scrivere in /etc (variante immutabile)
set -eu
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
ROOT="$1"
chroot "${ROOT}" augenrules
