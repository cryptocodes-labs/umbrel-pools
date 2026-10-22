#!/bin/bash
#
# Zet beide BTC-pools (btc-rental en Bassin) op een nieuwe ckpool-versie met
# onze 1%-fee. Eerst btc-rental (meestal leeg) als proef, daarna Bassin.
# Lukt een stap niet, dan gaat die pool terug naar het oude image.
#   sudo bash ~/ckpool-upgrade.sh v1.2.0
#
# Bouwbestand: ~/ckpool-fee-<versie>/Dockerfile (tag + commit vastgezet,
# bouwen faalt als het adres van de ckpool-ontwikkelaar niet vervangen is).
# Sinds 22-10-2026: v1.1.1 → v1.2.0 tegen het groeiende geheugen van ckpool.
set -u
V=${1:?geef een versie, bijv. v1.2.0}
NEW=cryptocode/ckpool-solo-fee:$V
FEE=bc1qtr0j4w275ndkyrh5396rzdvmtakqymcp046cht
SRC=/home/umbrel/ckpool-fee-$V
B=/home/umbrel/umbrel/app-data/bassin
BLOG=$B/data/www/ckpool.log
RLOG=/home/umbrel/btc-rental/logs/ckpool.log
OLD_R=$(docker inspect -f '{{.Config.Image}}' btc-rental) || { echo "LET OP: btc-rental niet gevonden"; exit 1; }
OLD_B=$(docker inspect -f '{{.Config.Image}}' bassin_ckpool_1) || { echo "LET OP: bassin_ckpool_1 niet gevonden"; exit 1; }

# btc-rental is geen Umbrel-app; zelfde opties als ~/btc-rental-start.sh.
start_rental() {
  docker rm -f btc-rental >/dev/null 2>&1
  docker run -d --name btc-rental --restart unless-stopped \
    --network umbrel_main_network --user 1000:1000 --tmpfs /tmp \
    -p 3338:3333/tcp \
    -v /home/umbrel/btc-rental/ckpool.conf:/config/ckpool.conf:ro \
    -v /home/umbrel/btc-rental/logs:/logs \
    --entrypoint ckpool "$1" -k -B -c /config/ckpool.conf >/dev/null
}

# Wacht tot een pool draait, het nieuwe image heeft en in zijn log (na regel
# $3) de 1%-fee naar ons adres en een eerste blokvoorstel meldt.
gezond() { # container log startregel image
  for _ in $(seq 1 45); do
    sleep 2
    [ "$(docker inspect -f '{{.State.Running}} {{.Config.Image}}' "$1" 2>/dev/null)" = "true $4" ] || continue
    nieuw=$(tail -n +"$3" "$2")
    echo "$nieuw" | grep -q "1.0 percent donation to $FEE" && echo "$nieuw" | grep -q "Stored local workbase" && return 0
  done
  return 1
}

echo "== Nu: btc-rental $OLD_R, Bassin $OLD_B"
pr=$(docker inspect -f '{{json .HostConfig.PortBindings}} {{json .HostConfig.Tmpfs}} {{.Config.User}} {{json .HostConfig.Binds}}' btc-rental)
case "$pr" in
  *'"HostPort":"3338"'*'"/tmp"'*'1000:1000'*'/home/umbrel/btc-rental/ckpool.conf:/config/ckpool.conf:ro'*) ;;
  *) echo "LET OP: btc-rental draait met andere opties dan verwacht, niets veranderd:"; echo "  $pr"; exit 1 ;;
esac

echo "== Bouwen $NEW ($(date -u +%T) UTC, duurt een paar minuten)"
if ! docker build --build-arg FEE_ADDR=$FEE -t "$NEW" "$SRC" > "$SRC/build.log" 2>&1; then
  echo "LET OP: bouwen mislukt, niets veranderd. Zie $SRC/build.log"; exit 1
fi
if ! docker run --rm --entrypoint sh "$NEW" -c "grep -q $FEE /bin/ckpool && ! grep -q bc1q28kkr5hk4gnqe3evma6runjrd2pvqyp8fpwfzu /bin/ckpool"; then
  echo "LET OP: feeadres zit niet goed in het nieuwe image, niets veranderd."; exit 1
fi
echo "image gebouwd, feeadres erin"

echo "== btc-rental naar $V ($(date -u +%T) UTC)"
n=$(($(wc -l < "$RLOG") + 1))
start_rental "$NEW"
if gezond btc-rental "$RLOG" $n "$NEW"; then
  echo "btc-rental draait op $V, fee 1% naar ons adres"
else
  echo "LET OP: btc-rental kwam niet goed op met $V; terug naar $OLD_R. Bassin niet aangeraakt."
  tail -n +$n "$RLOG" | tail -5
  start_rental "$OLD_R"; exit 1
fi

echo "== Bassin naar $V ($(date -u +%T) UTC)"
cp -p "$B/docker-compose.yml" "$B/docker-compose.yml.voor-$V"
sed -i "s#image: $OLD_B\$#image: $NEW#" "$B/docker-compose.yml"
if ! grep -q "image: $NEW\$" "$B/docker-compose.yml"; then
  echo "LET OP: image-regel van Bassin niet gevonden; Bassin niet aangeraakt."
  cp -p "$B/docker-compose.yml.voor-$V" "$B/docker-compose.yml"; exit 1
fi
n=$(($(wc -l < "$BLOG") + 1))
umbreld client apps.stop.mutate --appId bassin >/dev/null
umbreld client apps.start.mutate --appId bassin >/dev/null
if gezond bassin_ckpool_1 "$BLOG" $n "$NEW"; then
  echo "Bassin draait op $V, fee 1% naar ons adres"
else
  echo "LET OP: Bassin kwam niet goed op met $V; terug naar $OLD_B."
  tail -n +$n "$BLOG" | tail -5
  cp -p "$B/docker-compose.yml.voor-$V" "$B/docker-compose.yml"
  umbreld client apps.stop.mutate --appId bassin >/dev/null
  umbreld client apps.start.mutate --appId bassin >/dev/null
  exit 1
fi

echo "== Klaar ($(date -u +%T) UTC). Claude controleert miners en geheugen."
