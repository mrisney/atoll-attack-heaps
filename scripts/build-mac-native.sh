#!/usr/bin/env bash
# Native macOS build through HashLink/C. Needs: brew install haxe hashlink sdl2
# Produces bin/atoll, a normal arm64 (or x86_64) executable.
set -euo pipefail
cd "$(dirname "$0")/.."
haxe build-hlc.hxml
HL="$(brew --prefix hashlink)"
SDL="$(brew --prefix sdl2)"
LIB="$HL/lib"
mkdir -p bin
clang -O2 -std=c11 -o bin/atoll \
  -I out -I "$HL/include" out/main.c \
  -L"$LIB" -lhl "$LIB"/sdl.hdll "$LIB"/fmt.hdll "$LIB"/ui.hdll \
  -L"$SDL/lib" -lSDL2 \
  -Wl,-rpath,"$LIB"
echo "Built bin/atoll — run it with: ./bin/atoll"
