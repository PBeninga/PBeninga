#!/bin/sh
# Usage: tools/shot.sh <script> <out.png> [extra --key=value ...]
G=${GODOT:-/opt/godot/Godot_v4.3-stable_linux.x86_64}
S=$1; O=$2; shift 2
xvfb-run -a -s "-screen 0 1280x720x24" $G --path . --rendering-driver opengl3 --resolution 1280x720 -- --script=$S --shot=$O --fresh "$@" 2>&1 | grep -v -E "^$|Godot Engine|OpenGL API" | head -30
