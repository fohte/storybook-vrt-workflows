#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
test_dir=$(mktemp -d)
trap 'rm -r "$test_dir"' EXIT

mkdir "$test_dir/bin"
export EVENTS="$test_dir/events"
export ATTEMPTS="$test_dir/attempts"
export MODE
REAL_TIMEOUT=$(command -v timeout)
export REAL_TIMEOUT
export PATH="$test_dir/bin:$PATH"

cat > "$test_dir/bin/timeout" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "$1" != '--kill-after=30s' ] || [ "$2" != '3m' ]; then
  printf 'Unexpected timeout options: %s\n' "$*" >&2
  exit 2
fi
shift 2
"$REAL_TIMEOUT" --kill-after=1s 1s "$@"
EOF

cat > "$test_dir/bin/sudo" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "$1" = 'pkill' ]; then
  printf 'pkill\n' >> "$EVENTS"
  if [ "$2" != '-x' ] || [ "$3" != 'apt-get' ]; then
    printf 'Unexpected pkill arguments: %s\n' "$*" >&2
    exit 2
  fi
  exit 0
fi

exec "$@"
EOF

cat > "$test_dir/bin/apt-get" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "$1" = 'clean' ]; then
  printf 'clean\n' >> "$EVENTS"
  exit 0
fi

printf 'install\n' >> "$EVENTS"
attempt=$(cat "$ATTEMPTS")
attempt=$((attempt + 1))
printf '%s\n' "$attempt" > "$ATTEMPTS"

case "$MODE:$attempt" in
  hang_then_succeed:1) exec sleep 10 ;;
  hang_then_succeed:*) exit 0 ;;
  fail:*) exit 7 ;;
esac
EOF

chmod +x "$test_dir/bin/timeout" "$test_dir/bin/sudo" "$test_dir/bin/apt-get"

run_install() {
  : > "$EVENTS"
  printf '0\n' > "$ATTEMPTS"
  MODE=$1 INSTALL_COMMAND='sudo apt-get install fixture-package' bash "$script_dir/install.sh"
}

run_install_command() {
  : > "$EVENTS"
  printf '0\n' > "$ATTEMPTS"
  INSTALL_COMMAND=$1 bash "$script_dir/install.sh"
}

output_file="$test_dir/output"
if run_install hang_then_succeed > "$output_file" 2>&1; then
  :
else
  cat "$output_file" >&2
  printf 'Expected install to succeed after a timed-out attempt\n' >&2
  exit 1
fi

if [ "$(cat "$EVENTS")" != "clean
install
pkill
install" ]; then
  printf 'Unexpected retry event sequence:\n%s\n' "$(cat "$EVENTS")" >&2
  exit 1
fi

if ! grep -Fq '::warning::apt install attempt 1/3 failed' "$output_file"; then
  printf 'Expected a warning for the timed-out attempt\n' >&2
  exit 1
fi

if run_install fail > "$output_file" 2>&1; then
  printf 'Expected install to fail after all attempts\n' >&2
  exit 1
fi

if [ "$(cat "$EVENTS")" != "clean
install
pkill
install
pkill
install
pkill" ]; then
  printf 'Unexpected all-failed event sequence:\n%s\n' "$(cat "$EVENTS")" >&2
  exit 1
fi

warning_count=$(grep -c '::warning::apt install attempt' "$output_file")
if [ "$warning_count" -ne 3 ]; then
  printf 'Expected 3 warnings after all attempts fail, got %s\n' "$warning_count" >&2
  exit 1
fi

if run_install_command 'false | true; echo continued' > "$output_file" 2>&1; then
  printf 'Expected pipeline failure to trigger retries\n' >&2
  exit 1
fi

if [ "$(cat "$EVENTS")" != "clean
pkill
pkill
pkill" ]; then
  printf 'Expected pipefail and errexit to stop the command before its final statement:\n%s\n' "$(cat "$EVENTS")" >&2
  exit 1
fi

warning_count=$(grep -c '::warning::apt install attempt' "$output_file")
if [ "$warning_count" -ne 3 ]; then
  printf 'Expected 3 warnings for shell option failures, got %s\n' "$warning_count" >&2
  exit 1
fi

if grep -Fq continued "$output_file"; then
  printf 'Command continued after a failed pipeline\n' >&2
  exit 1
fi

printf 'apt install retry cases passed\n'
