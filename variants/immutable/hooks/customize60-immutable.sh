#!/bin/bash
# Variante immutabile (articolo 5), parte eseguita in build: fstab, transfer di
# systemd-sysupdate, servizi. Lo spostamento di /var in /usr/share/factory avviene
# in image.sh (variants/immutable/finalize-root.sh): mmdebstrap usa ancora /var
# nella sua pulizia finale, dopo gli hook.
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
ROOT="$1"
IMAGE_ID="golden-${GOLDEN_PROFILE}"

# 1. /var montata dalla sua partizione
echo 'PARTLABEL=var  /var  ext4  defaults,nosuid,nodev  0  2' >> "${ROOT}/etc/fstab"

# 2. /etc in sola lettura: niente "aggiornamenti" di /etc a ogni avvio
#    (ConditionNeedsUpdate=/etc confronta /etc/.updated con /usr)
touch "${ROOT}/etc/.updated"

# 3. Machine-id: file vuoto (systemd.machine_id=firmware lo ricava dal firmware)
: > "${ROOT}/etc/machine-id"

# 4. systemd-sysupdate: i transfer arrivano dall'overlay con dei segnaposto
for f in "${ROOT}"/usr/lib/sysupdate.d/*.transfer; do
  sed -i -e "s|@UPDATE_URL@|${UPDATE_URL}|g" -e "s|@IMAGE_ID@|${IMAGE_ID}|g" "${f}"
done

# 5. Avvio "buono" solo se nessuna unit è fallita (boot assessment);
#    apt non ha senso su una root in sola lettura
chroot "${ROOT}" systemctl enable systemd-boot-check-no-failures.service
chroot "${ROOT}" systemctl mask apt-daily.timer apt-daily-upgrade.timer
