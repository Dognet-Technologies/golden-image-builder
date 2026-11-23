#!/usr/bin/env bash
# Audit con lynis nella VM avviata, SENZA installarlo (articolo 9): lynis è fatto di
# script shell, lo copiamo in /tmp, lo eseguiamo e lo cancelliamo. Il pacchetto
# arriva dall'archivio Debian (stessa versione di trixie).
#   tests/lynis.sh [file-di-output]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-out/lynis-report.txt}"
CACHE=out/cache/lynis
if [ ! -d "${CACHE}/lynis" ]; then
  rm -rf "${CACHE}"; mkdir -p "${CACHE}"
  (cd "${CACHE}" && apt-get download lynis >/dev/null && dpkg-deb -x lynis_*.deb x)
  mkdir -p "${CACHE}/lynis"
  cp -a "${CACHE}/x/usr/sbin/lynis" "${CACHE}/x/usr/share/lynis/include" "${CACHE}/x/usr/share/lynis/db" \
        "${CACHE}/x/etc/lynis/plugins" "${CACHE}/x/etc/lynis/default.prf" "${CACHE}/lynis/"
fi
tar -C "${CACHE}" --owner=0 --group=0 -cf - lynis | tests/vm.sh ssh '
  set -e; rm -rf /tmp/lynis; tar -C /tmp -xf -; cd /tmp/lynis
  ./lynis audit system --no-colors --quiet --no-log --report-file /tmp/lynis-report.dat >/dev/null 2>&1 || true
  echo "hardening_index=$(sed -n "s/^hardening_index=//p" /tmp/lynis-report.dat)"
  echo "tests_performed=$(sed -n "s/^lynis_tests_done=//p" /tmp/lynis-report.dat)"
  echo "warnings=$(grep -c "^warning\[\]=" /tmp/lynis-report.dat || true)"
  echo "suggestions=$(grep -c "^suggestion\[\]=" /tmp/lynis-report.dat || true)"
  grep -E "^(warning|suggestion)\[\]=" /tmp/lynis-report.dat | sed -E "s/\[\]=/ /"
  rm -rf /tmp/lynis /tmp/lynis-report.dat' > "${OUT}"
head -4 "${OUT}"
