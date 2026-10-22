#!/bin/bash
# Meet 14 dagen lang elke 10 minuten het geheugen van beide ckpools (alleen lezen),
# om te zien of v1.2.0 (sinds 22-10-2026 15:52 UTC) nog blijft groeien.
# Uitvoer: ~/ckpool-geheugen.log (UTC). Stopt vanzelf.
for i in $(seq 1 2016); do
  r=""
  for p in $(pgrep -x ckpool); do
    m=$(awk "\$5==\"/config/ckpool.conf\"{print \"rental\"} \$5==\"/config\"{print \"bassin\"}" /proc/$p/mountinfo 2>/dev/null | head -1)
    r="$r $m=$(awk "/RssAnon/{a=int(\$2/1024)} /VmSwap/{s=int(\$2/1024)} END{print a\"+\"s}" /proc/$p/status 2>/dev/null)MB"
  done
  echo "$(date -u +%F_%H:%M)$r" >> ~/ckpool-geheugen.log
  sleep 600
done
