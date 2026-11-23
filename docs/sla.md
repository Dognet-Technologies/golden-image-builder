# Gestione delle vulnerabilità e SLA di patch (articolo 8)

Proposta di politica, da adattare al contesto. I tempi decorrono dalla
disponibilità della correzione in Debian (campo `fixed_version` del Debian
Security Tracker), non dalla pubblicazione della CVE.

## Rilevazione

- `tools/vulnscan.sh` incrocia ogni giorno la SBOM di ogni immagine in produzione
  con il Debian Security Tracker.
- Una vulnerabilità «correggibile» significa: esiste una versione corretta più recente di
  quella nell'immagine. Si risolve con una nuova immagine costruita da uno snapshot più recente.
- Le vulnerabilità senza correzione in trixie («open») si valutano caso per caso:
  componente raggiungibile? mitigazioni presenti (sandbox, AppArmor, firewall)?

## Tempi di intervento

| Classe | Criterio | Nuova immagine pubblicata entro |
| --- | --- | --- |
| Emergenza | sfruttata attivamente (es. nel catalogo CISA KEV) o RCE senza autenticazione su un servizio esposto | 24-72 ore |
| Alta | urgenza «high» nel tracker, o CVSS ≥ 7 su un componente raggiungibile | 7 giorni |
| Media | urgenza «medium», o CVSS 4-6.9 | 30 giorni |
| Bassa | il resto | prossima ricostruzione pianificata |

Ricostruzione pianificata: settimanale, con lo snapshot del giorno, anche senza CVE.

## Rilascio

1. Build e verifica completa (`tests/run-all.sh`): nessun rilascio con controlli falliti.
2. Rilascio firmato (`tools/release.sh`) e pubblicazione degli aggiornamenti (`tools/publish.sh`).
3. Distribuzione graduale: prima un gruppo «canary», poi il resto. Nella variante immutabile
   `systemd-sysupdate` installa nello slot libero e il rollback è automatico se l'avvio fallisce.
4. Variante mutabile: `unattended-upgrades` applica ogni giorno le correzioni di sicurezza
   dello userland; kernel e bootloader arrivano solo con una nuova immagine.

## Evidenze per l'audit

Per ogni rilascio restano: SBOM, rapporto vulnerabilità, log dei test, rapporto
(`out/reports/<profilo>-<variante>/REPORT.md`) e manifest firmato.
