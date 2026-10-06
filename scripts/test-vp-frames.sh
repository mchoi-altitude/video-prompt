#!/bin/bash
# vp-frames contract checks (run against .build/debug/vp-frames and a real video).
B="$(dirname "$0")/../.build/debug/vp-frames"; V="${1:?usage: scripts/test-vp-frames.sh <video.mp4>}"; fail=0
o=$($B "$V" --from 0.05 --to 0.45 --fps 10); n=$(echo "$o" | wc -l); u=$(echo "$o" | sort -u | wc -l)
[ "$n" -eq "$u" ] && echo "PASS unique names ($n)" || { echo "FAIL duplicate names: $n lines, $u unique"; fail=1; }
$B "$V" --from abc --to 2 >/dev/null 2>&1; [ $? -eq 2 ] && echo "PASS bad number → exit 2" || { echo "FAIL bad number accepted"; fail=1; }
$B "$V" --from 0 --to 1 --bogus 3 >/dev/null 2>&1; [ $? -eq 2 ] && echo "PASS unknown flag → exit 2" || { echo "FAIL unknown flag accepted"; fail=1; }
n=$($B "$V" --from 0 --to 40 --fps 10 | wc -l); [ "$n" -le 100 ] && echo "PASS capped ($n)" || { echo "FAIL not capped ($n)"; fail=1; }
a=$($B "$V" --from 1 --to 1 | head -1); b=$($B "$V" --from 2 --to 2 | head -1)
[ "$(dirname "$a")" != "$(dirname "$b")" ] && echo "PASS fresh folder per call" || { echo "FAIL shared folder"; fail=1; }
exit $fail
