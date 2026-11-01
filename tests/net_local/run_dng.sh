#!/bin/bash
# v0.9.5.2: локальный сервер + 2 клиента в одной группе в Склепе. $1 = "" | --touch. Логи: /workspace/testlogs/net_dng_*.log
cd "$(dirname "$0")/../.."
G=${G:-$HOME/tools/godot/Godot_v4.7.2-stable_linux.x86_64}
L=/workspace/testlogs; mkdir -p $L; rm -rf /tmp/fake_internal /tmp/dg_*; M=${1:-}
R=1280x720; [ "$M" = "--touch" ] && R=2400x1080
python3 tests/net_local/fake_internal.py 7791 & FP=$!
RPG_INTERNAL_URL=http://127.0.0.1:7791 RPG_INTERNAL_KEY=x timeout 300 $G --headless --path . res://scenes/server.tscn ++ --server > $L/net_dng_server$M.log 2>&1 & SP=$!
sleep 4
timeout 290 xvfb-run -a -s "-screen 0 ${R}x24" $G --path . --rendering-driver opengl3 --resolution $R res://tests/net_dng_test.tscn ++ --net-host=127.0.0.1 --user=dg_a --lead $M > $L/net_dng_a$M.log 2>&1 & A=$!
sleep 2
timeout 290 xvfb-run -a -s "-screen 0 ${R}x24" $G --path . --rendering-driver opengl3 --resolution $R res://tests/net_dng_test.tscn ++ --net-host=127.0.0.1 --user=dg_b $M > $L/net_dng_b$M.log 2>&1
wait $A; kill $SP $FP 2>/dev/null
rg -N "OK  |FAIL|RESULT|TIMEOUT|SCRIPT ERROR" $L/net_dng_a$M.log $L/net_dng_b$M.log
rg -N "склеп|вышел из|SCRIPT ERROR" $L/net_dng_server$M.log
