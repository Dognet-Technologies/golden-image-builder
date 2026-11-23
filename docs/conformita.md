# Mappatura dei controlli (articolo 9)

La baseline **contribuisce** ai controlli elencati: la conformità riguarda
l'organizzazione intera (processi, persone, fornitori) e non si ottiene con
un'immagine. Per ogni voce: cosa fa l'immagine e dove si verifica.

## ISO/IEC 27001:2022, Annex A

| Controllo | Contributo della baseline | Evidenza |
| --- | --- | --- |
| 5.9 Inventario degli asset | SBOM CycloneDX per ogni immagine; allow-list dei pacchetti | `tools/sbom.sh`, `tests/check-packages.sh` |
| 5.21 Sicurezza nella supply chain ICT | Pacchetti da snapshot fissato e firmato; strumenti di build dallo stesso snapshot; build riproducibile | `build.sh`, `tools.sh`, confronto degli hash |
| 8.2 Diritti di accesso privilegiati | Solo chiavi SSH, nessuna password, setuid ridotti a 3, comandi delle sessioni registrati da auditd | `tests/guest/userland.sh` |
| 8.3 Limitazione degli accessi alle informazioni | AppArmor in enforce sui servizi, sandboxing systemd, firewall con policy drop | `tests/guest/profiles/*.sh` |
| 8.5 Autenticazione sicura | SSH solo a chiave pubblica, algoritmi moderni (KEX ibrido post-quantistico) | `sshd -T` nei test |
| 8.7 Protezione dal malware | Secure Boot con chiavi proprie, lockdown, moduli firmati, root dm-verity (immutabile) | test Secure Boot, `tests/ab-update.sh` |
| 8.8 Gestione delle vulnerabilità tecniche | Scansione con il Debian Security Tracker, SLA di patch, ricostruzione periodica | `tools/vulnscan.sh`, `docs/sla.md` |
| 8.9 Gestione della configurazione | Configurazione definita in build; drift detection | `tests/drift.sh` |
| 8.15 Logging | auditd con regole immutabili, journal, log SSH con l'impronta della chiave | `tests/guest/userland.sh` |
| 8.16 Monitoraggio | Regole di audit su identità, configurazione, moduli, comandi (inoltro centralizzato da aggiungere) | `/etc/audit/rules.d` |
| 8.17 Sincronizzazione degli orologi | systemd-timesyncd attivo | test servizi |
| 8.19 Installazione di software | Variante immutabile: niente installazioni sulla macchina; mutabile: solo aggiornamenti di sicurezza | variante immutabile |
| 8.20 Sicurezza delle reti | nftables con policy drop in ingresso e sul forward | `tests/guest/userland.sh` |
| 8.21 Sicurezza dei servizi di rete | nginx e PostgreSQL con TLS da credential, header di sicurezza, scram-sha-256 | profili web e db |
| 8.22 Segregazione delle reti | Bastion con WireGuard; database aperto solo ai client autorizzati | profili bastion e db |
| 8.24 Uso della crittografia | TLS 1.2+, SSH moderno, firma Secure Boot, dm-verity, manifest firmati | `tools/verify-release.sh` |
| 8.27 Principi di architettura sicura | Superficie minima, difesa in profondità, threat model documentato | articolo 1 |
| 8.29 Test di sicurezza | Suite automatica, lynis, controlli statici a ogni build | `tests/run-all.sh` |
| 8.32 Gestione dei cambiamenti | Immagini versionate e firmate, A/B con rollback automatico | `tests/ab-update.sh` |

## NIS2, articolo 21, paragrafo 2

| Lettera | Misura | Contributo della baseline |
| --- | --- | --- |
| a | Analisi dei rischi e politiche di sicurezza | Threat model e scelte di progetto documentate |
| b | Gestione degli incidenti | Audit e log locali pronti per l'inoltro a un SIEM |
| c | Continuità operativa | Ricostruzione riproducibile, A/B con rollback (i backup dei dati restano fuori dall'immagine) |
| d | Sicurezza della catena di approvvigionamento | Snapshot, SBOM, firma e verifica degli artefatti |
| e | Sicurezza nello sviluppo e nella manutenzione, gestione delle vulnerabilità | Scansione, SLA, test automatici |
| f | Valutazione dell'efficacia delle misure | Rapporto per immagine con esito dei test e audit lynis |
| g | Igiene informatica di base | Hardening di kernel, servizi, rete (la formazione è fuori ambito) |
| h | Crittografia | Algoritmi e chiavi definiti; nessuna chiave nell'immagine |
| i | Controllo degli accessi e gestione degli asset | Accesso solo a chiave, inventario via SBOM |
| j | Autenticazione forte e comunicazioni protette | Chiavi SSH (anche FIDO2 `sk-ssh-ed25519`), TLS, WireGuard |
