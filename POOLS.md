# Cryptocode mining pools — hoe het staat (bijgewerkt 22 oktober 2026)

Lees dit vóór je iets aan de pools, de Umbrel of de VPS verandert.

## Overzicht

| Publiek (pool.cryptocodes.eu) | VPS HAProxy → Umbrel | Pool | Fee | Openbaar |
|---|---|---|---|---|
| 3333 | → 100.111.67.28:3456 | BTC solo — Bassin-app, eigen ckpool-image | 1% → bc1qtr0j4w275ndkyrh5396rzdvmtakqymcp046cht | ja |
| 3338 | → :3338 | BTC solo **rental** — losse container `btc-rental` (mindiff 500k, startdiff 1M) | 1% → zelfde BTC-adres | ja |
| 3334 | → :3335 | BCH solo — LoneStrike Cash (asicseer-pool `-B`) | 1% → bitcoincash:qppus6ldc7esd8x4lfq6yk98metwm6mg6czuhu4k8p | ja |
| 3337 | → :3337 | BCH solo **rental** — losse container `bch-rental` (mindiff 500k, startdiff 1M) | 1% → zelfde BCH-adres | ja |
| 3335 | → :22559 | DOGE+LTC(+PEP) **publiek** — losse container `doge-public` (image cryptocode/doge-public:1.8.0 sinds 16 okt, PUBLIC_MERGED=1), username `LTC.DOGE[.PEP][.rig]` | 1% op LTC → LdAEjW…, DOGE → DFabbT3…, PEP → Pfe2U3… | ja (live 26 sep, PEP 16 okt) |
| 3339 | → :22562 | DOGE+LTC(+PEP) **publiek rental** — losse container `doge-public-rental` (zelfde image, START_DIFFICULTY 1048576, MIN 65536), username `LTC.DOGE[.PEP][.rig]` | 1% op LTC, DOGE en PEP | ja (live 26 sep, PEP 16 okt) |
| 3336 | → :22558 | DOGE+LTC rental (umbrel-dogecoin 1.6.1, LOCK_PAYOUT_ADDRESS=1) | – | alleen tijdens eigen huurorder |
| niet doorgestuurd | :22557 | DOGE+LTC thuispoort (app 1.6.1), gelockt op eigen adressen | – | nee |
| niet doorgestuurd | :33333 | LoneStrike SV2 — betaalt altijd één vast adres | – | nooit openbaar |

Nooit doorsturen: RPC-poorten 8332 (BTC/BCH), 9332 (LTC), 22555 (DOGE), dashboards.

Toegang: VPS `ssh -i ~/.ssh/id_ed25519_vps ubuntu@57.131.149.173` (Tailscale `pool-vps` 100.105.8.122), config in `/etc/haproxy/haproxy.cfg`, firewall `ufw`. Umbrel `ssh umbrel@192.168.1.149` (Tailscale 100.111.67.28). DNS pool.cryptocodes.eu → 57.131.149.173 (niet via Cloudflare-proxy, stratum werkt daar niet door).

## Hoe de 1% fee werkt

- **BTC:** standaard ckpool heeft geen operator-fee; de enige "donation" gaat naar een in de code vastgezet adres van de ckpool-ontwikkelaar. Daarom draaien Bassin en btc-rental op een eigen build `cryptocode/ckpool-solo-fee:v1.2.0` (sinds 22 okt; Dockerfile in `~/ckpool-fee-v1.2.0` op de Umbrel, kopie in `ckpool-fee/` in deze repo) waarin dat adres vervangen is door ons BTC-adres, plus `"donation" : 1.0` in `~/umbrel/app-data/bassin/data/config/ckpool.conf`. Controle: `ckpool.log` moet `1.0 percent donation to bc1qtr0j…` tonen.
- **BCH:** asicseer-pool kent `pool_fee` (naar `bchaddress`), maar het startscript van LoneStrike schrijft bij elke start `0.0`. Daarom is `~/umbrel/app-data/sslabs-solostrike-cash/entrypoint-fee.sh` (kopie met 1.0) over `/entrypoint.sh` gemount in docker-compose.yml. `bch-rental` gebruikt een eigen kopie `~/bch-rental-entrypoint.sh`.

## ⚠️ Updates — dit gaat fout als je het vergeet

