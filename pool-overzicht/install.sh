#!/bin/bash
# Installeert of vernieuwt het pool-overzicht op de Umbrel (poort 22570).
# Alleen-lezen: raakt geen enkele pool aan. Weghalen: sudo docker rm -f pool-overzicht
set -e
DIR="$HOME/pool-overzicht"
chmod a+r "$DIR/server.js"

NET=$(sudo docker inspect doge-public -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' | awk '{print $1}')
PRIV=$(sudo docker ps --format '{{.Names}}' | grep -i doge | grep -iv public | grep -iE 'app|stratum|pool' | head -1)
PRIVNET=$(sudo docker inspect "$PRIV" -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null | awk '{print $1}')
echo "netwerk publiek: $NET   prive container: ${PRIV:-niet gevonden} ($PRIVNET)"

# Pepecoin-netwerkcijfers (alleen lezen): dezelfde RPC-gegevens als de pools, uit de
# .env van de privépool, in een eigen bestand (600) zodat niets op het scherm komt.
PEPENV="$DIR/pep.env"
grep -E '^PEP_RPC_(HOST|PORT|USER|PASSWORD)=' "$HOME/umbrel/app-data/doge-dogecoin-solo/.env" > "$PEPENV" || true
chmod 600 "$PEPENV"
echo "Pepecoin-gegevens: $(grep -c . "$PEPENV") van 4 regels"

# Systeemcijfers van de node-watchdog (/public/systeem); de map bestaat ook als de
# watchdog nog niet is bijgewerkt, dan geeft de route gewoon 404.
mkdir -p "$HOME/node-watchdog/publiek"

sudo docker rm -f pool-overzicht >/dev/null 2>&1 || true
sudo docker run -d --name pool-overzicht --restart unless-stopped \
  --network "$NET" -p 22570:3000 --user 0 \
  -e DOGE_PRIVATE_URL="http://$PRIV:3000/api/status" \
  --env-file "$PEPENV" \
  -v "$DIR/server.js":/app/overzicht.js:ro \
  -v "$HOME/umbrel/app-data/bassin/data":/src/bassin:ro \
  -v "$HOME/btc-rental/logs":/src/btc-rental:ro \
  -v "$HOME/umbrel/app-data/sslabs-solostrike-cash/data":/src/bch:ro \
  -v "$HOME/bch-rental":/src/bch-rental:ro \
  -v "$HOME/node-watchdog/publiek":/src/systeem:ro \
  --entrypoint node cryptocode/doge-public:1.7.0 /app/overzicht.js >/dev/null

if [ -n "$PRIVNET" ] && [ "$PRIVNET" != "$NET" ]; then
  sudo docker network connect "$PRIVNET" pool-overzicht || true
fi

sleep 3
curl -s http://localhost:22570/api > /tmp/overzicht.json
python3 - <<'PY'
import json
d = json.load(open("/tmp/overzicht.json"))
for p in d["pools"]:
    print("%-18s %-12s %3s workers  %s" % (p["naam"], p["status"], p["workers"], p.get("fout", "")))
PY
echo
echo "Open: http://192.168.1.149:22570"
curl -s http://localhost:22570/public/summary | python3 -c "import json,sys; [print(p['id'], 'pep:', json.dumps(p.get('pep'))) for p in json.load(sys.stdin)['pools'] if p.get('pep')]"
echo
curl -s http://localhost:22570/public/systeem | head -c 400; echo
