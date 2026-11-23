#!/usr/bin/env bash
# SBOM CycloneDX del rootfs di un profilo (articolo 8)
#   [VARIANT=...] tools/sbom.sh <profilo>
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/env.sh
PROFILE="${1:-web}"
check_profile "${PROFILE}"; check_variant "${VARIANT}"
TAR="out/rootfs-${PROFILE}-${VARIANT}.tar"
[ -f "${TAR}" ] || die "manca ${TAR}"
OUT="out/sbom-${PROFILE}-${VARIANT}.cdx.json"
python3 -I lib/sbom.py "${TAR}" "golden-${PROFILE}" "${IMAGE_VERSION}" "${SNAP}" "${VARIANT}" > "${OUT}.tmp"
mv "${OUT}.tmp" "${OUT}"
python3 -I - "${OUT}" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))["components"]
print(f"{sys.argv[1]}: {len(c)} componenti, {sum(1 for x in c if x.get('licenses'))} con licenza")
PY