Een update van **Bassin**, **LoneStrike**, **Bitcoin Cash Node** of **Bitcoin Node** in de Umbrel App Store zet `docker-compose.yml` terug:
- Bassin draait dan weer de officiële image, maar `donation: 1.0` blijft in de config staan → **1% gaat naar de ckpool-ontwikkelaar in plaats van naar ons.**
- LoneStrike draait dan weer met `pool_fee: 0.0` → geen fee.
- Bitcoin Cash Node krijgt weer `-txindex=1` en verliest `-prune` → de BCH-node **start niet** ("-reindex to go back to unpruned mode") en LoneStrike en bch-rental staan stil. De bewaking meldt dan dat de BCH-node niet reageert.
- Bitcoin Node verliest de geheugengrens van 3 GB → de node staat in Umbrel weer op ~6 GB (vooral cache van de UTXO-database). Niet gevaarlijk, wel weer hoog.

**Na élke update van Bassin, LoneStrike, Bitcoin Cash Node of Bitcoin Node:** log in op de Umbrel en draai `~/fees-herstellen.sh`. Dat zet alles terug, herstart waar nodig en toont de controle (BTC `1.0 percent donation to bc1qtr0j…`, BCH en BCH rental `"pool_fee": 1.0`, `BCH-node: -prune=10000`, `BTC-node: geheugengrens 3 GB`). Het BCH-deel staat in `~/bch-prune-herstellen.sh`, het BTC-geheugendeel in `~/btc-geheugen-herstellen.sh` (kopieën in `scripts/` in deze repo).
- Meldt het script "LET OP: update gebruikt docker-ckpool-solo:vX": de officiële ckpool is naar een nieuwe versie gegaan. Het script zet onze v1.2.0 terug. Kijk bij de bron (bitbucket.org/ckolivas/ckpool) of de nieuwe versie iets oplevert. Zo ja: kopieer `~/ckpool-fee-v1.2.0` naar `~/ckpool-fee-<versie>`, zet in de Dockerfile `VERSION` en `COMMIT` (de commit van die tag) en draai `sudo bash ~/ckpool-upgrade.sh <versie>` (`scripts/ckpool-upgrade.sh`). Dat bouwt het image (faalt als het adres van de ontwikkelaar niet vervangen is), zet eerst btc-rental en dan Bassin om, en zet een pool terug op het oude image als de fee-regel niet verschijnt. Pas daarna in `~/fees-herstellen.sh` en `~/btc-rental-start.sh` de versie aan.
- `btc-rental` en `bch-rental` zijn losse containers (`--restart unless-stopped`), niet uit de App Store. Die worden nooit automatisch bijgewerkt en een app-update raakt ze niet.
- **Nooit "Alles bijwerken"** in de Umbrel als Bassin, LoneStrike, Bitcoin Cash Node of Bitcoin Node in de lijst staan: werk die apart bij en draai daarna `~/fees-herstellen.sh`. De AI-agent (Claude Code via Umbrel MCP) werkt Bassin en LoneStrike nooit bij.

## Overig

