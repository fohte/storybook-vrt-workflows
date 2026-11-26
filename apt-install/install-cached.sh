#!/usr/bin/env bash
set -euo pipefail

cache_dir=$1
shopt -s nullglob
debs=("$cache_dir"/*.deb)

if [ "${#debs[@]}" -gt 0 ]; then
  sudo dpkg -i --auto-deconfigure "${debs[@]}" || true
  sudo dpkg --configure -a
fi
