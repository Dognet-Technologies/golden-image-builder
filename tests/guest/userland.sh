# Controlli dell'articolo 4: setuid, SSH, firewall, PAM, AppArmor, audit, servizi

# 1. Binari setuid/setgid: solo quelli attesi
EXPECTED_SUID="${EXPECTED_SUID:-/usr/bin/ssh-agent /usr/lib/dbus-1.0/dbus-daemon-launch-helper /usr/sbin/unix_chkpwd}"
FOUND="$(find / -xdev -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null | sort | xargs)"
if [ "${FOUND}" = "${EXPECTED_SUID}" ]; then pass "setuid/setgid solo: ${FOUND}"; else fail "setuid/setgid: ${FOUND}"; fi

# 2. SSH: configurazione valida e valori effettivi
check "sshd -t: configurazione valida" sshd -t
SSHD_T="$(sshd -T 2>/dev/null)"
for kv in "permitrootlogin without-password" "passwordauthentication no" \
          "kbdinteractiveauthentication no" "authenticationmethods publickey" \
          "loglevel VERBOSE" "maxauthtries 3" \
          "hostkeyalgorithms ssh-ed25519" \
          "kexalgorithms mlkem768x25519-sha256,sntrup761x25519-sha512,curve25519-sha256"; do
  check "sshd: ${kv}" grep -qix "${kv}" <<<"${SSHD_T}"
done
# Inoltri chiusi, salvo i profili che li dichiarano (bastion: SSHD_FORWARDING=local)
if [ "${SSHD_FORWARDING:-none}" = none ]; then
  check "sshd: disableforwarding yes" grep -qix "disableforwarding yes" <<<"${SSHD_T}"
else
  check "sshd: allowtcpforwarding ${SSHD_FORWARDING}" grep -qix "allowtcpforwarding ${SSHD_FORWARDING}" <<<"${SSHD_T}"
fi
check "sshd: nessuna variabile accettata dal client (AcceptEnv)" bash -c '! grep -qi "^acceptenv" <<<"$0"' "${SSHD_T}"
HOSTKEYS="$(grep -i '^hostkey ' <<<"${SSHD_T}" | awk '{print $2}' | xargs)"
case "${HOSTKEYS}" in
  *" "*|"") fail "chiavi host: ${HOSTKEYS:-nessuna}" ;;
  *ed25519_key) check "una sola chiave host, ed25519 (${HOSTKEYS})" test -s "${HOSTKEYS}" ;;
  *) fail "chiave host non ed25519: ${HOSTKEYS}" ;;
esac

# 3. Porte in ascolto sulla rete: solo quelle del profilo (EXPECTED_LISTEN), più
#    il client DHCP; localhost escluso
LISTEN="$(ss -Htuln | awk '{print $1":"$5}' | grep -vE ':(127\.|\[::1\])' | sed -E 's/:.*:/:/' | grep -vx 'udp:68' | sort -u | xargs)"
WANT="$(tr ' ' '\n' <<<"${EXPECTED_LISTEN:-tcp:22}" | sort -u | xargs)"
if [ "${LISTEN}" = "${WANT}" ]; then pass "in ascolto solo: ${LISTEN}"; else fail "in ascolto: ${LISTEN} (atteso ${WANT})"; fi

# 4. Firewall caricato con policy drop in ingresso
check "nftables attivo" systemctl is-active --quiet nftables
check "input policy drop" bash -c 'nft list chain inet filter input | grep -q "policy drop"'
check "forward policy drop" bash -c 'nft list chain inet filter forward | grep -q "policy drop"'

# 5. PAM: niente pam_motd/pam_mail, pam_loginuid presente (serve all'audit)
check "pam_motd disattivato in sshd" bash -c '! grep -qE "^session.*pam_motd" /etc/pam.d/sshd'
check "pam_loginuid attivo in sshd" grep -qE '^session\s+required\s+pam_loginuid.so' /etc/pam.d/sshd

# 6. AppArmor
check "AppArmor abilitato" bash -c '[ "$(cat /sys/module/apparmor/parameters/enabled)" = Y ]'
echo "INFO  profili AppArmor caricati: $(grep -c . /sys/kernel/security/apparmor/profiles 2>/dev/null || echo 0)"

# 7. Audit: attivo, regole caricate, immutabili, auid della sessione impostato
check "auditd attivo" systemctl is-active --quiet auditd
check "regole di audit immutabili (enabled 2)" bash -c 'auditctl -s | grep -q "^enabled 2"'
check "regola exec caricata" bash -c 'auditctl -l | grep -q "key=exec"'
check "auid della sessione impostato" bash -c '[ "$(cat /proc/self/loginuid)" != 4294967295 ]'

# 8. Nessun servizio fallito, nessun core dump su disco
check "nessuna unit fallita" bash -c '[ -z "$(systemctl --failed --no-legend)" ]'
check "core dump scartati" bash -c '[ "$(cat /proc/sys/kernel/core_pattern)" = "|/bin/false" ]'

# 9. Esposizione dei servizi in esecuzione (systemd-analyze security): informativo
echo "INFO  esposizione dei servizi (0 = isolato, 10 = nessun isolamento):"
systemd-analyze security --no-pager 2>/dev/null | awk 'NR>1 && $2 ~ /^[0-9.]+$/ {printf "INFO    %-40s %s %s\n", $1, $2, $3}'

# 10. Proprietari dei file di sistema: nessun file di utenti inesistenti o >= 1000
#     (OWNER_EXCLUDE: percorsi legittimi del profilo, es. lo storage di Podman rootless,
#     i cui file appartengono per costruzione agli UID subordinati)
PRUNE=()
for d in ${OWNER_EXCLUDE:-}; do PRUNE+=(-path "${d}" -prune -o); done
BAD="$(find / -xdev "${PRUNE[@]}" \( -nouser -o -nogroup -o -uid +999 \) -print -quit 2>/dev/null)"
if [ -z "${BAD}" ]; then pass "nessun file senza proprietario o con uid >= 1000"; else fail "file con proprietario anomalo: ${BAD}"; fi
