#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
test_dir=$(mktemp -d)
data_package="apt-install-fixture-data-$$"
lib_package="apt-install-fixture-lib-$$"
trap 'sudo dpkg --purge "$lib_package" "$data_package" >/dev/null 2>&1 || true; rm -r "$test_dir"' EXIT

build_package() {
  local package=$1
  local version=$2
  local control=$3
  local package_dir="$test_dir/build/$package-$version"

  mkdir -p "$package_dir/DEBIAN"
  printf 'Package: %s\nVersion: %s\nArchitecture: all\nMaintainer: Test Fixture <fixture@example.invalid>\nDescription: synthetic package for cached install testing\n%b' \
    "$package" "$version" "$control" > "$package_dir/DEBIAN/control"
  dpkg-deb --build "$package_dir" "$test_dir/$package-$version.deb" > /dev/null
}

build_package "$data_package" 1 ''
build_package "$lib_package" 1 "Depends: $data_package (>= 1)\n"
sudo dpkg -i "$test_dir/$data_package-1.deb" "$test_dir/$lib_package-1.deb" > /dev/null

mkdir -p "$test_dir/cache"
build_package "$data_package" 2 "Breaks: $lib_package (<< 2)\n"
build_package "$lib_package" 2 "Depends: $data_package (>= 2)\n"
cp "$test_dir/$data_package-2.deb" "$test_dir/$lib_package-2.deb" "$test_dir/cache/"

bash "$script_dir/install-cached.sh" "$test_dir/cache"

for package in "$data_package" "$lib_package"; do
  status=$(dpkg-query -W -f='${Status} ${Version}' "$package")
  if [ "$status" != 'install ok installed 2' ]; then
    printf 'Expected %s at version 2, got: %s\n' "$package" "$status" >&2
    exit 1
  fi
done

if [ -n "$(sudo dpkg --audit)" ]; then
  printf 'dpkg reported packages requiring attention after cached install\n' >&2
  exit 1
fi

printf 'cached apt install auto-deconfigure case passed\n'