- Umbrel draaide op 26 sep vast door een Ubuntu Desktop-VM (Machines, 4 cores/8 GB) naast de full nodes. VM gestopt (`virsh destroy umbrel-machine-ubuntu-desktop`, autostart uit). Geen VM's meer naast de nodes, of maximaal 2 cores/4 GB.
- Na een harde herstart moeten de nodes eerst bijwerken; ckpool meldt dan "Bitcoin Core is in initial sync" en komt vanzelf terug.
- LoneStrike-images staan op `:latest` van een externe ontwikkelaar (danhaus93-ops); `bch-rental` is vastgezet op de image-ID die op 26 sep draaide.
- **DOGE+LTC openbaar (LIVE sinds 26 sep):** nieuwe modus `PUBLIC_MERGED=1` in umbrel-dogecoin (sinds 16 okt op `main` van cryptocodes-labs/umbrel-dogecoin-litecoin-merged: 1.7.0 = openbare modus, 1.8.0 = plus optioneel PEP). Draait als **losse container `doge-public`** naast de bestaande app (die blijft 1.6.1, gelockt). Gebruikersnaam `LTC-adres.DOGE-adres[.rig]` (ltc1q… mag). De pool bouwt per miner zelf het DOGE-blok (getblocktemplate + auxpow via submitblock) omdat createauxblock maar één adres kan betalen: 99% miner / 1% fee op beide chains naar PAYOUT_ADDRESS (DFabbT3…) en LTC_PAYOUT_ADDRESS (LdAEjW…). Umbrel-poort 22559 (stratum), 22561 (dashboard, alleen LAN). Uitrol: `scripts/deploy-public-umbrel.sh`; VPS publiek 3335 → Umbrel 22559. Getest op regtest met echte dogecoind 1.14.9 + litecoind 0.21.5.8 (CI: `test/merged_regtest.sh` draait alle `*_regtest`- en `public_*`-suites tegen de echte daemons); privé-modus byte-identiek gebleven.
- Andreas heeft op 26 sep akkoord gegeven om BTC en BCH openbaar te maken.
- 26 sep: externe test geslaagd — eigen miner via pool.cryptocodes.eu kwam binnen en stuurde shares. Rental-poorten 3337/3338 nog niet met een echte huurorder getest.
- 26 sep eindcontrole: `python3 ~/Documents/umbrel-dogecoin/scripts/check_pools.py` (leest het werk van alle publieke poorten zoals een miner het krijgt) gaf 5× OK, 99% miner / 1% fee. DOGE- en LTC-blok van de publieke pool door de mainnet-nodes als geldig beoordeeld via `sudo docker exec doge-public node /app/verify-proposal.js <LTC> <DOGE>`. Draai beide checks opnieuw na elke wijziging of update.
- `doge-public` herbouwen na codewijziging: bron (`images/stratum` van main) naar `~/doge-public-src` kopiëren, `chmod -R a+rX ~/doge-public-src` (anders EACCES), dan `sudo bash ~/deploy-public-umbrel.sh`. Wordt niet door de App Store bijgewerkt. Het script in de repo bouwt sinds 1.8.0 `cryptocode/doge-public:1.8.0` en neemt ook de `PEP_*`-instellingen uit de Solo-app over.
- 26 sep: doge-public en doge-public-rental draaien met MAX_CONNECTIONS(_PER_IP)=512: al het publieke verkeer komt via HAProxy van één IP binnen, de standaard 8 per IP gold dus voor iedereen samen. Env-bestanden: ~/doge-public/env en ~/doge-public-rental/env.
- Eigen MRR Scrypt-huur: pool 1 = doge.pool.cryptocodes.eu:3339 met username LdAEjW….DFabbT3….rental32 (99% + 1% fee, allebei naar ons), pool 2 (backup) = :3336 met DFabbT3….rental29 (privé, gelockt). Niet meer op 3335 met alleen een DOGE-adres: dat weigert de publieke pool.

## Pool-overzicht (één pagina voor alle pools)

- `pool-overzicht/` (server.js + install.sh), draait als container `pool-overzicht` op de Umbrel, poort **22570**: http://192.168.1.149:22570 , JSON op `/api` (basis voor stats op de website).
- Alleen-lezen: leest pool.status/users van Bassin en btc-rental, LoneStrike/bch-rental logs, en `/api/status` van doge-public, doge-public-rental en de privé DOGE-app.
- Installeren/vernieuwen: vanaf Mac `scp -r ~/Projects/umbrel-cryptocode/pool-overzicht umbrel@192.168.1.149:~/` en op de Umbrel `bash ~/pool-overzicht/install.sh`.
- De DOGE-app-dashboard toont alleen de privé pool (22557/22558/3336). Publieke/rental miners staan op 22561/22563 en op dit overzicht. BTC/BCH rentals staan niet in Bassin/LoneStrike (aparte containers) — wel hier.

## Publieke stats (live sinds 26-09-2026)

