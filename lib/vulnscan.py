"""Vulnerabilità di un'immagine (articolo 8): SBOM CycloneDX x Debian Security Tracker.

Uso: python3 -I lib/vulnscan.py <sbom.cdx.json> <tracker.json> <suite> > report.json
Per ogni pacchetto sorgente installato e ogni CVE del tracker per la suite:
 - "fixable": il tracker indica una versione corretta più recente di quella installata
               (serve una nuova immagine: è il caso coperto dagli SLA di patch);
 - "open":    vulnerabilità nota senza correzione nella suite;
 - le voci "unimportant" e gli stati non determinati sono contati a parte.
"""
import collections
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import debver  # noqa: E402


def main():
    sbom_path, tracker_path, suite = sys.argv[1:4]
    sbom = json.load(open(sbom_path))
    tracker = json.load(open(tracker_path))
    sources = {}
    for c in sbom["components"]:
        props = {p["name"]: p["value"] for p in c.get("properties", [])}
        src, ver = props["debian:source"], props["debian:source_version"]
        # I pacchetti firmati per Secure Boot hanno un sorgente proprio, assente dal
        # tracker (es. linux-signed-amd64 6.12.117+1): le CVE stanno sotto il sorgente
        # non firmato (linux), con la versione del pacchetto binario (6.12.117-1)
        unsigned = re.sub(r"-signed(-[a-z0-9]+)?$", "", src)
        if unsigned != src:
            src, ver = unsigned, c["version"]
        sources.setdefault(src, ver)

    findings = []
    for src, installed in sorted(sources.items()):
        for cve, info in tracker.get(src, {}).items():
            rel = info.get("releases", {}).get(suite)
            if not rel:
                continue
            urgency = rel.get("urgency", "not yet assigned")
            status = rel.get("status")
            fixed = rel.get("fixed_version")
            if status == "resolved" and fixed and fixed != "0" and debver.compare(installed, fixed) < 0:
                kind = "fixable"
            elif status == "open":
                kind = "open"
            elif status == "undetermined":
                kind = "undetermined"
            else:
                continue
            if urgency == "unimportant":
                kind += "-unimportant"
            findings.append({"cve": cve, "source": src, "installed": installed,
                             "fixed": fixed if kind.startswith("fixable") else None,
                             "urgency": urgency, "kind": kind,
                             "description": (info.get("description") or "")[:160]})
    summary = collections.Counter(f["kind"] for f in findings)
    by_urgency = collections.Counter(f["urgency"] for f in findings if f["kind"] == "fixable")
    json.dump({"image": sbom["metadata"]["component"]["name"],
               "version": sbom["metadata"]["component"]["version"],
               "suite": suite, "sources": len(sources),
               "summary": dict(sorted(summary.items())),
               "fixable_by_urgency": dict(sorted(by_urgency.items())),
               "findings": sorted(findings, key=lambda f: (f["kind"], f["source"], f["cve"]))},
              sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
