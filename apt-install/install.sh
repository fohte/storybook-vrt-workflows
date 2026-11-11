#!/usr/bin/env bash
set -euo pipefail

sudo apt-get clean

max_attempts=3
for ((attempt = 1; attempt <= max_attempts; attempt++)); do
  if timeout --kill-after=30s 3m bash -c "$INSTALL_COMMAND"; then
    exit 0
  else
    status=$?
    echo "::warning::apt install attempt $attempt/$max_attempts failed with status $status"
    sudo pkill -x apt-get || true
  fi
done

exit 1
