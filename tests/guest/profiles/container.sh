# Controlli del profilo container (articolo 7)
U="$(id -u podman)"
# Da / (la directory corrente di root non è accessibile a podman) e con il bus della
# sessione utente: senza, podman ripiega su cgroupfs e "exec" non entra nel container
as_podman() {
  (cd / && runuser -u podman -- env XDG_RUNTIME_DIR="/run/user/${U}" \
     DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${U}/bus" "$@")
}
check "utente podman con subuid" grep -q '^podman:524288:65536$' /etc/subuid
check "user manager di podman attivo (lingering)" systemctl is-active --quiet "user@${U}.service"
check "podman in modalità rootless" test "$(as_podman podman info --format '{{.Host.Security.Rootless}}')" = true
# Il primo avvio del quadlet scarica l'immagine: attendiamo fino a 120 s
for i in $(seq 1 60); do
  as_podman systemctl --user is-active --quiet hello.service && break; sleep 2
done
check "container quadlet attivo" as_podman systemctl --user is-active --quiet hello.service
MAP="$(as_podman podman exec systemd-hello cat /proc/self/uid_map | awk 'NR==1 {print $2}')"
check "root nel container = UID non privilegiato sull'host (${MAP})" test "${MAP}" = "${U}"
check "processo del container di proprietà di podman" bash -c '[ "$(ps -o user= -C sleep | sort -u | xargs)" = podman ]'
OUT="$(as_podman podman exec systemd-hello touch /x 2>&1 || true)"
if grep -q "Read-only file system" <<<"${OUT}"; then
  pass "filesystem del container in sola lettura"; else fail "touch nel container: ${OUT:-riuscito}"; fi
check "user namespace aperti solo in questo profilo" test "$(cat /proc/sys/kernel/unprivileged_userns_clone)" = 1
