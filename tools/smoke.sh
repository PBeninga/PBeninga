#!/bin/sh
# Plays the real scene headlessly through every screen; fails on script errors.
G=${GODOT:-/opt/godot/Godot_v4.3-stable_linux.x86_64}
OUT=$(timeout 300 $G --headless --path . -- --script=smoke --fresh --frames=2 2>&1)
echo "$OUT" | grep -E "SMOKE|SCRIPT ERROR|ERROR" -A2 | grep -v -E "ALSA|audio|pulse|ERR_CANT_OPEN|init_output" | head -40
echo "$OUT" | grep -q "SHOT DONE" || { echo "smoke did not finish"; exit 1; }
echo "$OUT" | grep -q "SCRIPT ERROR" && exit 1
exit 0
