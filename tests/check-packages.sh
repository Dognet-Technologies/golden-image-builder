#!/usr/bin/env bash
# Allow-list dei pacchetti: confronta i pacchetti installati nel rootfs con
# profiles/<profilo>/packages-<variante>.lock. Ogni differenza va giustificata e approvata.
#   [VARIANT=...] tests/check-packages.sh <profilo> [--update]
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/env.sh
PROFILE="${1:-web}"
check_profile "${PROFILE}"; check_variant "${VARIANT}"
TAR="out/rootfs-${PROFILE}-${VARIANT}.tar"
LOCK="profiles/${PROFILE}/packages-${VARIANT}.lock"
[ -f "${TAR}" ] || die "manca ${TAR}"

# Un paragrafo per pacchetto: nel file status "Status:" viene PRIMA di "Architecture:",
# quindi si decide a fine paragrafo (RS="" = paragrafi separati da righe vuote).
# Installati sono sia "install ok installed" sia "hold ok installed" (apt-mark hold)
CURRENT="$(tar -xOf "${TAR}" ./var/lib/dpkg/status | awk 'BEGIN {RS=""; FS="\n"}
  { p=a=ok=""
    for (i = 1; i <= NF; i++) {
      if ($i ~ /^Package: /) p = substr($i, 10)
      else if ($i ~ /^Architecture: /) a = substr($i, 15)
      else if ($i ~ /^Status: (install|hold) ok installed$/) ok = 1
    }
    if (ok) print p ":" a }' | sort)"

if [ "${2:-}" = "--update" ]; then
  printf '%s\n' "${CURRENT}" > "${LOCK}"
  echo "Aggiornato ${LOCK}: $(wc -l < "${LOCK}") pacchetti"
  exit 0
fi
[ -f "${LOCK}" ] || die "manca ${LOCK}: crealo con --update e rivedilo"

if DIFF="$(diff <(cat "${LOCK}") <(printf '%s\n' "${CURRENT}"))"; then
  echo "OK: $(wc -l <<<"${CURRENT}") pacchetti, identici all'allow-list"
else
  echo "Pacchetti diversi dall'allow-list (< tolti, > aggiunti):"
  echo "${DIFF}" | grep -E '^[<>]'
  exit 1
fi
