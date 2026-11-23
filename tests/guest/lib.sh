# Funzioni comuni ai controlli eseguiti dentro la macchina (bash).
# Uso: cat tests/guest/lib.sh tests/guest/<controllo>.sh | tests/vm.sh ssh bash -s
FAILS=0
pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; FAILS=$((FAILS + 1)); }
check() {  # check "descrizione" comando...
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "${desc}"; else fail "${desc}"; fi
}
# A fine script: riepilogo e codice di uscita diverso da zero se qualcosa è fallito.
# Chi definisce una propria trap EXIT deve richiamare finish per ultimo.
finish() {
  echo "---- ${FAILS} controlli falliti"
  [ "${FAILS}" -eq 0 ] || exit 1
}
trap finish EXIT
