#!/usr/bin/env bash
# Build the ECW Expression Calculator from the repo root.
#
# Two conventional Lazarus projects share the engine unit ecwengine.pas:
#   ecw.lpi     / ecw.lpr       GUI project  -> ./ecw   (ecw.exe on Windows)
#   ec.lpi      / ec.lpr        CLI project  -> ./ec    (ec.exe on Windows)
#
# Usage:
#   ./build.sh               build the GUI   -> ./ecw
#   ./build.sh gui           build the GUI
#   ./build.sh cli           build the CLI   -> ./ec
# Extra arguments after the mode are forwarded to lazbuild
# (e.g. ./build.sh cli --os=win64 --cpu=x86_64).
set -euo pipefail
cd "$(dirname "$0")"

mode="${1:-gui}"
shift || true

case "$mode" in
  gui)
    lazbuild "$@" ecw.lpi
    ;;
  cli)
    lazbuild "$@" ec.lpi
    ;;
  *)
    echo "usage: $0 [gui|cli] [lazbuild options...]" >&2
    exit 2
    ;;
esac
