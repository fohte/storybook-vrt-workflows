#!/usr/bin/env bash
set -euo pipefail

cache_dir=$1
shopt -s nullglob
debs=("$cache_dir"/*.deb)

if [ "${#debs[@]}" -gt 0 ]; then
  # dpkg refuses Breaks conflicts with installed packages without auto-deconfiguration.
  sudo dpkg -i --auto-deconfigure "${debs[@]}" || true
  # Configure again after all archives are unpacked because dpkg doesn't resolve install order.
  sudo dpkg --configure -a
fi
