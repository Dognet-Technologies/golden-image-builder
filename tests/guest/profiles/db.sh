# Controlli del profilo db (articolo 6)
psql_q() { runuser -u postgres -- psql -XAtqc "$1"; }
check "cluster creato al primo avvio" test -f /var/lib/postgresql/17/main/PG_VERSION
check "PostgreSQL attivo" systemctl is-active --quiet postgresql@17-main
check "data checksums attivi" test "$(psql_q 'show data_checksums')" = on
check "TLS attivo (certificato da credential)" test "$(psql_q 'show ssl')" = on
check "password_encryption scram-sha-256" test "$(psql_q 'show password_encryption')" = scram-sha-256
check "pg_hba: niente host in chiaro né trust" bash -c '! grep -vE "^\s*(#|$)" /etc/postgresql/17/main/pg_hba.conf | grep -qE "^(host|local)\s.*\btrust\b|^host\s"'
check "nessuna chiave snakeoil" test ! -e /etc/ssl/private/ssl-cert-snakeoil.key
check "5432 non aperta nel firewall per default" bash -c 'nft list set inet filter db_clients4 | grep -q "elements" && exit 1 || exit 0'
EXPO="$(systemd-analyze security postgresql@17-main.service --no-pager 2>/dev/null | grep -oP 'Overall exposure level for \S+: \K[0-9.]+')"
echo "INFO  esposizione di postgresql@17-main.service: ${EXPO}"
# Campo strutturato del journal: un grep sul testo troverebbe il record di audit
# EXECVE del grep stesso (la regola "exec" registra gli argomenti dei comandi)
check "nessun processo ucciso da seccomp (SIGSYS)" test -z "$(journalctl -b -q --no-pager _AUDIT_TYPE=1326)"
check "AppArmor: postgres in enforce" bash -c 'ps -eo label,comm | grep -qE "^postgresql \(enforce\) +postgres$"'
check "nessun processo postgres fuori profilo" bash -c '! ps -eo label,comm | grep -E " postgres$" | grep -vq "^postgresql (enforce)"'
# Carico reale: ruolo, database, tabella, indice, connessione TCP con TLS, checkpoint
export LC_ALL=C.UTF-8
(cd / && runuser -u postgres -- psql -Xq -c "create role golden_test login password 'Prova-123!'" -c "create database golden_test owner golden_test") >/dev/null 2>&1
N="$(cd / && PGPASSWORD='Prova-123!' psql -XqAt "host=127.0.0.1 dbname=golden_test user=golden_test sslmode=require" \
     -c "create table t(id serial primary key, v text); insert into t(v) select md5(i::text) from generate_series(1,5000) i; create index on t(v); select count(*) from t" 2>&1)"
check "carico reale su TCP con TLS (5000 righe)" test "${N}" = 5000
check "checkpoint e vacuum" bash -c 'cd / && runuser -u postgres -- psql -Xq -c checkpoint -c "vacuum analyze" >/dev/null'
check "nessun DENIED di AppArmor" bash -c '! grep -q "apparmor=\"DENIED\"" /var/log/audit/audit.log'