- VPS: Caddy op 80/443 (`/etc/caddy/Caddyfile`), alleen `https://pool.cryptocodes.eu/public/*` → Umbrel 100.111.67.28:22570. Andere paden geven een tekstregel. Mining-poorten (HAProxy) staan er los van.
- Sinds 23-10-2026 heeft Caddy ook `btc.pool`, `bch.pool`, `doge.pool` en `rental.pool.cryptocodes.eu`: eigen Let's Encrypt-certificaat, en in een browser een 301 naar `https://pool.cryptocodes.eu{uri}`. Daarvoor faalde HTTPS op die namen (geen certificaat), terwijl HSTS op cryptocodes.eu met `includeSubDomains` (sinds 22-10) browsers naar HTTPS dwingt. Reservekopie van de oude instelling: `/etc/caddy/Caddyfile.bak-20261023`. Komt er een nieuwe stratumnaam bij in de DNS, zet hem dan ook in dit Caddy-blok.
- API: `/public/summary` (totalen per pool, geen adressen) en `/public/miner/<adres>` (één adres; merged = DOGE-adres). 30 s cache, 30 verzoeken/min per IP.
- Website: sectie "Live stats" op /minen/solo-pool (`src/components/SoloPoolStats.tsx`, 9 talen), CSP connect-src bevat pool.cryptocodes.eu. Live gecontroleerd op cryptocodes.eu en cryptocode.nl.

## Stand 22 oktober 2026

- **BTC-node geheugengrens 3 GB** (+1 GB swap) sinds 22 okt 17:40 NL. Bitcoin Core leest de UTXO-database (~11 GB) via mmap; wat gelezen was bleef als cache bij de app staan en Umbrel telde dat mee (6,4 GB, waarvan 1,9 GB echt in gebruik). Nu 2,3 GB in Umbrel. Zonder herstart gezet (`docker update` in stappen 8 → 5 → 3 GB) en vastgelegd als `mem_limit`/`memswap_limit` bij service `app` in `~/umbrel/app-data/bitcoin/docker-compose.yml`. Script: `scripts/btc-geheugen-herstellen.sh` (zet de grens op 16 GB terug als de node in de knel komt).
- **ckpool v1.2.0** op Bassin en btc-rental (22 okt 17:52 NL, Bassin ±18 s stil, miners vanzelf terug). v1.1.1 groeide ~80–100 MB per dag per pool, ook zonder miners: na de herstart van 16 okt weer 490–640 MB in 6 dagen (18.044 blokvoorstellen). v1.2.0 slaat in solomodus de transactielijst per blokvoorstel over (commit 15f4de3f), vervangt jansson door yyjson en bevat enkele lekfixes. Onze instellingen (`btcd`, `btcsig`, `donation`, `mindiff`, `startdiff`, `maxdiff`, `zmqblock`, `logdir`), de opties `-k -B -c`, de statusbestanden en de logregel `1.0 percent donation to …` zijn ongewijzigd (nagekeken in de bron). Na de uitrol: `check_pools.py` 6× OK (99% / 1%). Umbrels eigen Bassin-app (2.1.4) gebruikt nog v1.1.1.
- **ckpool-geheugen meten**: `scripts/ckpool-geheugen-meten.sh` draait 14 dagen op de Umbrel en schrijft elke 10 min het geheugen van beide ckpools naar `~/ckpool-geheugen.log` (UTC). Start 130 MB, na 12 min ~215 MB. Blijft het daarna groeien: wekelijks herstarten met `~/pools-herstart.sh`.
- **Extra munten (onderzocht 22 okt)**: DigiByte kan niet merge-minen (geen AuxPoW in DigiByte Core v9.26.7). Onder LTC kunnen wel BELLS (chain id 16), DINGO (50), LKY (8211), JKC (8224), SHIC (74) en TRMP (168); CRC is dood. Per blok €0,01–0,19 (koersen 22 okt), bij ~2 GH/s één blok per 1–2,5 jaar per munt: alleen interessant als reclame. BELLS is de bekendste en past met DOGE (98) en PEP (63) in een boom van 4. DINGO heeft dezelfde adresbytes als DOGE.
- Repo hernoemd van `umbrel-ecash` naar `umbrel-pools` (22 okt). Oude adressen sturen door, ook die van de App Store op de Umbrel (`andreashetem-cloud/umbrel-cryptocode`).

## Stand 16 oktober 2026 (nodes en apps)

