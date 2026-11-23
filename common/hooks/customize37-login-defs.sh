#!/bin/sh
# login.defs di trixie non definisce UMASK: 027 per i file creati da useradd e pam_umask
set -eu
ROOT="$1"
grep -qE '^UMASK' "${ROOT}/etc/login.defs" || printf '\n# golden: niente permessi per "altri" sui file nuovi\nUMASK\t\t027\n' >> "${ROOT}/etc/login.defs"
