#!/usr/bin/env bash
# Test end-to-end degli aggiornamenti A/B della variante immutabile (articolo 5):
#  1. installa la versione 1 e la avvia;
#  2. pubblica la versione 2 (manifest firmato), aggiorna con systemd-sysupdate,
#     riavvia: deve girare la 2 dallo slot B, confermata da systemd-bless-boot;
#  3. pubblica una versione 3 MANOMESSA (root alterata, roothash originale):
#     dm-verity la rifiuta, i 3 tentativi si esauriscono e torna la versione 2.
#   GOLDEN_KEYS=<dir> tests/ab-update.sh <profilo>
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/env.sh
PROFILE="${1:-web}"
check_profile "${PROFILE}"
: "${GOLDEN_KEYS:?serve GOLDEN_KEYS (chiave di firma degli aggiornamenti)}"
ID="golden-${PROFILE}"
UPD="out/update/${ID}"
BASE="${SNAP:0:8}"
. tests/guest/lib.sh
trap 'rc=$?; if [ "${rc}" -ne 0 ]; then echo "---- interrotto (codice ${rc})"; exit "${rc}"; fi; finish' EXIT
vm() { tests/vm.sh "$@"; }
on_vm() { tests/vm.sh ssh "$@" < /dev/null; }

rm -rf "${UPD}"
mkdir -p out/logs
echo "== versione 1 (disco) e versione 2 (aggiornamento)"
BUILD=1 VARIANT=immutable ./image.sh "${PROFILE}" > out/logs/ab-v1.log 2>&1
command cp -f "out/disk-${PROFILE}-immutable.raw" "out/disk-${PROFILE}-immutable-v1.raw"
BUILD=2 VARIANT=immutable ./image.sh "${PROFILE}" > out/logs/ab-v2.log 2>&1
tools/publish.sh "${PROFILE}" > out/logs/ab-publish.log 2>&1

python3 -m http.server 8080 --bind 127.0.0.1 --directory out/update > out/logs/ab-http.log 2>&1 &
HTTP=$!
# Se un comando fallisce (set -e) il riepilogo non deve dire "0 falliti"
trap 'rc=$?; kill ${HTTP} 2>/dev/null; vm stop
      if [ "${rc}" -ne 0 ]; then echo "---- interrotto (codice ${rc})"; exit "${rc}"; fi
      finish' EXIT

vm start "out/disk-${PROFILE}-immutable-v1.raw" > /dev/null
check "avviata la versione 1" on_vm grep -q "IMAGE_VERSION=${BASE}.1" /etc/os-release
KEY1="$(on_vm cat /var/lib/ssh/ssh_host_ed25519_key.pub)"
MID1="$(on_vm cat /etc/machine-id)"

echo "== aggiornamento alla versione 2"
check "sysupdate vede la versione 2" bash -c "tests/vm.sh ssh /usr/lib/systemd/systemd-sysupdate check-new < /dev/null 2>/dev/null | grep -qx ${BASE}.2"
check "sysupdate installa la versione 2" on_vm /usr/lib/systemd/systemd-sysupdate update
vm reboot > /dev/null
check "avviata la versione 2" on_vm grep -q "IMAGE_VERSION=${BASE}.2" /etc/os-release
check "root dallo slot della versione 2" on_vm grep -q "verity_root_data=/dev/disk/by-partlabel/${ID}_${BASE}.2" /proc/cmdline
check "avvio confermato (UKI senza contatore)" on_vm test -f "/efi/EFI/Linux/${ID}_${BASE}.2.efi"
check "chiave host SSH invariata" test "$(on_vm cat /var/lib/ssh/ssh_host_ed25519_key.pub)" = "${KEY1}"
check "machine-id invariato" test "$(on_vm cat /etc/machine-id)" = "${MID1}"

echo "== versione 3 manomessa"
BUILD=3 VARIANT=immutable ./image.sh "${PROFILE}" > out/logs/ab-v3.log 2>&1
python3 - "${UPD}/${ID}_${BASE}.3.root.raw" <<'PY'
import sys
with open(sys.argv[1], "r+b") as f:          # 16 byte del superblocco erofs invertiti
    f.seek(1040); b = f.read(16); f.seek(1040); f.write(bytes(x ^ 0xff for x in b))
PY
tools/publish.sh "${PROFILE}" > out/logs/ab-publish.log 2>&1
check "sysupdate installa la versione 3" on_vm /usr/lib/systemd/systemd-sysupdate update
WAIT=300 vm reboot > /dev/null || true
check "rollback: di nuovo la versione 2" on_vm grep -q "IMAGE_VERSION=${BASE}.2" /etc/os-release
check "versione 3 marcata come non avviabile (+0-3)" on_vm test -f "/efi/EFI/Linux/${ID}_${BASE}.3+0-3.efi"
check "dm-verity ha rilevato la manomissione" grep -aq "verity: .* data block .* is corrupted" out/vm/console.log
echo "INFO  avvii nel log della console: $(grep -ac 'Linux version' out/vm/console.log)"
