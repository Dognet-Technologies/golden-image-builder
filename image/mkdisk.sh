#!/usr/bin/env bash
# Crea il disco dentro il chroot degli strumenti (vedi lib/chroot.sh).
# /src = repository (ro), /out = output, /keys = chiavi Secure Boot (opzionali, ro)
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
PROFILE="$1" VARIANT="$2"
. /src/lib/env.sh

IMAGE_ID="golden-${PROFILE}"
ROOT=/work/root
ESP=/work/esp
DISK="/out/disk-${PROFILE}-${VARIANT}.raw"
TMP_DISK="/out/.disk-${PROFILE}-${VARIANT}.$$.raw"
trap 'rm -f "${TMP_DISK}"' EXIT

# Riga di comando da più file, senza commenti e su una riga
cmdline_from() {
  local files=() f
  for f in "$@"; do [ -f "${f}" ] && files+=("${f}"); done
  sed 's/#.*//' "${files[@]}" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//'
}

# Date fisse su tutto ciò che abbiamo toccato (come fa mkinitramfs)
clamp_mtimes() {
  find "$@" -newermt "@${SOURCE_DATE_EPOCH}" -print0 \
    | xargs -0r touch --no-dereference --date="@${SOURCE_DATE_EPOCH}"
}

# 1. Filesystem radice e ESP vuota. /dev resta vuota: al boot c'è devtmpfs
mkdir -p "${ROOT}" "${ESP}/EFI/BOOT" "${ESP}/EFI/Linux" "${ESP}/loader"
tar -C "${ROOT}" --numeric-owner --xattrs --xattrs-include='*' \
    --exclude='./dev/*' -xpf "/out/rootfs-${PROFILE}-${VARIANT}.tar"

# 2. Primo avvio riconoscibile (variante mutabile): con machine-id vuoto systemd
#    NON lo considera primo avvio e sshd-keygen (ConditionFirstBoot=yes) non parte.
#    Nella variante immutabile /etc è in sola lettura: machine-id dal firmware.
[ "${VARIANT}" = mutable ] && printf 'uninitialized\n' > "${ROOT}/etc/machine-id"

# 3. Identità dell'immagine in os-release: systemd-sysupdate la usa come versione attuale
cat >> "${ROOT}/usr/lib/os-release" <<OSREL
IMAGE_ID=${IMAGE_ID}
IMAGE_VERSION=${IMAGE_VERSION}
OSREL

# 4. Kernel: ne vogliamo esattamente uno
set -- "${ROOT}"/boot/vmlinuz-*
[ "$#" -eq 1 ] && [ -f "$1" ] || die "atteso un solo kernel in /boot"
KVER="${1##*/vmlinuz-}"

# 5. Firma Secure Boot, se ci sono le chiavi
SIGN=()
if [ -f /keys/db.key ]; then
  SIGN=(--signtool=sbsign --secureboot-private-key=/keys/db.key --secureboot-certificate=/keys/db.crt)
fi

# 6. Bootloader nel percorso di fallback (nessuna voce NVRAM necessaria)
BOOT_EFI="${ROOT}/usr/lib/systemd/boot/efi/systemd-bootx64.efi"
if [ "${#SIGN[@]}" -gt 0 ]; then
  sbsign --key /keys/db.key --cert /keys/db.crt --output "${ESP}/EFI/BOOT/BOOTX64.EFI" "${BOOT_EFI}"
else
  install -m 0644 "${BOOT_EFI}" "${ESP}/EFI/BOOT/BOOTX64.EFI"
fi
cat > "${ESP}/loader/loader.conf" <<LOADER
timeout 0
editor no
auto-entries no
auto-firmware no
LOADER

# 7. Enrollment automatico delle chiavi (solo per VM di test in setup mode):
#    systemd-boot registra da solo solo le chiavi in /loader/keys/auto
if [ "${ENROLL:-0}" = 1 ]; then
  for f in PK KEK db; do
    [ -f "/keys/${f}.auth" ] || die "ENROLL=1 richiede /keys/${f}.auth"
  done
  mkdir -p "${ESP}/loader/keys/auto"
  install -m 0644 /keys/PK.auth /keys/KEK.auth /keys/db.auth "${ESP}/loader/keys/auto/"
  echo "secure-boot-enroll if-safe" >> "${ESP}/loader/loader.conf"
