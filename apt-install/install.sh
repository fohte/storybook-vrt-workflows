#!/usr/bin/env bash
set -euo pipefail

# Exclude unrelated runner and prior-call .debs from this cache; retries keep new downloads.
sudo apt-get clean

max_attempts=3
for ((attempt = 1; attempt <= max_attempts; attempt++)); do
  # A slow mirror can keep sending data, so apt's own inactivity timeout does not fire.
  if timeout --kill-after=30s 3m bash -eo pipefail -c "$INSTALL_COMMAND"; then
    exit 0
  else
    status=$?
    echo "::warning::apt install attempt $attempt/$max_attempts failed with status $status"
    # timeout cannot signal root-owned apt-get, which can keep the apt lock.
    sudo pkill -x apt-get || true
  fi
done

exit 1
