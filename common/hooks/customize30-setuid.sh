#!/bin/sh
# Toglie i bit setuid/setgid che su un server senza utenti interattivi non servono.
# dpkg-statoverride: la modifica sopravvive agli aggiornamenti dei pacchetti.
set -eu
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
ROOT="$1"
for f in /usr/bin/chfn /usr/bin/chsh /usr/bin/gpasswd /usr/bin/newgrp /usr/bin/passwd \
         /usr/bin/su /usr/bin/mount /usr/bin/umount /usr/lib/openssh/ssh-keysign \
         /usr/bin/chage /usr/bin/expiry; do
  [ -e "${ROOT}${f}" ] || continue
  chroot "${ROOT}" dpkg-statoverride --update --add root root 0755 "${f}"
done
