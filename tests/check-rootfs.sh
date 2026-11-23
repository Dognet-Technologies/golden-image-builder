#!/usr/bin/env bash
# Controlli statici sull'archivio del rootfs, senza estrarlo né avviarlo.
#   [VARIANT=...] tests/check-rootfs.sh <profilo>
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/env.sh
PROFILE="${1:-web}"
check_profile "${PROFILE}"; check_variant "${VARIANT}"
TAR="out/rootfs-${PROFILE}-${VARIANT}.tar"
[ -f "${TAR}" ] || die "manca ${TAR}"
. tests/guest/lib.sh

LIST="$(tar -tvf "${TAR}" --numeric-owner)"
# 1. Proprietari: nessun file di utenti "umani" (uid/gid >= 1000)
BAD_OWNER="$(awk '{split($2,o,"/"); if (o[1]>=1000 && o[1]<65534 || o[2]>=1000 && o[2]<65534) print $NF}' <<<"${LIST}" | head -5)"
if [ -z "${BAD_OWNER}" ]; then pass "nessun file con uid/gid >= 1000"; else fail "file con uid/gid >= 1000: ${BAD_OWNER//$'\n'/ }"; fi
# 2. Niente scrivibile da tutti, tranne le directory sticky previste
BAD_WW="$(awk '$1 ~ /^[-d].......w/ && $1 !~ /t$/ {print $NF}' <<<"${LIST}" | head -5)"
if [ -z "${BAD_WW}" ]; then pass "nessun file scrivibile da tutti"; else fail "scrivibili da tutti: ${BAD_WW//$'\n'/ }"; fi
has() { grep -qE "$1" <<<"${LIST}"; }
# 3. Radice e /etc: root, 755
if has '^drwxr-xr-x 0/0 .* \./$' && has '^drwxr-xr-x 0/0 .* \./etc/$'; then
  pass "/ e /etc di root con permessi 755"; else fail "/ o /etc con proprietario o permessi errati"; fi
# 4. Nessuna identità e nessuna traccia della build
for f in './etc/ssh/ssh_host_' './etc/hostname$' './etc/apt/sources.list$' './etc/apt/apt.conf.d/99mmdebstrap'; do
  if has " ${f}"; then fail "presente ${f}"; else pass "assente ${f}"; fi
done
if [ -z "$(tar -xOf "${TAR}" ./etc/machine-id)" ]; then pass "machine-id vuoto"; else fail "machine-id non vuoto"; fi
if tar -xOf "${TAR}" ./etc/apt/sources.list.d/debian.sources | grep -q snapshot; then
  fail "sorgenti APT con lo snapshot"; else pass "sorgenti APT ufficiali, niente snapshot"; fi
if has ' \./etc/resolv.conf -> \.\./run/systemd/resolve/stub-resolv.conf$'; then
  pass "resolv.conf verso lo stub di resolved"; else fail "resolv.conf errato"; fi
