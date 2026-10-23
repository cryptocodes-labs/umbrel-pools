#!/bin/bash
#
# Installeert (of vernieuwt) de node-watchdog als losse container op de Umbrel.
#   sudo bash ~/node-watchdog/install.sh
#
set -euo pipefail
DIR=/home/umbrel/node-watchdog
IMG=cryptocode/node-watchdog:1.0

echo "== containernamen die de watchdog verwacht:"
for c in bitcoin_app_1 bitcoin-cash-node_bitcoind_1 doge-dogecoin-node_dogecoind_1 doge-litecoin-node_litecoind_1 \
         doge-pepecoin-node_pepecoind_1 bassin_ckpool_1 btc-rental bch-rental sslabs-solostrike-cash_pool_1 \
         doge-public doge-public-rental doge-dogecoin-solo_app_1; do
  if docker inspect "$c" >/dev/null 2>&1; then echo "  ok   $c"; else echo "  MIST $c"; fi
done

echo "== bouwen $IMG"
docker build -q -t "$IMG" "$DIR"

touch "$DIR/watchdog.log" "$DIR/config"
chown 1000:1000 "$DIR/watchdog.log" "$DIR/config"
# Map met de systeemcijfers voor de site (systeem.json); het pool-overzicht
# mount alleen deze map, niet de config met het ntfy-topic.
mkdir -p "$DIR/publiek"

docker rm -f node-watchdog >/dev/null 2>&1 || true
docker run -d --name node-watchdog --restart unless-stopped \
  --network umbrel_main_network \
  --memory 64m --cpus 0.2 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$DIR":/state \
  -v /home/umbrel/btc-rental/logs:/logs/btc-rental \
  -v /home/umbrel/umbrel/app-data/bassin/data/www:/logs/bassin \
  -v /home/umbrel/umbrel/app-data:/appdata:ro \
  -v /sys/devices/virtual/powercap:/powercap:ro \
  "$IMG" >/dev/null

sleep 5
echo "== node-watchdog draait:"; docker ps --filter name=node-watchdog --format '  {{.Names}} {{.Status}}'
echo "== eerste regels:"; tail -n 20 "$DIR/watchdog.log"
sleep 60
echo "== systeemcijfers (na een minuut):"; cat "$DIR/publiek/systeem.json" 2>/dev/null || echo "  nog niet geschreven"
