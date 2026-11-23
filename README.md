# golden-image-builder

*Minimal, hardened, reproducible and verifiable Debian 13 golden images, with a full verification pipeline. Documentation is in Italian.*

Costruisce golden image **Debian 13 «trixie»** minimali e hardenizzate per quattro profili (web, database, container host, bastion), in due varianti:

- **mutabile**: root scrivibile, aggiornamenti di sicurezza automatici dello userland;
- **immutabile**: root in sola lettura protetta da dm-verity, aggiornamenti A/B con `systemd-sysupdate` e ritorno automatico alla versione precedente.

Ogni immagine è riproducibile bit per bit, avviabile con Secure Boot e chiavi proprie, accompagnata da SBOM, rapporto delle vulnerabilità e manifest firmato, e verificata da una pipeline che la avvia in una macchina virtuale.

È il codice della serie di articoli **«Golden image Debian 13 per tecnici»** di Dognet Technologies, dove ogni scelta è spiegata e ogni affermazione verificata.

## Requisiti sull'host

- Debian 13 o derivata, con `mmdebstrap`.
- Per lavorare senza root: `uidmap`, user namespace non privilegiati attivi e un intervallo di UID subordinati per il tuo utente in `/etc/subuid` e `/etc/subgid` (su Debian viene creato con l'utente). In alternativa, gli script di build accettano `sudo`.
- Per le prove in macchina virtuale: `qemu-system-x86`, `ovmf`, `openssh-client`, `socat`, `mtools`, e accesso a `/dev/kvm` (gruppo `kvm`).
- `openssl`, `curl`, `python3` (solo libreria standard).

```bash
sudo apt install mmdebstrap uidmap qemu-system-x86 ovmf openssh-client socat mtools openssl curl python3
```

Tutti gli altri strumenti (systemd-repart, ukify, sbsign, erofs-utils, gpg...) arrivano da un chroot costruito con lo **stesso snapshot** Debian dell'immagine (`./tools.sh`): il risultato non dipende dalle versioni installate sull'host.

## Guida rapida

```bash
# 1. Strumenti di build, dallo snapshot (una volta per snapshot)
./tools.sh

# 2. Chiavi: Secure Boot (PK, KEK, db) e firma degli aggiornamenti (una volta).
#    Vanno FUORI dal repository; in produzione su una macchina dedicata o in un HSM.
make keys KEYS=~/golden-keys

# 3. Un'immagine: profilo web, variante mutabile
make image PROFILE=web VARIANT=mutable KEYS=~/golden-keys

# 4. Prova in una macchina virtuale: accesso con una chiave SSH e certificato TLS
#    di prova, entrambi passati come credential (nessun segreto nell'immagine)
make test-creds
CREDS="golden.tls.crt=out/vm/tls.crt golden.tls.key=out/vm/tls.key" \
  tests/vm.sh start out/disk-web-mutable.raw
tests/run-guest.sh web
tests/vm.sh stop

# 5. Tutto: 4 profili x 2 varianti, firmate, avviate con Secure Boot e verificate
make test-all KEYS=~/golden-keys
```

I profili web e db usano un certificato TLS passato come credential; il bastion una chiave WireGuard, i peer e gli indirizzi di amministrazione. Per le prove li genera `make test-creds` (`tools/test-creds.sh`), e `tests/guest/profiles/<profilo>.creds` dice quali file passare a ogni profilo.

I risultati finiscono in `out/`: rootfs, dischi, SBOM (`out/sbom-*.cdx.json`), rapporti delle vulnerabilità, rilasci firmati (`out/release/`) e un rapporto per immagine (`out/reports/<profilo>-<variante>/REPORT.md`).

## Struttura

| Percorso | Contenuto |
| --- | --- |
| `build.sh` | rootfs come archivio tar riproducibile (mmdebstrap) |
| `tools.sh`, `tools/packages.txt` | chroot degli strumenti di build dallo stesso snapshot |
| `image.sh`, `image/mkdisk.sh` | disco GPT: UKI, systemd-boot, Secure Boot, dm-verity, A/B |
| `lib/` | variabili comuni, chroot degli strumenti, SBOM, confronto versioni Debian, scansione |
| `common/` | livello comune: pacchetti, overlay, hook, riga di comando del kernel |
| `profiles/<profilo>/` | web, db, container, bastion; con l'allow-list dei pacchetti per variante |
| `variants/<variante>/` | mutable, immutable |
| `repart.d/` | partizioni (systemd-repart) |
| `tools/` | chiavi, aggiornamenti, SBOM, vulnerabilità, rilasci, verifica delle firme |
| `tests/` | controlli statici, VM di prova, suite nella VM, A/B, drift, lynis, pipeline completa |
| `docs/` | politica di patch (SLA), mappatura ISO/IEC 27001 e NIS2 |

## Gli articoli

| # | Articolo | Cosa trovi nel codice |
| --- | --- | --- |
| 1 | Metodo, threat model e architettura | `build.sh` (prima versione), `common/` |
| 2 | Build riproducibile, da archivio a disco avviabile | `tools.sh`, `lib/`, `image.sh`, `image/mkdisk.sh`, `repart.d/`, `tools/sb-keys.sh`, `tests/vm.sh` |
| 3 | Kernel e boot hardening | `common/cmdline`, `sysctl.d`, `modprobe.d`, `tests/guest/kernel.sh` |
| 4 | Userland minimale | hook di setuid, PAM, SSH, audit; nftables; allow-list; `tests/guest/userland.sh` |
| 5 | Immutabilità e aggiornamenti | `variants/`, dm-verity e A/B in `mkdisk.sh`, `tools/update-key.sh`, `tools/publish.sh`, `tests/ab-update.sh` |
| 6 | Profili I: web e database | `profiles/web`, `profiles/db` |
| 7 | Profili II: container host e bastion | `profiles/container`, `profiles/bastion` |
| 8 | Supply chain e gestione delle vulnerabilità | `lib/sbom.py`, `lib/debver.py`, `lib/vulnscan.py`, `tools/release.sh`, `tools/verify-*.sh`, `docs/sla.md` |
| 9 | Verifica e conformità | `tests/run-all.sh`, `tests/drift.sh`, `tests/lynis.sh`, `tools/report.sh`, `docs/conformita.md` |

## Prima di usarlo in produzione

- **Snapshot.** `lib/env.sh` fissa lo snapshot `20261117T000000Z`. Le allow-list in `profiles/*/packages-*.lock` valgono per quello snapshot: cambiandolo, rigenerale con `tests/check-packages.sh <profilo> --update` e rivedi le differenze.
- **Chiavi.** Le chiavi generate da `make keys` sono adatte alle prove. In produzione: chiavi custodite fuori dalle macchine di build ordinarie, registrazione in Secure Boot dal firmware o dagli strumenti di gestione, non con l'enrollment automatico (`ENROLL=1`, pensato per le VM di prova).
- **Aggiornamenti.** `UPDATE_URL` in `lib/env.sh` punta all'host visto da una VM QEMU (`10.0.2.2`): va impostato sul tuo server di distribuzione.
- **Container.** Il quadlet d'esempio scarica `alpine` da Docker Hub: in produzione usa un registry proprio, nomi con digest e una politica delle firme.
- **Log.** Audit e journal restano sulla macchina: l'inoltro a un sistema centrale dipende dalla tua infrastruttura.

## Licenza

[MIT](LICENSE). Copyright (c) 2026 Dognet Technologies Srl.

Il software è fornito «così com'è», senza garanzie. Per immagini costruite, verificate e mantenute per il tuo carico di lavoro, con tempi di intervento concordati, contatta Dognet Technologies.
