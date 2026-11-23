#!/usr/bin/env bash
# Esegue nella VM avviata i controlli comuni (kernel, userland) e quelli del profilo.
#   tests/run-guest.sh <profilo>
set -euo pipefail
cd "$(dirname "$0")"
PROFILE="${1:?profilo mancante}"
FILES=(guest/lib.sh)
[ -f "guest/profiles/${PROFILE}.env" ] && FILES+=("guest/profiles/${PROFILE}.env")
FILES+=(guest/kernel.sh guest/userland.sh)
[ -f "guest/profiles/${PROFILE}.sh" ] && FILES+=("guest/profiles/${PROFILE}.sh")
# Prima la fine dell'avvio: SSH risponde quando alcuni servizi sono ancora in partenza
# (degraded è ammesso qui: le unità fallite le controlla userland.sh)
./vm.sh ssh 'systemctl is-system-running --wait' < /dev/null > /dev/null || true
cat "${FILES[@]}" | ./vm.sh ssh bash -s
