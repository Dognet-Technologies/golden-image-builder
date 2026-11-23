#!/usr/bin/env bash
# Verifica che un disco FIRMATO corrisponda al disco NON firmato ricostruito da
# chiunque dagli stessi sorgenti (articolo 8). La firma Secure Boot non è
# deterministica (signingTime): si confronta tutto il resto.
#  - stessa tabella delle partizioni (tipi, etichette, dimensioni)
#  - partizioni diverse dalla ESP identiche bit per bit
#  - nella ESP stessi file; i binari EFI identici tolta la firma (sbattach --remove)
#    e azzerato il checksum PE, che sbsign ricalcola
#   tools/verify-signed.sh <disco-firmato.raw> <disco-non-firmato.raw> [db.crt]
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/env.sh
SIGNED="$(realpath "${1:?disco firmato}")"; PLAIN="$(realpath "${2:?disco non firmato}")"
CERT="${3:-}"
WORK="$(mktemp -d "${TMPDIR:-/var/tmp}/golden-verify.XXXXXX")"
trap 'as_root rm -rf "${WORK}"' EXIT
BINDS=("$(dirname "${SIGNED}"):/disks/a:ro" "$(dirname "${PLAIN}"):/disks/b:ro")
[ -n "${CERT}" ] && BINDS+=("$(dirname "$(realpath "${CERT}")"):/cert:ro")
as_root lib/chroot.sh "${PWD}" "${WORK}" "${BINDS[@]}" -- /bin/bash -euo pipefail -s \
  "/disks/a/$(basename "${SIGNED}")" "/disks/b/$(basename "${PLAIN}")" "${CERT:+/cert/$(basename "${CERT}")}" <<'INNER'
A="$1" B="$2" CERT="$3"
. /src/tests/guest/lib.sh
layout() { sfdisk --dump "$1" | grep -E '^/' | sed -E 's|^[^:]+:||; s/uuid=[^,]+, //'; }
check "stessa tabella delle partizioni (tipi, etichette, dimensioni)" test "$(layout "$A")" = "$(layout "$B")"
while read -r start size type name; do
  if [ "${type}" = C12A7328-F81F-11D2-BA4B-00A0C93EC93B ]; then ESP_OFF=$((start * 512)); continue; fi
  ha="$(dd if="$A" bs=512 skip="${start}" count="${size}" status=none | sha256sum)"
  hb="$(dd if="$B" bs=512 skip="${start}" count="${size}" status=none | sha256sum)"
  check "partizione ${name} identica" test "${ha}" = "${hb}"
done < <(sfdisk --dump "$A" | grep -E '^/' | sed -E 's/.*start= *([0-9]+), size= *([0-9]+), type=([^,]+),.*name="([^"]*)".*/\1 \2 \3 \4/')
mkdir -p /work/a /work/b
mcopy -s -n -i "$A@@${ESP_OFF}" ::/ /work/a/
mcopy -s -n -i "$B@@${ESP_OFF}" ::/ /work/b/
check "ESP: stessi file" test "$(cd /work/a && find . -type f | sort)" = "$(cd /work/b && find . -type f | sort)"
normalize() {  # copia senza firma e con checksum PE azzerato
  cp "$1" "$2"; sbattach --remove "$2" >/dev/null 2>&1 || true
  python3 - "$2" <<'PY'
import struct, sys
with open(sys.argv[1], "r+b") as f:
    f.seek(0x3c); pe = struct.unpack("<I", f.read(4))[0]
    f.seek(pe + 4 + 20 + 64); f.write(b"\0\0\0\0")
PY
}
while read -r f; do
  if [[ "${f}" == *.efi || "${f}" == *.EFI ]]; then
    [ -n "${CERT}" ] && check "firma valida: ${f}" sbverify --cert "${CERT}" "/work/a/${f}"
    normalize "/work/a/${f}" /work/na; normalize "/work/b/${f}" /work/nb
    check "${f}: identico tolta la firma" cmp -s /work/na /work/nb
  else
    check "${f}: identico" cmp -s "/work/a/${f}" "/work/b/${f}"
  fi
done < <(cd /work/a && find . -type f | sed 's|^\./||' | sort)
INNER
