#!/usr/bin/env bash
# Manifest di /etc del rootfs (articolo 9): sha256 di ogni file regolare, per la
# drift detection sulle macchine in esecuzione (tests/drift.sh).
#   [VARIANT=...] tools/manifest.sh <profilo>
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/env.sh
PROFILE="${1:-web}"
check_profile "${PROFILE}"; check_variant "${VARIANT}"
TAR="out/rootfs-${PROFILE}-${VARIANT}.tar"
[ -f "${TAR}" ] || die "manca ${TAR}"
OUT="out/manifest-${PROFILE}-${VARIANT}.sha256"
python3 -I - "${TAR}" > "${OUT}" <<'PY'
import hashlib, sys, tarfile
with tarfile.open(sys.argv[1]) as t:
    for m in sorted(t.getmembers(), key=lambda m: m.name):
        if m.isfile() and m.name.startswith("./etc/"):
            print(hashlib.sha256(t.extractfile(m).read()).hexdigest(), m.name[1:], sep="  ")
PY
echo "${OUT}: $(wc -l < "${OUT}") file"
