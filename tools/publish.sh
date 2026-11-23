#!/usr/bin/env bash
# Pubblica gli aggiornamenti di un'immagine immutabile: rigenera SHA256SUMS per
# tutte le versioni presenti in out/update/<immagine> e lo firma (SHA256SUMS.gpg).
#   GOLDEN_KEYS=<dir> tools/publish.sh <profilo>
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/env.sh
PROFILE="${1:-web}"
check_profile "${PROFILE}"
KEYS="$(realpath "${GOLDEN_KEYS:?serve GOLDEN_KEYS}")"
[ -d "${KEYS}/gnupg" ] || die "manca la chiave di firma: tools/update-key.sh ${KEYS}"
DIR="update/golden-${PROFILE}"
[ -d "out/${DIR}" ] || die "nessun aggiornamento in out/${DIR}"

WORK="$(mktemp -d "${TMPDIR:-/var/tmp}/golden-publish.XXXXXX")"
trap 'as_root rm -rf "${WORK}"' EXIT
as_root lib/chroot.sh "${PWD}" "${WORK}" "${KEYS}:/keys:ro" -- /bin/bash -euo pipefail -c '
  cd "/out/'"${DIR}"'"
  rm -f SHA256SUMS SHA256SUMS.gpg
  sha256sum -- *.raw *.efi > SHA256SUMS
  # Copia della chiave in /work: gpg vuole scrivere nella sua home
  cp -a /keys/gnupg /work/gnupg
  GNUPGHOME=/work/gnupg gpg --batch --quiet --detach-sign --output SHA256SUMS.gpg SHA256SUMS
  GNUPGHOME=/work/gnupg gpg --batch --verify SHA256SUMS.gpg SHA256SUMS
  cat SHA256SUMS
'
