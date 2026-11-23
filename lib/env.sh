# shellcheck shell=bash
# Variabili e funzioni comuni a tutti gli script. Uso: . lib/env.sh

SNAP="${SNAP:-20261117T000000Z}"          # istante dello snapshot dell'archivio
ARCH="${ARCH:-amd64}"                     # architettura: fa parte degli input
BUILD="${BUILD:-1}"                       # numero di build a parità di snapshot
IMAGE_VERSION="${IMAGE_VERSION:-${SNAP:0:8}.${BUILD}}"
VARIANT="${VARIANT:-mutable}"             # mutable | immutable (articolo 5)
# Dove la variante immutabile cerca gli aggiornamenti (10.0.2.2 = host visto da QEMU)
UPDATE_URL="${UPDATE_URL:-http://10.0.2.2:8080}"

die() { echo "ERRORE: $*" >&2; exit 1; }

# Profili ammessi: aggiorna l'elenco quando ne aggiungi uno
check_profile() {
  case "${1:-}" in
    web|db|bastion|container) ;;
    *) die "Profilo non supportato: ${1:-<vuoto>}" ;;
  esac
}

check_variant() {
  case "${1:-}" in
    mutable|immutable) ;;
    *) die "Variante non supportata: ${1:-<vuota>}" ;;
  esac
}

# Data fissa per mtime e metadati: serve alla riproducibilità
SOURCE_DATE_EPOCH="$(date -u -d "${SNAP:0:4}-${SNAP:4:2}-${SNAP:6:2} 00:00:00" +%s)"
export SOURCE_DATE_EPOCH

# UUID deterministico ricavato da una stringa (seed di repart, hash seed di ext4)
uuid_from() {
  local h
  h="$(printf '%s' "$1" | sha256sum)"
  printf '%s-%s-%s-%s-%s\n' "${h:0:8}" "${h:8:4}" "${h:12:4}" "${h:16:4}" "${h:20:12}"
}

# Esegue un comando come root in un mount namespace privato:
# root vero se lanciato con sudo, altrimenti root in un user namespace (subuid)
as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    unshare --mount --propagation private --pid --fork "$@"
  else
    unshare --map-auto --map-root-user --mount --propagation private --pid --fork "$@"
  fi
}
