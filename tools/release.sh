#!/usr/bin/env bash
# Rilascio di un'immagine (articolo 8): raccoglie gli artefatti in
# out/release/<immagine>_<variante>_<versione>/ e firma il manifest SHA256SUMS.
#   GOLDEN_KEYS=<dir> [VARIANT=...] tools/release.sh <profilo>
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/env.sh
PROFILE="${1:-web}"
check_profile "${PROFILE}"; check_variant "${VARIANT}"
KEYS="$(realpath "${GOLDEN_KEYS:?serve GOLDEN_KEYS}")"
[ -d "${KEYS}/gnupg" ] || die "manca la chiave di firma: tools/update-key.sh ${KEYS}"
NAME="golden-${PROFILE}_${VARIANT}_${IMAGE_VERSION}"
REL="out/release/${NAME}"
FILES=("out/disk-${PROFILE}-${VARIANT}.raw" "out/rootfs-${PROFILE}-${VARIANT}.tar"
       "out/sbom-${PROFILE}-${VARIANT}.cdx.json" "out/vulns-${PROFILE}-${VARIANT}.json"
       "profiles/${PROFILE}/packages-${VARIANT}.lock")
for f in "${FILES[@]}"; do [ -f "${f}" ] || die "manca ${f}"; done
rm -rf "${REL}"; mkdir -p "${REL}"
for f in "${FILES[@]}"; do ln "${f}" "${REL}/" 2>/dev/null || cp "${f}" "${REL}/"; done
cp "${KEYS}/update-pubring.gpg" "${REL}/release-pubring.gpg"
[ -f "${KEYS}/db.crt" ] && cp "${KEYS}/db.crt" "${REL}/secureboot-db.crt"

WORK="$(mktemp -d "${TMPDIR:-/var/tmp}/golden-release.XXXXXX")"
trap 'as_root rm -rf "${WORK}"' EXIT
as_root lib/chroot.sh "${PWD}" "${WORK}" "${KEYS}:/keys:ro" -- /bin/bash -euo pipefail -c '
  cd "/out/release/'"${NAME}"'"
  sha256sum -- $(ls | grep -vE "^SHA256SUMS") > SHA256SUMS
  cp -a /keys/gnupg /work/gnupg
  GNUPGHOME=/work/gnupg gpg --batch --quiet --detach-sign --output SHA256SUMS.gpg SHA256SUMS
'
echo "Rilascio in ${REL}:"; ls -l "${REL}"
