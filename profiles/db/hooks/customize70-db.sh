#!/bin/sh
# Profilo db: niente identità nell'immagine
set -eu
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
ROOT="$1"
# Cluster creato dal pacchetto in build (system identifier uguale su ogni macchina)
if [ -d "${ROOT}/var/lib/postgresql/17/main" ]; then
  chroot "${ROOT}" pg_dropcluster 17 main
fi
# Certificato e chiave "snakeoil" generati da ssl-cert all'installazione
rm -f "${ROOT}/etc/ssl/private/ssl-cert-snakeoil.key" "${ROOT}/etc/ssl/certs/ssl-cert-snakeoil.pem"

# Variante immutabile: /etc è in sola lettura e pg_createcluster scrive in /etc/postgresql
if [ "${GOLDEN_VARIANT:-mutable}" = immutable ]; then
  rm -rf "${ROOT}/etc/postgresql"
  chroot "${ROOT}" install -d -o postgres -g postgres -m 0755 /var/lib/postgresql/etc
  ln -s /var/lib/postgresql/etc "${ROOT}/etc/postgresql"
fi
