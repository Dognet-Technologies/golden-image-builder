"""Verifica lib/debver.py contro dpkg (articolo 8): confronta coppie di versioni
reali, prese da una SBOM, più alcuni casi limite (~, epoche, revisioni).
Uso: python3 -I tests/check-debver.py out/sbom-<profilo>-<variante>.cdx.json"""
import json
import os
import random
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import debver  # noqa: E402

versions = sorted({c["version"] for c in json.load(open(sys.argv[1]))["components"]})
versions += ["1.0~rc1", "1.0", "1.0+deb13u1", "1.0-1~bpo13+1", "1:0.1", "2.0a", "2.0.0"]
random.seed(1)
pairs = [(random.choice(versions), random.choice(versions)) for _ in range(400)]


def dpkg(a, b):
    if subprocess.run(["dpkg", "--compare-versions", a, "eq", b]).returncode == 0:
        return 0
    return 1 if subprocess.run(["dpkg", "--compare-versions", a, "gt", b]).returncode == 0 else -1


bad = 0
for a, b in pairs:
    r = debver.compare(a, b)
    mine = (r > 0) - (r < 0)
    if mine != dpkg(a, b):
        bad += 1
        print("DIVERSO:", a, b)
print(f"{len(pairs)} confronti, {bad} diversi da dpkg")
sys.exit(1 if bad else 0)
