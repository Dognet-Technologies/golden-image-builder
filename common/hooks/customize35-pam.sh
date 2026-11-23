#!/bin/sh
# PAM: a ogni login pam_motd esegue come root gli script di /etc/update-motd.d
# e pam_mail controlla una casella di posta che non esiste. Li disattiviamo.
set -eu
ROOT="$1"
for f in sshd login; do
  sed -i -E 's/^(session[[:space:]]+optional[[:space:]]+pam_(motd|mail)\.so.*)$/# golden: \1/' \
    "${ROOT}/etc/pam.d/${f}"
done
