#!/usr/bin/env bash
# Scansione delle vulnerabilità di un profilo (articolo 8): SBOM x Debian Security Tracker.
# I dati del tracker sono pubblici; si scaricano al più una volta al giorno.
#   [VARIANT=...] tools/vulnscan.sh <profilo>
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/env.sh
PROFILE="${1:-web}"
check_profile "${PROFILE}"; check_variant "${VARIANT}"
SBOM="out/sbom-${PROFILE}-${VARIANT}.cdx.json"
[ -f "${SBOM}" ] || die "manca ${SBOM}: esegui tools/sbom.sh ${PROFILE}"
CACHE=out/cache/debian-security-tracker.json
mkdir -p out/cache
if [ ! -s "${CACHE}" ] || [ -n "$(find "${CACHE}" -mmin +1440)" ]; then
  curl -fsSL --compressed -o "${CACHE}.tmp" https://security-tracker.debian.org/tracker/data/json
  mv "${CACHE}.tmp" "${CACHE}"
fi
OUT="out/vulns-${PROFILE}-${VARIANT}.json"
python3 -I lib/vulnscan.py "${SBOM}" "${CACHE}" trixie > "${OUT}.tmp"
mv "${OUT}.tmp" "${OUT}"
python3 -I - "${OUT}" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
print(f"{sys.argv[1]}: {r['sources']} pacchetti sorgente, {r['summary']}")
print(f"  correggibili per urgenza: {r['fixable_by_urgency']}")
for f in [x for x in r["findings"] if x["kind"] == "fixable"][:8]:
    print(f"  {f['cve']:16} {f['source']:18} {f['installed']} -> {f['fixed']} ({f['urgency']})")
PY
