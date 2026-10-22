#!/bin/bash
#
# Houdt de Bitcoin-node rond 3 GB geheugen (sinds 22-10-2026).
#
# Bitcoin Core leest zijn UTXO-database (chainstate, ~11 GB) via mmap. Wat
# gelezen is blijft als cache bij de app staan en Umbrel telt dat mee: de
# node stond op ~6,4 GB, waarvan maar ~1,9 GB echt in gebruik. Met een grens
# van 3 GB (plus 1 GB swap) houdt de kernel die cache klein; de node leest
# dan vaker van de SSD, wat op NVMe nauwelijks merkbaar is.
#
# Een update van de Bitcoin Node-app zet docker-compose.yml terug zonder
# grens. Wordt aangeroepen vanuit ~/fees-herstellen.sh; los kan ook:
#   bash ~/btc-geheugen-herstellen.sh
#
# Waarom live met docker update én in docker-compose.yml: docker update
# werkt meteen zonder herstart, de compose-regel zorgt dat de grens blijft
# als Umbrel de container opnieuw aanmaakt (herstart Umbrel, app-herstart).

N=${BTC_COMPOSE:-/home/umbrel/umbrel/app-data/bitcoin/docker-compose.yml}
SUDO=${SUDO-sudo}
C=bitcoin_app_1
GRENS=3g
SWAP=4g # geheugen + swap samen

if python3 -I -c "import yaml,sys; a=yaml.safe_load(open(sys.argv[1]))['services']['app']; sys.exit(0 if a.get('mem_limit')=='$GRENS' and a.get('memswap_limit')=='$SWAP' else 1)" "$N"; then
  echo "BTC-geheugengrens in compose: ok"
else
  $SUDO cp -p "$N" "$N.voor-geheugen"
  if ! $SUDO python3 -I - "$N" "$C" "$GRENS" "$SWAP" <<'EOF'
import re, sys
p, c, grens, swap = sys.argv[1:5]
lines = open(p).read().split('\n')
if any(re.match(r"^\s*(mem_limit|memswap_limit):", l) for l in lines):
    sys.exit("er staat al een andere geheugengrens; niets aangepast")
out, done = [], False
for l in lines:
    out.append(l)
    m = re.match(r"^(\s*)container_name: " + re.escape(c) + r"\s*$", l)
    if m and not done:
        out.append(f"{m.group(1)}mem_limit: {grens}")
        out.append(f"{m.group(1)}memswap_limit: {swap}")
        done = True
if not done:
    sys.exit(f"container_name {c} niet gevonden; niets aangepast")
open(p, 'w').write('\n'.join(out))
EOF
  then
    echo "LET OP: BTC-geheugengrens niet in compose gezet. Vraag Claude om te kijken."
    exit 1
  fi
  if ! python3 -I -c "import yaml,sys; s=yaml.safe_load(open(sys.argv[1]))['services']; a=s['app']; assert a['mem_limit']=='$GRENS' and a['memswap_limit']=='$SWAP' and a['container_name']=='$C' and 'mem_limit' not in s['tor']" "$N"; then
    echo "LET OP: aangepaste compose klopt niet; oude versie teruggezet."
    $SUDO cp -p "$N.voor-geheugen" "$N"
    exit 1
  fi
  echo "BTC-geheugengrens in compose gezet ($GRENS)"
fi

[ -n "${GEEN_LIVE:-}" ] && exit 0

ID=$($SUDO docker inspect -f '{{.Id}}' $C 2>/dev/null) || { echo "LET OP: $C draait niet; grens geldt bij de volgende start."; exit 0; }
CG=/sys/fs/cgroup/system.slice/docker-$ID.scope
if [ "$(cat $CG/memory.max)" = "$((3 * 1024 * 1024 * 1024))" ]; then
  echo "BTC-geheugengrens live: ok"
else
  # In stappen omlaag, zodat de kernel de cache rustig kan vrijgeven.
  oom0=$(awk '/^oom_kill /{print $2}' $CG/memory.events)
  for stap in "8g 9g" "5g 6g" "$GRENS $SWAP"; do
    set -- $stap
    if ! $SUDO docker update --memory $1 --memory-swap $2 $C >/dev/null; then
      echo "LET OP: grens $1 zetten mislukt. Vraag Claude om te kijken."
      exit 1
    fi
    if [ "$(awk '/^oom_kill /{print $2}' $CG/memory.events)" != "$oom0" ] || [ "$($SUDO docker inspect -f '{{.State.Running}}' $C)" != true ]; then
      $SUDO docker update --memory 16g --memory-swap 17g $C >/dev/null
      echo "LET OP: node kwam in de knel bij $1; grens weer ruim (16 GB) gezet. Vraag Claude om te kijken."
      exit 1
    fi
    echo "grens $1: ok ($(($(cat $CG/memory.current) / 1048576)) MB)"
  done
fi
cur=$(cat $CG/memory.current); inf=$(awk '/^inactive_file /{print $2}' $CG/memory.stat); sw=$(cat $CG/memory.swap.current)
echo "BTC-node volgens Umbrel nu: $(((cur - inf + sw) / 1048576)) MB"