- **Litecoin Node 0.21.5.8-1** (was 0.21.4). Verplicht voor pools: 0.21.5.6 en 0.21.5.7 brachten MWEB-softforks, actief sinds hoogte 3.154.440 en 3.172.640. Litecoin 24 (nu rc) doet een MWEB-database-upgrade die niet terug kan: eerst back-up.
- **Dogecoin Node 1.14.9-2**: alleen nieuwe image-adressen. Sinds de verhuizing naar de org staan alle images op `ghcr.io/cryptocodes-labs/…`; `ghcr.io/andreashetem-cloud/…` bestaat niet meer (een herinstallatie van een oude versie zou falen).
- **DOGE + LTC Solo 1.8.0** (privé, PEP uit). `doge-public` en `doge-public-rental` draaien nog hun 1.7.0-build tot de PEP-uitrol.
- **Pepecoin Node 1.1.0-1** geïnstalleerd (16 okt), nog niet aan de pool gekoppeld.
- **DBCACHE=450** op de DOGE- en LTC-node, via Umbrel-instellingen (eigen omgevingsvariabele, blijft bij updates). Scheelt weinig RAM: het geheugen van die nodes zit vooral in de blokindex.
- **BTC-node**: Bitcoin Core v31.1.0. **16 okt 16:24 (NL) segfault** in een RPC-thread; de Umbrel Bitcoin-app start bitcoind dan bewust niet opnieuw ("TODO … auto-restart", manager.ts) en blijft "ready" tonen. Bassin en btc-rental zaten 30 min zonder node, weigerden 1…/3…-adressen en hun `ckpool.log` groeide 5 MB/s. Opgelost met een herstart; nu bewaakt (zie hieronder). Enige crash sinds 3 okt, geen hardwarefouten.
- **BCH-node**: officiële Umbrel-app, BCHN v29.0.0; v29.2.0 is "strongly encouraged" — wachten op een update van de Umbrel-app.
- **BCH-node gesnoeid (16 okt 19:01 NL)**: van 275 GB naar 15 GB. In de `docker-compose.yml` van de app `-txindex=1` → `-txindex=0` plus `-prune=10000` (10 GB blokken, nu terug tot hoogte 882.966). Niet via `bitcoin.conf`: die herschrijft het BCH-dashboard volledig (Tor-instellingen), en `-txindex=1` op de opdrachtregel botst met prune (BCHN `init.cpp`: "Prune mode is incompatible with -txindex"). De dashboards van LoneStrike en BCHN vragen transacties op mét blokhash, dat werkt zonder txindex. De oude index (21 GB) staat in de Umbrel-prullenbak. Terug naar een volledige node = 232 GB opnieuw downloaden.
- **ckpool-geheugen**: de ckpool van Bassin en van btc-rental gebruikten na 13 dagen elk 2,4 GB (met 3 resp. 0 workers). Op 16 okt 18:34 NL herstart (`sudo docker restart bassin_ckpool_1 btc-rental`; fee zit in image + `ckpool.conf` en bleef 1,0) → 50 MB elk. Groeit het weer, dan is het een lek in ckpool.
- **eCash Solo Mining-app** op 16 okt 18:06 NL verwijderd via het Umbrel-scherm (166 GB vrij).
- De ckpool-logboeken van Bassin en btc-rental zijn op 16 okt leeggemaakt (samen 18,8 GB spam); nuttige regels staan in `ckpool-tot-2026-10-16.log` ernaast.
- In de Umbrel zit een ongebruikte interne NVMe van 512 GB (`nvme0n1`, geen partities).

## PEP (Pepecoin) — live op de pools sinds 16 oktober 2026

