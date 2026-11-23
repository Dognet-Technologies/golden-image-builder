#!/usr/bin/env bash
# Pipeline completa con verifica (articoli 2-9), per ogni coppia profilo:variante.
#   GOLDEN_KEYS=<dir> [NO_BUILD=1] tests/run-all.sh [profilo:variante ...]
# Default: tutti i profili, variante mutabile e immutabile. Per ogni immagine:
# build, controlli statici, SBOM, vulnerabilità, manifest, disco firmato con
# enrollment Secure Boot, avvio con Secure Boot, suite nella VM, lynis, drift,
# (A/B e rollback per web immutabile), rilascio firmato, rapporto.
set -uo pipefail
cd "$(dirname "$0")/.."
. lib/env.sh
: "${GOLDEN_KEYS:?serve GOLDEN_KEYS (chiavi Secure Boot e di firma)}"
export GOLDEN_KEYS
PAIRS=("$@")
[ "${#PAIRS[@]}" -gt 0 ] || PAIRS=(web:mutable db:mutable container:mutable bastion:mutable
                                   web:immutable db:immutable container:immutable bastion:immutable)
SUMMARY=()

run() {  # run <log> <comando...>: esegue, salva il log, ritorna l'esito
  local log="$1"; shift
  "$@" > "${log}" 2>&1
}

for pair in "${PAIRS[@]}"; do
  P="${pair%%:*}" V="${pair##*:}"
  export VARIANT="${V}"
  R="out/reports/${P}-${V}"; rm -rf "${R}"; mkdir -p "${R}"
  echo "===== ${P} ${V}"
  step() { local name="$1"; shift; if run "${R}/${name}.log" "$@"; then echo "  ok   ${name}"; else echo "  FAIL ${name} (vedi ${R}/${name}.log)"; FAILED=1; fi; }
  FAILED=0
  [ "${NO_BUILD:-0}" = 1 ] && [ -f "out/rootfs-${P}-${V}.tar" ] || step build ./build.sh "${P}"
  step check-rootfs tests/check-rootfs.sh "${P}"
  step check-packages tests/check-packages.sh "${P}"
  step sbom tools/sbom.sh "${P}"
  step vulnscan tools/vulnscan.sh "${P}"
  step manifest tools/manifest.sh "${P}"
  step image env ENROLL=1 ./image.sh "${P}"
  CREDS="$(grep -v "^#" "tests/guest/profiles/${P}.creds" 2>/dev/null | tr "\n" " " || true)"
  if CREDS="${CREDS}" run "${R}/vm-start.log" tests/vm.sh start "out/disk-${P}-${V}.raw" secureboot; then
    step secureboot tests/vm.sh ssh 'grep -q "Secure boot enabled" <(dmesg) && grep -q "\[integrity\]" /sys/kernel/security/lockdown'
    step guest tests/run-guest.sh "${P}"
    step lynis tests/lynis.sh "${R}/lynis.txt"
    step drift tests/drift.sh "${P}"
  else
    echo "  FAIL avvio della VM (vedi ${R}/vm-start.log, out/vm/console.log)"; FAILED=1
  fi
  tests/vm.sh stop > /dev/null 2>&1
  step release tools/release.sh "${P}"
  step report tools/report.sh "${P}"
  # Per ultimo: ricostruisce il disco con altre versioni (v1, v2, v3 manomessa)
  if [ "${P}:${V}" = web:immutable ]; then step ab-update tests/ab-update.sh "${P}"; fi
  SUMMARY+=("$( [ "${FAILED}" = 0 ] && echo OK || echo FAIL )  ${P} ${V}")
done
echo "===== riepilogo"; printf '%s\n' "${SUMMARY[@]}"
! printf '%s\n' "${SUMMARY[@]}" | grep -q '^FAIL'
