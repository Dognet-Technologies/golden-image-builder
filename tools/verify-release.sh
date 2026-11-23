#!/usr/bin/env bash
# Verifica un rilascio (articolo 8): firma del manifest con la chiave pubblica
# indicata (ottenuta per un canale fidato, NON quella dentro il rilascio) e hash.
# In trixie gpgv non è installato di default (APT 3 verifica con sqv): usiamo gpg
# con un keyring esplicito e una home temporanea.
#   tools/verify-release.sh <directory-rilascio> <chiave-pubblica.gpg>
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/env.sh
REL="$(realpath "${1:?directory del rilascio}")"; PUB="$(realpath "${2:?chiave pubblica fidata}")"
WORK="$(mktemp -d "${TMPDIR:-/var/tmp}/golden-verify.XXXXXX")"
trap 'as_root rm -rf "${WORK}"' EXIT
as_root lib/chroot.sh "${PWD}" "${WORK}" "${REL}:/rel:ro" "$(dirname "${PUB}"):/pub:ro" -- \
  /bin/bash -euo pipefail -s "/pub/$(basename "${PUB}")" <<'INNER'
cd /rel
install -d -m 0700 /work/gnupg
gpg --batch --quiet --homedir /work/gnupg --no-default-keyring --keyring "$1" \
    --verify SHA256SUMS.gpg SHA256SUMS
sha256sum --strict -c SHA256SUMS
INNER