fi

# 8. UUID da un seed fisso, hash seed di ext4 fisso: disco riproducibile
SEED="$(uuid_from "golden-${PROFILE}-${VARIANT}-${IMAGE_VERSION}")"
sed "s/@HASH_SEED@/$(uuid_from "ext4-${SEED}")/" /src/common/mke2fs.conf.in > /work/mke2fs.conf
export MKE2FS_CONFIG=/work/mke2fs.conf
REPART=(systemd-repart --dry-run=no --offline=yes --seed="${SEED}")

# 9. Riga di comando: comune + profilo + variante (+ root, per l'immutabile)
CMDLINE="$(cmdline_from /src/common/cmdline "/src/profiles/${PROFILE}/cmdline" "/src/variants/${VARIANT}/cmdline")"
UKI_NAME="${IMAGE_ID}_${IMAGE_VERSION}.efi"
DEFS="/src/repart.d/${VARIANT}"

if [ "${VARIANT}" = immutable ]; then
  /src/variants/immutable/finalize-root.sh "${ROOT}"
  # 9a. Root erofs + verity come file separati: da qui il roothash
  clamp_mtimes "${ROOT}"
  mkdir -p /work/split
  "${REPART[@]}" --empty=create --size=auto --split=yes --json=short \
    --definitions=/src/repart.d/immutable-root /work/split/img.raw > /work/split/repart.json
  ROOTHASH="$(python3 -c 'import json,sys; print(next(p["roothash"] for p in json.load(open(sys.argv[1])) if p.get("roothash")))' /work/split/repart.json)"
  LABEL="${IMAGE_ID}_${IMAGE_VERSION}"
  echo "roothash ${ROOTHASH}"
  # Il roothash nella UKI firmata: firmware -> systemd-boot -> UKI -> ogni blocco della root
  CMDLINE="roothash=${ROOTHASH} systemd.verity_root_data=/dev/disk/by-partlabel/${LABEL} systemd.verity_root_hash=/dev/disk/by-partlabel/${LABEL}_verity root=/dev/mapper/root ro ${CMDLINE}"
  # Definizioni con l'etichetta della versione
  mkdir -p /work/repart.d
  for f in "${DEFS}"/*.conf "${DEFS}"/*.conf.in; do
    sed "s/@LABEL@/${LABEL}/g" "${f}" > "/work/repart.d/$(basename "${f}" .in)"
  done
  DEFS=/work/repart.d
fi

# 10. UKI: kernel + initrd + cmdline + os-release in un unico binario EFI (firmato)
ukify build \
  --linux="${ROOT}/boot/vmlinuz-${KVER}" \
  --initrd="${ROOT}/boot/initrd.img-${KVER}" \
  --stub="${ROOT}/usr/lib/systemd/boot/efi/linuxx64.efi.stub" \
  --os-release="@${ROOT}/usr/lib/os-release" \
  --uname="${KVER}" \
  --cmdline="${CMDLINE}" \
  "${SIGN[@]}" \
  --output="${ESP}/EFI/Linux/${UKI_NAME}"
clamp_mtimes "${ROOT}" "${ESP}"

# 11. Disco
"${REPART[@]}" --empty=create --size=auto --definitions="${DEFS}" "${TMP_DISK}"
mv "${TMP_DISK}" "${DISK}"
sha256sum "${DISK}" | sed 's|/out/|out/|' | tee "${DISK}.sha256"

# 12. Variante immutabile: artefatti di aggiornamento per systemd-sysupdate
if [ "${VARIANT}" = immutable ]; then
  UPD="/out/update/${IMAGE_ID}"
  mkdir -p "${UPD}"
  install -m 0644 /work/split/img.root.raw "${UPD}/${IMAGE_ID}_${IMAGE_VERSION}.root.raw"
  install -m 0644 /work/split/img.verity.raw "${UPD}/${IMAGE_ID}_${IMAGE_VERSION}.verity.raw"
  install -m 0644 "${ESP}/EFI/Linux/${UKI_NAME}" "${UPD}/${UKI_NAME}"
  echo "artefatti di aggiornamento in ${UPD#/}"
fi
