#!/usr/bin/env bash
# Chiave OpenPGP che firma i manifest SHA256SUMS degli aggiornamenti (articolo 5).
# La parte pubblica (update-pubring.gpg) entra nell'immagine immutabile come
# /etc/systemd/import-pubring.gpg; la privata resta nella directory delle chiavi.
#   tools/update-key.sh <directory-chiavi>
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/env.sh
KEYS="${1:?directory delle chiavi mancante}"
[ -f out/tools.tar ] || die "manca out/tools.tar: esegui ./tools.sh"
mkdir -p "${KEYS}"; chmod 700 "${KEYS}"
KEYS="$(realpath "${KEYS}")"
case "${KEYS}/" in "${PWD}/"*) die "le chiavi non vanno dentro il repository" ;; esac
[ -e "${KEYS}/update-pubring.gpg" ] && die "chiave di aggiornamento già presente in ${KEYS}"

WORK="$(mktemp -d "${TMPDIR:-/var/tmp}/golden-keys.XXXXXX")"
trap 'as_root rm -rf "${WORK}"' EXIT
as_root lib/chroot.sh "${PWD}" "${WORK}" "${KEYS}:/keys" -- /bin/bash -euo pipefail -c '
  export GNUPGHOME=/keys/gnupg
  install -d -m 0700 "${GNUPGHOME}"
  gpg --batch --quiet --passphrase "" --quick-gen-key "Golden Image Updates" ed25519 sign 3y
  gpg --batch --export > /keys/update-pubring.gpg
  chmod 644 /keys/update-pubring.gpg
  gpg --batch --list-keys --keyid-format long
'
