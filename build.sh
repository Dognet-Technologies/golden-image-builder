#!/usr/bin/env bash
# Filesystem radice come archivio tar riproducibile (articoli 1, 2, 4 e 5).
# Livelli, nell'ordine: common/ + profiles/<profilo>/ + variants/<variante>/
#   [VARIANT=mutable|immutable] ./build.sh <profilo>
# La variante immutabile richiede GOLDEN_KEYS con update-pubring.gpg (tools/update-key.sh)
set -euo pipefail
cd "$(dirname "$0")"
. lib/env.sh

PROFILE="${1:-web}"
check_profile "${PROFILE}"
check_variant "${VARIANT}"
export GOLDEN_PROFILE="${PROFILE}" GOLDEN_VARIANT="${VARIANT}" GOLDEN_SRC="${PWD}" UPDATE_URL  # per gli hook

LAYERS=(common "profiles/${PROFILE}" "variants/${VARIANT}")
OUT="out/rootfs-${PROFILE}-${VARIANT}.tar"
TMP_OUT="out/.rootfs-${PROFILE}-${VARIANT}.$$.tar"
mkdir -p out
trap 'rm -f "${TMP_OUT}"' EXIT           # niente file parziali se la build fallisce

# Pacchetti di tutti i livelli, ignorando righe vuote e commenti
PKG_FILES=()
for l in "${LAYERS[@]}"; do [ -f "${l}/packages.txt" ] && PKG_FILES+=("${l}/packages.txt"); done
PKGS="$(cat "${PKG_FILES[@]}" | sed 's/#.*//' | tr -s '[:space:]' ',' | sed 's/^,//; s/,$//')"

# L'overlay entra nell'immagine con i suoi permessi, anche quelli delle directory
# (sovrascrivono quelli di / e /etc): niente scrivibile da gruppo o altri
for l in "${LAYERS[@]}"; do
  BAD="$(find "${l}/overlay" -perm /022 ! -type l -print -quit 2>/dev/null || true)"
  if [ -n "${BAD}" ]; then
    echo "Permessi troppo larghi nell'overlay (${BAD}): esegui chmod -R go-w" >&2
    exit 1
  fi
done

# Overlay come archivi tar con proprietario root e date fisse: con sync-in, in
# modalità unshare, i file manterrebbero l'uid di chi lancia la build (es. 1000)
OVL_DIR="$(mktemp -d out/.overlay.XXXXXX)"
trap 'rm -f "${TMP_OUT}"; rm -rf "${OVL_DIR}"' EXIT
HOOKS=()
for l in "${LAYERS[@]}"; do
  [ -d "${l}/overlay" ] || continue
  t="${OVL_DIR}/${l//\//_}.tar"
  tar -C "${l}/overlay" --sort=name --owner=0 --group=0 --numeric-owner \
      --mtime="@${SOURCE_DATE_EPOCH}" --clamp-mtime -cf "${t}" .
  HOOKS+=(--customize-hook="tar-in ${t} /")
done
HOOKS+=(--customize-hook='rm -f "$1"/etc/apt/sources.list "$1"/etc/apt/apt.conf.d/99mmdebstrap')
HOOKS+=(--customize-hook='rm -f "$1"/etc/resolv.conf "$1"/etc/hostname')
HOOKS+=(--customize-hook='rm -f "$1"/etc/ssh/ssh_host_*')

# Variante immutabile: chiave pubblica che verifica i manifest degli aggiornamenti
if [ "${VARIANT}" = immutable ]; then
  PUBRING="${GOLDEN_KEYS:-}/update-pubring.gpg"
  [ -f "${PUBRING}" ] || die "la variante immutabile richiede GOLDEN_KEYS con update-pubring.gpg"
  HOOKS+=(--customize-hook="copy-in ${PUBRING} /etc/systemd")
  HOOKS+=(--customize-hook='mv "$1"/etc/systemd/update-pubring.gpg "$1"/etc/systemd/import-pubring.gpg && chown 0:0 "$1"/etc/systemd/import-pubring.gpg && chmod 0644 "$1"/etc/systemd/import-pubring.gpg')
fi

for l in "${LAYERS[@]}"; do
  [ -d "${l}/hooks" ] && HOOKS+=(--hook-directory="${l}/hooks")
done

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
  --dpkgopt='path-exclude=/usr/share/man/*' \
  --dpkgopt='path-exclude=/usr/share/info/*' \
  --dpkgopt='path-exclude=/usr/share/locale/*' \
  --dpkgopt='path-exclude=/usr/share/doc/*' \
  --dpkgopt='path-include=/usr/share/doc/*/copyright' \
  --include="${PKGS}" \
  "${CACHE_OPTS[@]}" \
  "${HOOKS[@]}" \
  trixie "${TMP_OUT}" \
  "deb http://snapshot.debian.org/archive/debian/${SNAP} trixie main" \
  "deb http://snapshot.debian.org/archive/debian-security/${SNAP} trixie-security main"

mv "${TMP_OUT}" "${OUT}"
sha256sum "${OUT}" > "${OUT}.sha256.tmp" && mv "${OUT}.sha256.tmp" "${OUT}.sha256"
cat "${OUT}.sha256"
