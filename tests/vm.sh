#!/usr/bin/env bash
# VM di test in QEMU/KVM. Il disco originale non viene modificato: si lavora
# su un overlay qcow2. L'accesso è con una chiave SSH passata come credential
# di systemd (SMBIOS tipo 11): nell'immagine non c'è nessuna identità.
#
#   tests/vm.sh start <disco.raw> [secureboot]   avvia la VM in background
#   tests/vm.sh ssh [comando...]                 comando (o shell) come root
#   tests/vm.sh reboot                           riavvia e attende SSH
#   tests/vm.sh stop                             spegne la VM
#   tests/vm.sh console                          mostra il log della console seriale
set -euo pipefail
cd "$(dirname "$0")/.."

VM=out/vm
PORT="${SSH_PORT:-2222}"
KEY="${VM}/id_ed25519"
OVMF=/usr/share/OVMF

ssh_vm() {
  ssh -i "${KEY}" -p "${PORT}" -o BatchMode=yes -o ConnectTimeout=5 \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile="${VM}/known_hosts" \
      -o LogLevel=ERROR root@127.0.0.1 "$@"
}

start() {
  local disk="${1:?disco mancante}" mode="${2:-}" code vars machine extra=()
  [ -f "${disk}" ] || { echo "Disco non trovato: ${disk}" >&2; exit 1; }
  mkdir -p "${VM}"
  [ -f "${KEY}" ] || ssh-keygen -q -t ed25519 -N '' -C golden-test -f "${KEY}"
  rm -f "${VM}/known_hosts" "${VM}/console.log"

  qemu-img create -q -f qcow2 -F raw -b "$(realpath "${disk}")" "${VM}/disk.qcow2"
  machine="q35,accel=kvm"
  if [ "${mode}" = secureboot ]; then
    code="${OVMF}/OVMF_CODE_4M.secboot.fd"
    machine="${machine},smm=on"
    extra=(-global driver=cfi.pflash01,property=secure,value=on)
  else
    code="${OVMF}/OVMF_CODE_4M.fd"
  fi
  # Credential aggiuntive: CREDS="nome=file nome=file ..." (es. certificato TLS)
  local c creds=()
  for c in ${CREDS:-}; do
    case "${c}" in *=*) ;; *) continue ;; esac     # solo voci nome=file
    creds+=(-smbios "type=11,value=io.systemd.credential.binary:${c%%=*}=$(base64 -w0 "${c#*=}")")
  done

  # Variabili UEFI: vuote (setup mode, nessuna chiave) o da un file (VARS=...),
  # per esempio quelle di una VM in cui le chiavi sono già state registrate
  command cp -f "${VARS:-${OVMF}/OVMF_VARS_4M.fd}" "${VM}/vars.fd"

  qemu-system-x86_64 -machine "${machine}" -cpu host -smp 2 -m 2048 \
    -uuid "${VM_UUID:-5b0c6f2e-9d41-4a7e-8f3a-2c1d0e9b7a65}" \
    "${extra[@]}" \
    -drive if=pflash,format=raw,unit=0,readonly=on,file="${code}" \
    -drive if=pflash,format=raw,unit=1,file="${VM}/vars.fd" \
    -drive file="${VM}/disk.qcow2",if=virtio,format=qcow2 \
    -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:"${PORT}"-:22,hostfwd=tcp:127.0.0.1:18080-:80,hostfwd=tcp:127.0.0.1:18443-:443 \
    -smbios type=11,value=io.systemd.credential.binary:ssh.authorized_keys.root="$(base64 -w0 "${KEY}.pub")" \
    "${creds[@]}" \
    -display none -serial file:"${VM}/console.log" \
    -monitor unix:"${VM}/monitor.sock",server,nowait \
    -pidfile "${VM}/qemu.pid" -daemonize

  # Attesa di SSH (il primo avvio genera le chiavi host, l'enrollment riavvia)
  wait_ssh
}

wait_ssh() {
  local i
  for i in $(seq 1 "${WAIT:-90}"); do
    if ssh_vm true 2>/dev/null; then echo "VM pronta (${i}x2s)"; return 0; fi
    sleep 2
  done
  echo "SSH non raggiungibile: vedi ${VM}/console.log" >&2
  return 1
}

reboot_vm() {
  ssh_vm systemctl reboot 2>/dev/null || true
  sleep 5
  wait_ssh
}

stop() {
  [ -S "${VM}/monitor.sock" ] || return 0
  ssh_vm systemctl poweroff 2>/dev/null || true
  local i
  for i in $(seq 1 30); do
    [ -f "${VM}/qemu.pid" ] && kill -0 "$(cat "${VM}/qemu.pid")" 2>/dev/null || break
    sleep 1
  done
  if [ -f "${VM}/qemu.pid" ] && kill -0 "$(cat "${VM}/qemu.pid")" 2>/dev/null; then
    echo quit | socat - UNIX-CONNECT:"${VM}/monitor.sock" >/dev/null 2>&1 || kill "$(cat "${VM}/qemu.pid")"
  fi
  rm -f "${VM}/monitor.sock" "${VM}/qemu.pid"
}

case "${1:-}" in
  start)   shift; start "$@" ;;
  ssh)     shift; ssh_vm "$@" ;;
  stop)    stop ;;
  reboot)  reboot_vm ;;
  console) cat "${VM}/console.log" ;;
  *) sed -n '2,10p' "$0"; exit 1 ;;
esac
