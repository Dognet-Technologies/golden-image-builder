#!/usr/bin/env bash
# Chroot con gli strumenti di build, dallo stesso snapshot dell'immagine:
# il risultato non dipende dalle versioni installate sull'host
set -euo pipefail
cd "$(dirname "$0")"
. lib/env.sh

OUT="out/tools.tar"
TMP_OUT="out/.tools.$$.tar"
mkdir -p out
trap 'rm -f "${TMP_OUT}"' EXIT

PKGS="$(sed 's/#.*//' tools/packages.txt | tr -s '[:space:]' ',' | sed 's/^,//; s/,$//')"

# Cache dei .deb scaricati (APT_CACHE= per disattivarla): stessi file e versioni,
# quindi stesso risultato, ma le ricostruzioni non riscaricano tutto dallo snapshot
APT_CACHE="${APT_CACHE-out/cache/apt}"
CACHE_OPTS=()
if [ -n "${APT_CACHE}" ]; then
  mkdir -p "${APT_CACHE}"
  CACHE_OPTS=(--skip=essential/unlink
    --setup-hook='mkdir -p "$1"/var/cache/apt/archives/'
    --setup-hook="sync-in ${APT_CACHE} /var/cache/apt/archives/"
    --setup-hook='chown -R 0:0 "$1"/var/cache/apt/archives'    # sync-in mantiene l'uid di chi lancia
    --customize-hook="sync-out /var/cache/apt/archives ${APT_CACHE}")
fi

mmdebstrap --variant=minbase --architectures="${ARCH}" \
  --aptopt='Acquire::Check-Valid-Until "false"' \
  --include="${PKGS}" \
  "${CACHE_OPTS[@]}" \
  trixie "${TMP_OUT}" \
  "deb http://snapshot.debian.org/archive/debian/${SNAP} trixie main" \
  "deb http://snapshot.debian.org/archive/debian-security/${SNAP} trixie-security main"

mv "${TMP_OUT}" "${OUT}"
sha256sum "${OUT}" > "${OUT}.sha256.tmp" && mv "${OUT}.sha256.tmp" "${OUT}.sha256"
cat "${OUT}.sha256"
