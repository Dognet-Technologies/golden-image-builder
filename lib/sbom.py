"""SBOM CycloneDX 1.6 di un rootfs (articolo 8), dal database di dpkg dentro il tar.

Uso: python3 -I lib/sbom.py <rootfs.tar> <image-id> <versione> <snapshot> <variante> > sbom.json
Deterministico: data da SOURCE_DATE_EPOCH, serialNumber derivato dall'hash del tar.
"""
import datetime
import hashlib
import json
import os
import re
import sys
import tarfile
import uuid


def paragraphs(text):
    """Paragrafi in formato deb822 (status di dpkg, copyright DEP-5)."""
    for block in re.split(r"\n\s*\n", text):
        fields, key = {}, None
        for line in block.splitlines():
            if line[:1] in (" ", "\t") and key:
                fields[key] += "\n" + line.strip()
            elif ":" in line:
                key, _, value = line.partition(":")
                key = key.strip()
                fields[key] = value.strip()
        if fields:
            yield fields


def license_of(copyright_text):
    """Licenza principale da un copyright in formato DEP-5 (paragrafo "Files: *")."""
    for p in paragraphs(copyright_text):
        if p.get("Files", "").split() == ["*"] and p.get("License"):
            return p["License"].splitlines()[0].strip()
    return None


def main():
    tar_path, image_id, version, snap, variant = sys.argv[1:6]
    epoch = int(os.environ.get("SOURCE_DATE_EPOCH", "0"))
    digest = hashlib.sha256()
    with open(tar_path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            digest.update(chunk)

    with tarfile.open(tar_path) as tar:
        status = tar.extractfile("./var/lib/dpkg/status").read().decode()
        copyrights = {}
        for member in tar.getmembers():
            m = re.fullmatch(r"\./usr/share/doc/([^/]+)/copyright", member.name)
            if m and member.isfile():
                copyrights[m.group(1)] = tar.extractfile(member).read().decode("utf-8", "replace")

    components = []
    for p in paragraphs(status):
        # installati: anche quelli in hold (apt-mark hold), come il kernel della variante mutabile
        if p.get("Status") not in ("install ok installed", "hold ok installed"):
            continue
        name, ver, arch = p["Package"], p["Version"], p["Architecture"]
        source = p.get("Source", name)
        src_name, _, src_ver = source.partition(" ")
        src_ver = src_ver.strip("()") or ver
        comp = {
            "type": "library",
            "bom-ref": f"pkg:deb/debian/{name}@{ver}?arch={arch}",
            "name": name,
            "version": ver,
            "purl": f"pkg:deb/debian/{name}@{ver}?arch={arch}&distro=debian-13",
            "properties": [
                {"name": "debian:source", "value": src_name},
                {"name": "debian:source_version", "value": src_ver},
                {"name": "debian:architecture", "value": arch},
            ],
        }
        lic = license_of(copyrights.get(name, ""))
        if lic:
            comp["licenses"] = [{"license": {"name": lic}}]
        components.append(comp)
    components.sort(key=lambda c: c["bom-ref"])

    bom = {
        "bomFormat": "CycloneDX",
        "specVersion": "1.6",
        "serialNumber": "urn:uuid:" + str(uuid.uuid5(uuid.NAMESPACE_URL, "golden:" + digest.hexdigest())),
        "version": 1,
        "metadata": {
            "timestamp": datetime.datetime.fromtimestamp(epoch, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "component": {
                "type": "operating-system",
                "bom-ref": f"{image_id}@{version}",
                "name": image_id,
                "version": version,
                "hashes": [{"alg": "SHA-256", "content": digest.hexdigest()}],
            },
            "properties": [
                {"name": "golden:snapshot", "value": snap},
                {"name": "golden:variant", "value": variant},
                {"name": "golden:rootfs", "value": os.path.basename(tar_path)},
            ],
        },
        "components": components,
    }
    json.dump(bom, sys.stdout, indent=2, ensure_ascii=False, sort_keys=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
