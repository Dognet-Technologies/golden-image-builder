#!/usr/bin/env bash
# Esegue un comando nel chroot degli strumenti (out/tools.tar).
# Va lanciato come root, vero o di user namespace, in un mount namespace
# privato (vedi as_root in lib/env.sh).
#   lib/chroot.sh <repo> <workdir> [origine:destinazione[:ro] ...] -- comando...
# Dentro il chroot: /src = repository (sola lettura), /out = output, /work = spazio di lavoro
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
REPO="$1" WORK="$2"
shift 2
T="${WORK}/tools"

mkdir -p "${T}"
# /dev arriva dall'host: in user namespace i nodi di dispositivo non si creano
tar -C "${T}" --numeric-owner --exclude='./dev/*' -xpf "${REPO}/out/tools.tar"
mkdir -p "${T}/work" "${T}/src" "${T}/out"

mount -t proc proc "${T}/proc"
mount --rbind /dev "${T}/dev"
mount --bind "${REPO}" "${T}/src"
mount -o remount,bind,ro "${T}/src"
mount --bind "${REPO}/out" "${T}/out"

while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
  IFS=: read -r src dst opt <<<"$1"
  mkdir -p "${T}${dst}"
  mount --bind "${src}" "${T}${dst}"
  [ "${opt:-}" = ro ] && mount -o remount,bind,ro "${T}${dst}"
  shift
done
[ "${1:-}" = "--" ] || { echo "manca -- prima del comando" >&2; exit 1; }
shift

chroot "${T}" "$@"
