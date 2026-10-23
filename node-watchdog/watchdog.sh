#!/bin/bash
#
# node-watchdog — houdt de nodes en pools op de Umbrel in de gaten.
#
# Aanleiding (16-10-2026): bitcoind (Core v31.1.0) crashte met een segfault.
# De Umbrel Bitcoin-app start bitcoind dan bewust NIET opnieuw (manager.ts:
# "TODO: decide if we want to auto-restart on exit ever") en blijft "ready"
# melden, dus Bassin en btc-rental zaten 30 minuten zonder node en hun logs
# groeiden met 5 MB/s.
#
# Wat dit doet, elke INTERVAL seconden:
#   * nodes (BTC, BCH, DOGE, LTC, PEP): reageert er een FAILS_BEFORE_RESTART
#     keer achter elkaar niet terwijl zijn container wel draait, dan
#     `docker restart` van die container — hooguit één keer per
#     RESTART_COOLDOWN per node, dus nooit een herstartlus. Een container die
#     NIET draait (bewust gestopt) wordt niet aangeraakt, alleen gemeld.
#   * pools: alleen melden als een container niet draait. Nooit herstarten:
#     Bassin en LoneStrike hebben handwerk voor hun fee (POOLS.md).
#   * ckpool-logboeken boven MAX_LOG_BYTES: leegmaken (ckpool schrijft met
#     O_APPEND, dus dat is veilig) en melden.
#   * schijf onder MIN_FREE_GB en CPU boven MAX_TEMP_C: melden.
#
# Meldingen: altijd in /state/watchdog.log; daarnaast naar ntfy als
# NTFY_TOPIC in /state/config staat. Elke melding hooguit eens per
# REPEAT_SECONDS, plus een melding als het weer goed is.

set -u
STATE=/state
LOG=$STATE/watchdog.log
CONF=$STATE/config
INTERVAL=${INTERVAL:-60}
FAILS_BEFORE_RESTART=${FAILS_BEFORE_RESTART:-3}
RESTART_COOLDOWN=${RESTART_COOLDOWN:-1800}
REPEAT_SECONDS=${REPEAT_SECONDS:-21600}
MAX_LOG_BYTES=${MAX_LOG_BYTES:-2147483648}
MIN_FREE_GB=${MIN_FREE_GB:-100}
MAX_TEMP_C=${MAX_TEMP_C:-92}

declare -A fails last_restart alerted

log() {
  echo "$(date -u '+%F %T') $*" >> "$LOG"
  # Eigen logboek kort houden: boven 5 MB alleen de laatste 2000 regels.
  if [ "$(stat -c %s "$LOG" 2>/dev/null || echo 0)" -gt 5242880 ]; then
    tail -n 2000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
  fi
}

send() {
  local topic=""
  # shellcheck disable=SC1090
  [ -f "$CONF" ] && topic=$(sed -n 's/^NTFY_TOPIC=//p' "$CONF" | head -1)
  [ -n "$topic" ] || return 0
  curl -s -m 10 -H "Title: Umbrel" -d "$1" "https://ntfy.sh/$topic" >/dev/null 2>&1 || log "ntfy niet bereikbaar"
}

# alert KEY TEKST: melden, maar dezelfde KEY hooguit eens per REPEAT_SECONDS.
alert() {
  local key=$1 msg=$2 now
  now=$(date +%s)
  if [ $(( now - ${alerted[$key]:-0} )) -ge "$REPEAT_SECONDS" ]; then
    alerted[$key]=$now
    log "MELDING: $msg"
    send "$msg"
  fi
}

# resolved KEY TEKST: alleen melden als er voor KEY eerder een melding was.
resolved() {
  local key=$1 msg=$2
  if [ -n "${alerted[$key]:-}" ]; then
    unset 'alerted[$key]'
    log "HERSTELD: $msg"
    send "$msg"
  fi
}

