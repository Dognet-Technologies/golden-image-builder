# Controlli del profilo bastion (articolo 7)
check "interfaccia wg0 di tipo wireguard" bash -c 'ip -d link show wg0 | grep -qw wireguard'
check "wg0 configurata con 10.99.0.1/24" bash -c 'ip -4 addr show wg0 | grep -q "10.99.0.1/24"'
check "peer WireGuard da credential" test -s /run/systemd/network/50-wg0.netdev.d/50-peers.conf
check "nessuna chiave WireGuard sul disco" bash -c '! grep -rqi "^PrivateKey" /etc/systemd/network'
check "firewall: 22 non aperta a tutti" bash -c '! nft list set inet filter tcp_in | grep -qw 22'
check "firewall: 51820/udp aperta" bash -c 'nft list set inet filter udp_in | grep -qw 51820'
check "firewall: SSH ammesso dal tunnel" bash -c 'nft list chain inet filter profile_in | grep -q "iifname \"wg0\" tcp dport 22 accept"'
check "amministrazione da credential (admin4)" bash -c 'nft list set inet filter admin4 | grep -q "10.0.2.2"'
check "sshd: solo inoltro TCP locale (ProxyJump)" bash -c 'sshd -T | grep -qix "allowtcpforwarding local"'
check "sshd: niente inoltro dell'agent" bash -c 'sshd -T | grep -qix "allowagentforwarding no"'
