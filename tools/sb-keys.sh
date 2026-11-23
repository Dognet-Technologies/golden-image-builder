#!/usr/bin/env bash
# Genera le chiavi Secure Boot (PK, KEK, db) e i file .auth per l'enrollment.
# Le chiavi vanno FUORI dal repository e, in produzione, in un HSM o almeno
# su una macchina dedicata: chi ha db.key può firmare kernel avviabili.
#   tools/sb-keys.sh <directory>
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/env.sh

KEYS="${1:?directory delle chiavi mancante}"
[ -f out/tools.tar ] || die "manca out/tools.tar: esegui ./tools.sh"
mkdir -p "${KEYS}"
chmod 700 "${KEYS}"
KEYS="$(realpath "${KEYS}")"
case "${KEYS}/" in "${PWD}/"*) die "le chiavi non vanno dentro il repository" ;; esac
[ -e "${KEYS}/db.key" ] && die "chiavi già presenti in ${KEYS}"

WORK="$(mktemp -d "${TMPDIR:-/var/tmp}/golden-keys.XXXXXX")"
trap 'as_root rm -rf "${WORK}"' EXIT
as_root lib/chroot.sh "${PWD}" "${WORK}" "${KEYS}:/keys" -- /bin/bash -euo pipefail -c '
  cd /keys
  umask 077
  GUID="$(cat /proc/sys/kernel/random/uuid)"   # proprietario delle voci nelle liste EFI
  echo "${GUID}" > GUID
  # RSA 2048: è la dimensione che ogni firmware UEFI deve supportare
  for k in PK KEK db; do
    openssl req -new -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
      -subj "/CN=Golden Image ${k}/" -keyout "${k}.key" -out "${k}.crt" 2>/dev/null
    cert-to-efi-sig-list -g "${GUID}" "${k}.crt" "${k}.esl"
  done
  # PK firma se stessa e KEK; KEK firma db
  sign-efi-sig-list -g "${GUID}" -k PK.key  -c PK.crt  PK  PK.esl  PK.auth
  sign-efi-sig-list -g "${GUID}" -k PK.key  -c PK.crt  KEK KEK.esl KEK.auth
  sign-efi-sig-list -g "${GUID}" -k KEK.key -c KEK.crt db  db.esl  db.auth
  chmod 644 *.crt *.esl *.auth GUID
  ls -l
'