port_open() { timeout 3 bash -c "</dev/tcp/$1/$2" >/dev/null 2>&1; }
running()   { [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]; }
exists()    { docker inspect "$1" >/dev/null 2>&1; }
health()    { docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$1" 2>/dev/null; }

# node NAAM CONTAINER OK(0/1)
node() {
  local name=$1 ctr=$2 ok=$3 now
  if ! exists "$ctr"; then return; fi
  if ! running "$ctr"; then
    alert "stopped:$ctr" "$name: container $ctr draait niet (bewust gestopt?). Ik raak hem niet aan."
    fails[$name]=0
    return
  fi
  resolved "stopped:$ctr" "$name: container $ctr draait weer."
  if [ "$ok" = 1 ]; then
    if [ "${fails[$name]:-0}" -ge "$FAILS_BEFORE_RESTART" ]; then
      resolved "down:$name" "$name werkt weer."
    fi
    fails[$name]=0
    return
  fi
  fails[$name]=$(( ${fails[$name]:-0} + 1 ))
  log "$name reageert niet (${fails[$name]}x)"
  # Elke FAILS_BEFORE_RESTART fouten opnieuw beoordelen, zodat een node die
  # na een herstart nog steeds niet reageert na de cooldown weer een kans krijgt.
  if [ $(( ${fails[$name]} % FAILS_BEFORE_RESTART )) -eq 0 ]; then
    now=$(date +%s)
    if [ $(( now - ${last_restart[$name]:-0} )) -ge "$RESTART_COOLDOWN" ]; then
      last_restart[$name]=$now
      alerted["down:$name"]=$now
      log "MELDING: $name reageert al $FAILS_BEFORE_RESTART minuten niet; ik herstart $ctr"
      send "$name reageert al $FAILS_BEFORE_RESTART minuten niet; ik herstart $ctr."
      if docker restart -t 300 "$ctr" >/dev/null 2>&1; then
        log "herstart van $ctr gegeven"
      else
        alert "restartfail:$name" "$name: herstart van $ctr MISLUKT. Kijk zelf even."
      fi
    else
      alert "down:$name" "$name reageert weer niet, maar is in het afgelopen half uur al herstart. Ik herstart niet opnieuw; kijk zelf even."
    fi
  fi
}

# Docker-healthcheck van een container: alleen "unhealthy" telt als fout,
# zodat "starting" tijdens het opstarten of bijwerken nooit een herstart geeft.
healthy() { [ "$(health "$1")" != "unhealthy" ]; }

pool() {
  local name=$1 ctr=$2
  exists "$ctr" || return
  if running "$ctr"; then
    resolved "pool:$ctr" "Pool $name ($ctr) draait weer."
  else
    alert "pool:$ctr" "Pool $name ($ctr) draait NIET. Ik herstart pools niet zelf; kijk even (POOLS.md)."
  fi
}

logguard() {
  local f=$1 size
  [ -f "$f" ] || return
  size=$(stat -c %s "$f" 2>/dev/null || echo 0)
  if [ "$size" -gt "$MAX_LOG_BYTES" ]; then
    : > "$f"
    alert "log:$f" "Logboek $f was $(( size / 1024 / 1024 )) MB en is leeggemaakt. Vaak een teken dat een node weg was."
  fi
}

# --- Systeemcijfers voor de site (sinds 23-10-2026) --------------------------
# Elke ronde schrijft de watchdog $PUBLIEK/systeem.json: uptime, belasting en
# temperatuur van de processor, het verbruik van de processor (RAPL, als dat
# leesbaar is), geheugen en schijf van de hele machine, en per node geheugen
# (elke 5 rondes, docker stats) en schijf (elke 30 rondes, du op de app-map).
# Het pool-overzicht geeft dat bestand door op /public/systeem; de solo-
# poolpagina op cryptocode.nl toont het in "Waar de pools op draaien".
# Alleen totalen: geen adressen, geen IP's, geen namen van bestanden.
PUBLIEK=$STATE/publiek
mkdir -p "$PUBLIEK"
# munt:container:map-in-/appdata
NODE_CTRS="BTC:bitcoin_app_1:bitcoin BCH:bitcoin-cash-node_bitcoind_1:bitcoin-cash-node LTC:doge-litecoin-node_litecoind_1:doge-litecoin-node DOGE:doge-dogecoin-node_dogecoind_1:doge-dogecoin-node PEP:doge-pepecoin-node_pepecoind_1:doge-pepecoin-node"
declare -A node_ram node_schijf
ronde=0
prev_tot="" prev_idle="" prev_e="" prev_et=""

# "2.301GiB" (docker stats) naar bytes.
bytes_van() {
  awk -v v="$1" 'BEGIN { n = v + 0; u = v; sub(/^[0-9.]+/, "", u); m = 1;
    if (u == "KiB") m = 1024; else if (u == "MiB") m = 1048576; else if (u == "GiB") m = 1073741824;
    else if (u == "TiB") m = 1099511627776; else if (u == "kB") m = 1e3; else if (u == "MB") m = 1e6;
    else if (u == "GB") m = 1e9; printf "%.0f", n * m }'
}
# Alleen een getal mag het JSON-bestand in, anders null.
num() { if [[ "${1:-}" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then echo "$1"; else echo null; fi; }

systeem() {
  local now u n s i w irq sirq st tot idle belasting="" uptime memtot memavail dtot="" dused="" temp="" watt="" f e
  now=$(date +%s)
  read -r _ u n s i w irq sirq st _ < /proc/stat
  tot=$(( u + n + s + i + w + irq + sirq + st )); idle=$(( i + w ))
  if [ -n "$prev_tot" ] && [ "$tot" -gt "$prev_tot" ]; then
    belasting=$(awk -v a=$(( tot - prev_tot )) -v b=$(( idle - prev_idle )) 'BEGIN { printf "%.3f", (a - b) / a }')
  fi
  prev_tot=$tot; prev_idle=$idle
  uptime=$(cut -d' ' -f1 /proc/uptime | cut -d. -f1)
  memtot=$(awk '/^MemTotal:/ { printf "%.0f", $2 * 1024 }' /proc/meminfo)
  memavail=$(awk '/^MemAvailable:/ { printf "%.0f", $2 * 1024 }' /proc/meminfo)
  read -r dtot dused < <(df -P -B1 "$STATE" 2>/dev/null | awk 'NR == 2 { print $2, $3 }')
  for h in /sys/class/hwmon/hwmon*; do
    if [ "$(cat "$h/name" 2>/dev/null)" = "k10temp" ]; then temp=$(awk '{ printf "%.1f", $1 / 1000 }' "$h/temp1_input"); fi
  done
  # Verbruik van de processor (package), alleen als RAPL leesbaar is
  # (install.sh mount /sys/devices/virtual/powercap op /powercap).
  for f in /powercap/intel-rapl/intel-rapl:0/energy_uj /powercap/intel-rapl:0/energy_uj; do
    [ -r "$f" ] || continue
    if e=$(cat "$f" 2>/dev/null); then
      if [ -n "$prev_e" ] && [ "$e" -ge "$prev_e" ] && [ "$now" -gt "$prev_et" ]; then
        watt=$(awk -v d=$(( e - prev_e )) -v t=$(( now - prev_et )) 'BEGIN { printf "%.1f", d / 1e6 / t }')
      fi
      prev_e=$e; prev_et=$now
    fi
    break
  done
  if [ $(( ronde % 5 )) -eq 0 ]; then
    local ctrs=() nd munt ctr map naam mem
    for nd in $NODE_CTRS; do IFS=: read -r munt ctr map <<< "$nd"; exists "$ctr" && ctrs+=("$ctr"); done
    if [ ${#ctrs[@]} -gt 0 ]; then
      while read -r naam mem; do
        for nd in $NODE_CTRS; do
          IFS=: read -r munt ctr map <<< "$nd"
          [ "$naam" = "$ctr" ] && node_ram[$munt]=$(bytes_van "$mem")
        done
      done < <(docker stats --no-stream --format '{{.Name}} {{.MemUsage}}' "${ctrs[@]}" 2>/dev/null | awk '{ print $1, $2 }')
    fi
  fi
  if [ $(( ronde % 30 )) -eq 0 ]; then
    for nd in $NODE_CTRS; do
      IFS=: read -r munt ctr map <<< "$nd"
      [ -d "/appdata/$map" ] && node_schijf[$munt]=$(nice -n 19 du -sb "/appdata/$map" 2>/dev/null | cut -f1)
    done
  fi
  ronde=$(( ronde + 1 ))
  local nodes="" sep="" gebruikt=""
  for nd in $NODE_CTRS; do
    IFS=: read -r munt ctr map <<< "$nd"
    nodes+="$sep{\"munt\":\"$munt\",\"geheugen\":$(num "${node_ram[$munt]:-}"),\"schijf\":$(num "${node_schijf[$munt]:-}")}"
    sep=","
  done
  [ -n "$memtot" ] && [ -n "$memavail" ] && gebruikt=$(( memtot - memavail ))
  printf '{"tijd":%s,"uptimeS":%s,"cpu":{"belasting":%s,"tempC":%s,"watt":%s},"geheugen":{"totaal":%s,"gebruikt":%s},"schijf":{"totaal":%s,"gebruikt":%s},"nodes":[%s]}\n' \
    "$(( now * 1000 ))" "$(num "$uptime")" "$(num "$belasting")" "$(num "$temp")" "$(num "$watt")" \
    "$(num "$memtot")" "$(num "$gebruikt")" "$(num "$dtot")" "$(num "$dused")" "$nodes" \
    > "$PUBLIEK/systeem.json.tmp" && mv "$PUBLIEK/systeem.json.tmp" "$PUBLIEK/systeem.json"
}

log "node-watchdog gestart (interval ${INTERVAL}s, herstart na ${FAILS_BEFORE_RESTART} fouten, cooldown ${RESTART_COOLDOWN}s)"
for c in bitcoin_app_1 bitcoin-cash-node_bitcoind_1 doge-dogecoin-node_dogecoind_1 doge-litecoin-node_litecoind_1 \
         doge-pepecoin-node_pepecoind_1 bassin_ckpool_1 btc-rental bch-rental sslabs-solostrike-cash_pool_1 \
         doge-public doge-public-rental doge-dogecoin-solo_app_1; do
  if exists "$c"; then log "  gevonden: $c"; else log "  niet gevonden: $c (wordt overgeslagen)"; fi
done

while true; do
  # BTC: de Bitcoin-app houdt zijn container in leven als bitcoind crasht,
  # dus de RPC-poort is de enige betrouwbare test.
  if port_open 10.21.21.8 8332; then btc=1; else btc=0; fi
  node "BTC-node" bitcoin_app_1 "$btc"
  if port_open 10.21.21.50 8332; then bch=1; else bch=0; fi
  node "BCH-node" bitcoin-cash-node_bitcoind_1 "$bch"
  # DOGE, LTC, PEP: eigen apps met een docker-healthcheck (getbestblockhash).
  if healthy doge-dogecoin-node_dogecoind_1; then d=1; else d=0; fi
  node "DOGE-node" doge-dogecoin-node_dogecoind_1 "$d"
  if healthy doge-litecoin-node_litecoind_1; then l=1; else l=0; fi
  node "LTC-node" doge-litecoin-node_litecoind_1 "$l"
  if healthy doge-pepecoin-node_pepecoind_1; then p=1; else p=0; fi
  node "PEP-node" doge-pepecoin-node_pepecoind_1 "$p"

  pool "BTC (3333)" bassin_ckpool_1
  pool "BTC-huur (3338)" btc-rental
  pool "BCH-huur (3337)" bch-rental
  pool "BCH (3334)" sslabs-solostrike-cash_pool_1
  pool "LTC+DOGE (3335)" doge-public
  pool "LTC+DOGE-huur (3339)" doge-public-rental
  pool "LTC+DOGE privé" doge-dogecoin-solo_app_1

  logguard /logs/btc-rental/ckpool.log
  logguard /logs/bassin/ckpool.log

  free_gb=$(df -P -BG /state 2>/dev/null | awk 'NR==2 {gsub("G","",$4); print $4}')
  if [ -n "$free_gb" ] && [ "$free_gb" -lt "$MIN_FREE_GB" ]; then
    alert "disk" "Schijf bijna vol: nog ${free_gb} GB vrij."
  else
    resolved "disk" "Schijfruimte weer in orde (${free_gb:-?} GB vrij)."
  fi

  temp=""
  for h in /sys/class/hwmon/hwmon*; do
    if [ "$(cat "$h/name" 2>/dev/null)" = "k10temp" ]; then temp=$(( $(cat "$h/temp1_input") / 1000 )); fi
  done
  if [ -n "$temp" ] && [ "$temp" -ge "$MAX_TEMP_C" ]; then
    alert "temp" "Processor ${temp} °C (grens ${MAX_TEMP_C} °C)."
  elif [ -n "$temp" ]; then
    resolved "temp" "Processortemperatuur weer normaal (${temp} °C)."
  fi

  # Systeemcijfers voor de site; een fout hierin mag de bewaking nooit stoppen.
  systeem || log "systeemcijfers konden niet worden geschreven"

  sleep "$INTERVAL"
done
