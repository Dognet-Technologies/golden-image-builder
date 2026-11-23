#!/bin/sh
# sshd: il file principale di Debian accetta variabili d'ambiente dal client
# (AcceptEnv LANG LC_* ...). AcceptEnv è cumulativa: un drop-in non può toglierla.
set -eu
ROOT="$1"
sed -i -E 's/^(AcceptEnv\b.*)$/# golden: \1/' "${ROOT}/etc/ssh/sshd_config"
