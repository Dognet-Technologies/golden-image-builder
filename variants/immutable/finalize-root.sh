#!/bin/bash
# Variante immutabile (articolo 5), eseguito da image/mkdisk.sh sul rootfs estratto.
#  - lo stato della macchina vive in /var (partizione separata, scrivibile);
#  - il contenuto iniziale di /var sta in /usr/share/factory/var e tmpfiles lo
#    copia la prima volta (e copia le directory nuove portate dagli aggiornamenti);
#  - /root, /home e /srv diventano link dentro /var.
set -euo pipefail
ROOT="$1"

# 1. /var e le home in factory, link al loro posto
install -d -m 0755 "${ROOT}/usr/share/factory"
mv "${ROOT}/var" "${ROOT}/usr/share/factory/var"
install -d -m 0755 "${ROOT}/var"
# Punto di montaggio /var/tmp già nella root: PrivateTmp=disconnected (es. resolved)
# monta un tmpfs su /var/tmp anche prima che la partizione /var sia montata
install -d -m 1777 "${ROOT}/var/tmp"
for d in root:roothome home:home srv:srv; do
  src="${d%%:*}" dst="${d##*:}"
  mv "${ROOT}/${src}" "${ROOT}/usr/share/factory/var/${dst}"
  ln -s "var/${dst}" "${ROOT}/${src}"
done

# 2. tmpfiles: "C" copia da /usr/share/factory se la destinazione non esiste.
#    Granularità al secondo livello per lib, cache, log, spool: così anche le
#    directory introdotte da un aggiornamento vengono create.
{
  echo "# Generato in build (articolo 5): popola /var da /usr/share/factory/var"
  cd "${ROOT}/usr/share/factory/var"
  for top in *; do
    case "${top}" in
      lib|cache|log|spool)
        echo "d /var/${top} 0755 root root -"
        for sub in "${top}"/*; do
          [ -e "${sub}" ] || continue
          [ "${sub}" = lib/dpkg ] && continue
          echo "C /var/${sub} - - - - -"
        done ;;
      tmp) echo "d /var/tmp 1777 root root 30d" ;;   # serve anche a PrivateTmp=
      *) echo "C /var/${top} - - - - -" ;;
    esac
  done
  echo "# Il database di dpkg descrive la root in sola lettura: sempre quello dell'immagine"
  echo "L+ /var/lib/dpkg - - - - /usr/share/factory/var/lib/dpkg"
} > "${ROOT}/usr/lib/tmpfiles.d/golden-var.conf"
