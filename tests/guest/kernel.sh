# Controlli dell'articolo 3: riga di comando, sysctl, lockdown, moduli

# 1. Ogni parametro di hardening è nella riga di comando effettiva
for p in rd.shell=0 rd.emergency=reboot rd.timeout=90 panic=10 init_on_free=1 slab_nomerge \
         page_alloc.shuffle=1 ia32_emulation=0 debugfs=off lockdown=integrity \
         module.sig_enforce=1 iommu.strict=1 iommu.passthrough=0; do
  check "cmdline contiene ${p}" grep -qw -- "${p}" /proc/cmdline
done

# 2. I valori di /etc/sysctl.d/90-golden.conf sono quelli attivi. Un file successivo
#    (es. 91-container.conf di un profilo) può ridefinire una chiave: vale l'ultimo.
last_value() {  # last_value <chiave>: valore nell'ultimo file di /etc/sysctl.d che la imposta
  cat /etc/sysctl.d/*.conf | sed 's/#.*//' | awk -F= -v k="$1" '{g=$1; gsub(/[ -]/,"",g)} g==k {v=$2} END {print v}' | xargs
}
while IFS= read -r line; do
  line="${line%%#*}"
  [ -n "${line// /}" ] || continue
  key="${line%%=*}"; key="${key// /}"; key="${key#-}"
  want="$(last_value "${key}")"
  f="/proc/sys/${key//.//}"
  if [ ! -e "${f}" ]; then
    case "${line}" in -*) pass "sysctl ${key} assente (opzionale)";; *) fail "sysctl ${key} assente";; esac
    continue
  fi
  have="$(xargs < "${f}")"
  if [ "${have}" = "${want}" ]; then pass "sysctl ${key} = ${want}"; else fail "sysctl ${key} = ${have} (atteso ${want})"; fi
done < /etc/sysctl.d/90-golden.conf

# 3. Lockdown attivo almeno in modalità integrity
check "lockdown integrity attivo" grep -qE '\[(integrity|confidentiality)\]' /sys/kernel/security/lockdown

# 4. debugfs non montabile
check "debugfs non montato" bash -c '! grep -qw debugfs /proc/mounts'

# 5. Moduli bloccati: il caricamento deve fallire
for m in sctp dccp bluetooth uas udf; do
  check "modulo ${m} non caricabile" bash -c "! modprobe ${m}"
done
