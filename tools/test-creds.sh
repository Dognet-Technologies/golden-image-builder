#!/usr/bin/env bash
# Credential di PROVA per le VM di test (articoli 6 e 7), in out/vm/:
#  - certificato TLS autofirmato per localhost (profili web e db);
#  - chiavi WireGuard del bastion e di un client, file dei peer;
#  - indirizzo di amministrazione del bastion: 10.0.2.2, l'host visto da QEMU.
# Non usarle fuori dai test. I file esistenti non vengono sovrascritti.
set -euo pipefail
cd "$(dirname "$0")/.."
D=out/vm
mkdir -p "${D}"
umask 077

if [ ! -s "${D}/tls.key" ]; then
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 30 \
    -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost" \
    -keyout "${D}/tls.key" -out "${D}/tls.crt" 2>/dev/null
fi

# Chiave X25519: WireGuard usa i 32 byte grezzi, in base64
wgkey() {
  openssl genpkey -algorithm X25519 -out "${D}/$1.pem" 2>/dev/null
  openssl pkey -in "${D}/$1.pem" -outform DER | tail -c 32 | base64 > "${D}/$1.key"
  openssl pkey -in "${D}/$1.pem" -pubout -outform DER | tail -c 32 | base64 > "${D}/$1.pub"
  rm -f "${D}/$1.pem"
}
if [ ! -s "${D}/wg-server.key" ]; then
  wgkey wg-server
  wgkey wg-client
  printf '[WireGuardPeer]\nPublicKey=%s\nAllowedIPs=10.99.0.2/32\n' "$(cat "${D}/wg-client.pub")" > "${D}/wg-peers.conf"
  printf '10.0.2.2/32\n' > "${D}/bastion-admin"
fi
ls -l "${D}"