- Pepecoin wordt als tweede extra munt naast DOGE onder dezelfde LTC-hashes gemined (chain merkle tree: DOGE 98 op plek 0, PEP 63 op plek 1). Zonder PEP-adres in de gebruikersnaam is het werk byte-identiek aan 1.7.0.
- **Feeadres (1%) en privépool:** `Pfe2U3n5GYXJd9TMAKNCGVhhSDyj35yjvj`, in de wallet van de Pepecoin Node zelf. Die wallet staat aan via de Umbrel-instelling `DISABLE_WALLET=0` (service pepecoind; blijft bij updates) en is versleuteld met een wachtwoord dat alleen de eigenaar heeft. `wallet.dat` zit in de uurlijkse back-up op de DigiEra. Uitbetalingen uit een blok zijn pas na 240 blokken uit te geven. Versturen (bijv. naar Kraken, dat PEP sinds 11-02-2026 heeft) doet de eigenaar zelf, in één keer boven Kraken's minimum: het feeadres zelf is bewust geen beursadres (100 PEP per blok kan onder het stortingsminimum vallen en gaat dan verloren).
- **Privépool** (Solo-app, 22557 en 22558): PEP_* in `~/umbrel/app-data/doge-dogecoin-solo/.env` sinds 16 okt 19:25 NL; elk PEP-blok gaat naar het feeadres.
- **Publiek 3335 en rental 3339**: 16 okt 19:31 NL opnieuw gestart op 1.8.0 met `~/pools-pep-uitrol.sh` (neemt de PEP_*-regels uit de privépool over en de containeropties uit `docker inspect`; valt bij een mislukte start zelf terug op 1.7.0). Kopieën: `~/doge-public*/env.voor-pep-*` en `inspect-voor-pep-*.json`.
- **Controle 16 okt:** `check_pools.py` 6× OK (99/1); van buitenaf met testadressen: zonder PEP-adres draagt de commitment 1 keten, met PEP-adres 2, op beide poorten; een ongeldig PEP-adres wordt geweigerd. Eerste echte PEP-blok nog nameten op 99/1.
- Gebruikersnaam: `LTC.DOGE[.PEP][.rig]`; met PEP-adres 99% van het eigen PEP-blok voor de miner, 1% voor ons. Eigen MRR-huur: zet het feeadres als derde deel in de MRR-gebruikersnaam om ook PEP te minen.
- Pepecoin uit of onbereikbaar: valt binnen seconden uit de jobs, LTC en DOGE lopen door (bewezen in CI met een gestopte pepecoind).
- **Nog te doen:** PEP-veld in de publieke stats-API (pool-overzicht) en daarna website-branch `feat/solo-pool-pep` in coin-bonus-finder mergen (pagina, statskop, voorwaarden, 9 talen; datum in de voorwaarden = livegangsdatum).

## Bewaking (node-watchdog)

- Losse container `node-watchdog` (bron: `node-watchdog/` in deze repo; op de Umbrel `~/node-watchdog`). Installeren of bijwerken: bestanden kopiëren en `sudo bash ~/node-watchdog/install.sh`.
- Elke minuut: BTC- en BCH-RPC bereikbaar, DOGE/LTC/PEP-healthcheck. 3 minuten geen antwoord terwijl de container draait → `docker restart` (hooguit 1× per 30 min per node). Bewust gestopte containers en de pools worden alleen gemeld, nooit herstart. ckpool-logboeken boven 2 GB worden leeggemaakt. Schijf onder 100 GB of CPU vanaf 92 °C: melding.
- Meldingen via ntfy (Android en iPhone). De topic staat alleen in `~/node-watchdog/config`; nieuwe maken met `bash ~/node-watchdog/new-topic.sh` (zonder tekens als l/1 en 0/o, die in de app op elkaar lijken).
- Logboek: `~/node-watchdog/watchdog.log`.

## Back-up

- Umbrel-back-up (Instellingen → Back-ups) naar de DigiEra 1 TB (USB aan de Umbrel, exFAT), map `umbrel-backup`, elk uur, versleuteld; wachtwoord in de wachtwoordbeheerder. Eerste back-up 16 okt 18:52 NL: 184 MB, de node-apps sluiten hun blockchains zelf uit. Kies bij het instellen nooit de map `.Spotlight-V100`: die is van macOS. Een eerdere poging (52,7 GB) staat in `DIGIERA/OUD-back-up-mag-weg` en mag weg.
- Wat buiten de apps staat (losse containers, scripts, fee-aanpassingen) zit niet vanzelf in de back-up. Er staat een kopie in Umbrel-bestanden **Home → Handwerk-backup**; na elke wijziging opnieuw kopiëren.

## Toegang

- Claude Code via Umbrel AI-agents (MCP): `http://umbrel.local/mcp`, token op de Mac in `~/.claude.json`. Machtigingen in Umbrel → Instellingen → AI-agents.
- SSH vanaf de Mac: `ssh -i ~/.ssh/id_ed25519_umbrel umbrel@192.168.1.149` (gebruik het IP: de oude `umbrel.local`-regels in known_hosts zijn van vóór umbrelOS 2.0). Docker vraagt sudo.
- De Umbrel draait op UTC; Nederlandse tijd is UTC+2 (zomer) / UTC+1 (winter).
