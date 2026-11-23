#!/usr/bin/env bash
# Drift detection sulla VM avviata (articolo 9): confronta /etc con il manifest
# dell'immagine e, nella variante mutabile, i file dei pacchetti con dpkg --verify.
# Le differenze attese (identità nate al primo avvio) sono elencate qui sotto.
#   [VARIANT=...] tests/drift.sh <profilo>
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/env.sh
PROFILE="${1:-web}"
check_profile "${PROFILE}"; check_variant "${VARIANT}"
MAN="out/manifest-${PROFILE}-${VARIANT}.sha256"
# Cambiamenti attesi del profilo (es. configurazione del cluster creata al primo avvio)
DRIFT_EXPECTED="$(sed -n "s/^DRIFT_EXPECTED=//p" "tests/guest/profiles/${PROFILE}.env" 2>/dev/null | tr -d "'\"")"
[ -f "${MAN}" ] || die "manca ${MAN}: esegui tools/manifest.sh ${PROFILE}"
{ cat tests/guest/lib.sh; echo "VARIANT=${VARIANT}"; printf 'PROFILE_EXPECTED=%q\n' "${DRIFT_EXPECTED}"; echo "cat > /tmp/golden-manifest <<'MANIFEST'"; cat "${MAN}"; echo "MANIFEST"; cat <<'GUEST'
# Cambiamenti attesi: identità e stato nati sulla macchina
EXPECTED='^/etc/(machine-id|ssh/ssh_host_.*|\.updated|\.pwd\.lock|credstore.*|adjtime|subuid-|subgid-|passwd-|group-|shadow-|gshadow-)$'
[ -n "${PROFILE_EXPECTED}" ] && EXPECTED="${EXPECTED}|${PROFILE_EXPECTED}"
CHANGED="$(sha256sum --quiet -c /tmp/golden-manifest 2>/dev/null | sed -E 's/: (FAILED.*)$//' | grep -vE "${EXPECTED}" || true)"
if [ -z "${CHANGED}" ]; then pass "/etc identica all'immagine (salvo identità attese)"; else fail "/etc modificata: ${CHANGED//$'\n'/ }"; fi
ADDED="$(comm -13 <(awk '{print $2}' /tmp/golden-manifest | sort) <(find /etc -xdev -type f | sort) | grep -vE "${EXPECTED}" || true)"
if [ -z "${ADDED}" ]; then pass "nessun file nuovo in /etc"; else fail "file nuovi in /etc: ${ADDED//$'\n'/ }"; fi
if [ "${VARIANT}" = mutable ]; then
  # dpkg --verify: checksum diversi (escluse le conffile, che personalizziamo) e file
  # mancanti, tranne documentazione e traduzioni escluse in build con path-exclude
  # Differenze attese, dichiarate:
  #  - /boot vuota: kernel e initrd stanno nella UKI firmata; systemd-repart non copia
  #    /boot ed /efi nella root quando il disco ha una ESP
  #  - /usr/lib/os-release: in build aggiungiamo IMAGE_ID e IMAGE_VERSION (sysupdate)
  EXCLUDED='^/usr/share/(doc|man|info|locale)/|^/boot/'
  BAD="$(dpkg --verify 2>/dev/null | awk -v ex="${EXCLUDED}" '
    $1 == "missing" && $NF !~ ex {print "mancante:" $NF; next}
    $1 ~ /^..5/ && $2 != "c" && $NF != "/usr/lib/os-release" {print "modificato:" $NF}' || true)"
  if [ -z "${BAD}" ]; then pass "dpkg --verify: file dei pacchetti integri"; else fail "dpkg --verify: ${BAD//$'\n'/ }"; fi
else
  check "root su dm-verity in sola lettura" bash -c 'findmnt -no SOURCE,OPTIONS / | grep -qE "^/dev/mapper/root ro,"'
fi
rm -f /tmp/golden-manifest
GUEST
} | tests/vm.sh ssh bash -s
