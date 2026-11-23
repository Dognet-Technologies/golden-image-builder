# Controlli del profilo web (articolo 6)
http_get() {  # http_get <percorso>: risposta grezza di nginx su 127.0.0.1:80
  exec 3<>/dev/tcp/127.0.0.1/80
  printf 'GET %s HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n' "$1" >&3
  timeout 5 cat <&3; exec 3<&-
}
check "nginx attivo" systemctl is-active --quiet nginx
RESP="$(http_get /)"
check "HTTP 200 sulla porta 80" grep -q '^HTTP/1.1 200' <<<"${RESP}"
check "versione di nginx non esposta" bash -c '! grep -qiE "^Server: nginx/[0-9]" <<<"$0"' "${RESP}"
check "intestazione X-Content-Type-Options" grep -qi '^X-Content-Type-Options: nosniff' <<<"${RESP}"
check "file nascosti negati (/.git)" grep -q '^HTTP/1.1 403' <<<"$(http_get /.git/config)"
check "HTTPS abilitato dal certificato in credential" test -s /run/nginx-golden/tls.conf
check "chiave TLS non sul disco" bash -c '! find /etc /var -name "*.key" -path "*nginx*" | grep -q .'
check "worker come www-data" bash -c '[ "$(ps -o user= -C nginx | sort -u | xargs)" = "root www-data" ]'
check "AppArmor: nginx in enforce" bash -c 'ps -eo label,comm | grep -E "^nginx \(enforce\) +nginx$" | grep -q .'
EXPO="$(systemd-analyze security nginx.service --no-pager 2>/dev/null | grep -oP 'Overall exposure level for \S+: \K[0-9.]+')"
echo "INFO  esposizione di nginx.service: ${EXPO}"
check "esposizione di nginx.service <= 5.0" awk -v e="${EXPO}" 'BEGIN { exit !(e <= 5.0) }'
# Campo strutturato del journal: un grep sul testo troverebbe il record di audit
# EXECVE del grep stesso (la regola "exec" registra gli argomenti dei comandi)
check "nessun processo ucciso da seccomp (SIGSYS)" test -z "$(journalctl -b -q --no-pager _AUDIT_TYPE=1326)"
check "nessun DENIED di AppArmor nel journal" bash -c '! journalctl -k -b --no-pager | grep -q "apparmor=\"DENIED\""'
