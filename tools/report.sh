#!/usr/bin/env bash
# Rapporto di un'immagine (articolo 9) in out/reports/<profilo>-<variante>/REPORT.md,
# dagli artefatti e dai log prodotti da tests/run-all.sh.
#   [VARIANT=...] tools/report.sh <profilo>
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/env.sh
PROFILE="${1:-web}"
check_profile "${PROFILE}"; check_variant "${VARIANT}"
R="out/reports/${PROFILE}-${VARIANT}"
mkdir -p "${R}"
python3 -I - "${PROFILE}" "${VARIANT}" "${IMAGE_VERSION}" "${SNAP}" "${R}" > "${R}/REPORT.md" <<'PY'
import glob, json, os, re, sys
profile, variant, version, snap, rdir = sys.argv[1:6]
def read(path, default=""):
    try:
        return open(path, encoding="utf-8").read()
    except OSError:
        return default
def checks(log):
    text = read(log)
    p = len(re.findall(r"^PASS ", text, re.M)); f = re.findall(r"^FAIL +(.*)$", text, re.M)
    return p, f
image = f"golden-{profile}"
rel = f"out/release/{image}_{variant}_{version}"
sums = dict(reversed(l.split("  ", 1)) for l in read(f"{rel}/SHA256SUMS").splitlines() if "  " in l)
sbom = json.loads(read(f"out/sbom-{profile}-{variant}.cdx.json", "{}") or "{}")
vulns = json.loads(read(f"out/vulns-{profile}-{variant}.json", "{}") or "{}")
lynis = read(f"{rdir}/lynis.txt")
li = re.search(r"^hardening_index=(\d+)", lynis, re.M)
out = []
w = out.append
w(f"# Rapporto immagine {image} ({variant}) {version}\n")
w("## Identità\n")
w(f"| Campo | Valore |\n| --- | --- |\n| Immagine | {image} |\n| Variante | {variant} |\n| Versione | {version} |\n| Snapshot Debian | {snap} |")
for f in sorted(sums):
    if f.endswith((".raw", ".tar")):
        w(f"| SHA-256 {f} | `{sums[f]}` |")
w(f"| Manifest firmato | `{rel}/SHA256SUMS(.gpg)` |\n")
comps = sbom.get("components", [])
w("## Contenuto (SBOM CycloneDX)\n")
w(f"- Pacchetti installati: **{len(comps)}**, con licenza dichiarata: {sum(1 for c in comps if c.get('licenses'))}")
w(f"- SBOM: `out/sbom-{profile}-{variant}.cdx.json`\n")
w("## Vulnerabilità (Debian Security Tracker)\n")
s = vulns.get("summary", {})
w(f"- Correggibili con una nuova immagine: **{s.get('fixable', 0)}** (per urgenza: {vulns.get('fixable_by_urgency', {})})")
w(f"- Note senza correzione in trixie: {s.get('open', 0)} (più {s.get('open-unimportant', 0)} classificate «unimportant»)")
fix = [f for f in vulns.get("findings", []) if f["kind"] == "fixable"]
if fix:
    w("\n| CVE | Sorgente | Installata | Corretta in |\n| --- | --- | --- | --- |")
    for f in fix[:15]:
        w(f"| {f['cve']} | {f['source']} | {f['installed']} | {f['fixed']} |")
    if len(fix) > 15:
        w(f"| … | altre {len(fix) - 15} | | |")
w("\n## Controlli automatici\n")
w("| Controllo | Superati | Falliti |\n| --- | --- | --- |")
for name, label in [("check-rootfs", "Rootfs (statici)"), ("check-packages", "Allow-list pacchetti"),
                    ("secureboot", "Secure Boot e lockdown"), ("guest", "Kernel, userland, profilo (nella VM)"),
                    ("drift", "Drift rispetto all'immagine"), ("ab-update", "Aggiornamento A/B e rollback")]:
    log = f"{rdir}/{name}.log"
    if not os.path.exists(log):
        continue
    p, f = checks(log)
    if name in ("check-packages", "secureboot") and not p and not f:
        ok = "OK" in read(log) or os.path.getsize(log) == 0
        w(f"| {label} | {'1' if ok else '0'} | {'0' if ok else '1'} |")
        continue
    w(f"| {label} | {p} | {len(f)} |")
    for x in f:
        w(f"|   ↳ FAIL | {x} | |")
w("\n## Audit lynis\n")
if li:
    warns = re.findall(r"^warning (.*)$", lynis, re.M)
    w(f"- Indice di hardening: **{li.group(1)}**/100, test eseguiti: {re.search(r'^tests_performed=(\d+)', lynis, re.M).group(1)}")
    w(f"- Warning: {len(warns)}" + "".join(f"\n  - {x.split('|')[0]} {x.split('|')[1]}" for x in warns))
    w(f"- Suggerimenti: {len(re.findall(r'^suggestion ', lynis, re.M))} (dettaglio in `{rdir}/lynis.txt`)")
w("\n## Conformità\n")
w("Mappatura dei controlli su ISO/IEC 27001:2022 (Annex A) e NIS2 (art. 21): `docs/conformita.md`.")
print("\n".join(out))
PY
echo "${R}/REPORT.md"
