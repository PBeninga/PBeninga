#!/bin/sh
# Parse every script; print script errors only.
G=${GODOT:-/opt/godot/Godot_v4.3-stable_linux.x86_64}
timeout 120 $G --headless --path . --import 2>&1 | grep -A2 -E "SCRIPT ERROR|Parse Error" | grep -v "^--$" | head -40
