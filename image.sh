#!/usr/bin/env bash
# Dal filesystem radice a un disco GPT avviabile: UEFI, UKI, Secure Boot, A/B (articoli 2 e 5)
# Uso: [VARIANT=mutable|immutable] [GOLDEN_KEYS=/percorso/chiavi] [ENROLL=1] ./image.sh <profilo>
set -euo pipefail
cd "$(dirname "$0")"
. lib/env.sh

PROFILE="${1:-web}"
check_profile "${PROFILE}"
check_variant "${VARIANT}"
[ -f "out/rootfs-${PROFILE}-${VARIANT}.tar" ] \
  || die "manca out/rootfs-${PROFILE}-${VARIANT}.tar: esegui VARIANT=${VARIANT} ./build.sh ${PROFILE}"
[ -f out/tools.tar ] || die "manca out/tools.tar: esegui ./tools.sh"

# Chiavi Secure Boot: directory fuori dal repository (vedi tools/sb-keys.sh)
KEYS="${GOLDEN_KEYS:-}"
if [ -n "${KEYS}" ]; then
  KEYS="$(realpath "${KEYS}")"
  [ -f "${KEYS}/db.key" ] && [ -f "${KEYS}/db.crt" ] || die "in ${KEYS} servono db.key e db.crt"
fi
export SNAP IMAGE_VERSION ENROLL="${ENROLL:-0}"

WORK="$(mktemp -d "${TMPDIR:-/var/tmp}/golden-image.XXXXXX")"
# I file estratti appartengono a utenti del namespace: si cancellano da lì
trap 'as_root rm -rf "${WORK}"' EXIT

BINDS=()
[ -n "${KEYS}" ] && BINDS+=("${KEYS}:/keys:ro")
as_root lib/chroot.sh "${PWD}" "${WORK}" "${BINDS[@]}" -- \
  /src/image/mkdisk.sh "${PROFILE}" "${VARIANT}"
