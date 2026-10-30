#!/bin/bash
# v0.9.4.1: локальный сервер + 2 клиента (тест вещей). $1 = "" | --touch. Логи: /workspace/testlogs/net_inv_*.log
cd "$(dirname "$0")/../.."
G=${G:-$HOME/tools/godot/Godot_v4.7.2-stable_linux.x86_64}
L=/workspace/testlogs; mkdir -p $L; rm -rf /tmp/fake_internal /tmp/it_*; M=${1:-}
python3 tests/net_local/fake_internal.py 7791 & FP=$!
RPG_TEST_LOOT=1 RPG_INTERNAL_URL=http://127.0.0.1:7791 RPG_INTERNAL_KEY=x timeout 330 $G --headless --path . res://scenes/server.tscn ++ --server > $L/net_inv_server$M.log 2>&1 & SP=$!
sleep 4
timeout 320 xvfb-run -a -s "-screen 0 1280x720x24" $G --path . --rendering-driver opengl3 --resolution 1280x720 res://tests/net_inv_test.tscn ++ --net-host=127.0.0.1 --user=it_a --lead $M > $L/net_inv_a$M.log 2>&1 & A=$!
sleep 2
timeout 320 xvfb-run -a -s "-screen 0 1280x720x24" $G --path . --rendering-driver opengl3 --resolution 1280x720 res://tests/net_inv_test.tscn ++ --net-host=127.0.0.1 --user=it_b $M > $L/net_inv_b$M.log 2>&1
wait $A; kill $SP $FP 2>/dev/null
rg -N "OK  |FAIL|RESULT|TIMEOUT|SCRIPT ERROR" $L/net_inv_a$M.log $L/net_inv_b$M.log
rg -c "SCRIPT ERROR" $L/net_inv_server$M.log
